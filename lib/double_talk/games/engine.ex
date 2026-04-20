defmodule DoubleTalk.Games.Engine do
  @moduledoc false

  alias DoubleTalk.Games.{Player, Room, Round, WordPack}

  @role_reveal_ms 8_000
  @clue_turn_ms 20_000
  @discussion_ms 35_000
  @voting_ms 20_000
  @round_result_ms 12_000

  def new_room(code, host_attrs, mode, now \\ DateTime.utc_now()) do
    host =
      %Player{
        id: host_attrs.id,
        name: sanitize_name(host_attrs.name),
        joined_at: now
      }

    %Room{
      code: normalize_code(code),
      host_id: host.id,
      mode: normalize_mode(mode),
      status: :lobby,
      updated_at: now,
      players: %{host.id => host},
      player_order: [host.id]
    }
  end

  def apply_command(room, command, now \\ DateTime.utc_now())

  def apply_command(room, {:join_player, attrs}, now) do
    id = attrs.id
    name = sanitize_name(attrs.name)
    existing = room.players[id]

    cond do
      existing ->
        updated_player =
          existing
          |> Map.put(:connected?, true)
          |> maybe_update_name(name)

        {:ok, %{room | players: Map.put(room.players, id, updated_player), updated_at: now}}

      room.status != :lobby ->
        {:error, :match_in_progress}

      map_size(room.players) >= room.max_players ->
        {:error, :room_full}

      name == "" ->
        {:error, :nickname_required}

      true ->
        player = %Player{id: id, name: name, connected?: true, joined_at: now}

        {:ok,
         %{
           room
           | players: Map.put(room.players, id, player),
             player_order: room.player_order ++ [id],
             updated_at: now
         }}
    end
  end

  def apply_command(room, {:disconnect_player, player_id}, now) do
    {:ok, update_player(room, player_id, &Map.put(&1, :connected?, false), now)}
  end

  def apply_command(room, {:leave_player, player_id}, now) do
    if room.status != :lobby or not Map.has_key?(room.players, player_id) do
      {:error, :cannot_leave_now}
    else
      players = Map.delete(room.players, player_id)
      player_order = Enum.reject(room.player_order, &(&1 == player_id))
      host_id = if room.host_id == player_id, do: List.first(player_order), else: room.host_id

      {:ok,
       %{room | players: players, player_order: player_order, host_id: host_id, updated_at: now}}
    end
  end

  def apply_command(room, {:toggle_ready, player_id}, now) do
    cond do
      room.status != :lobby ->
        {:error, :match_in_progress}

      not Map.has_key?(room.players, player_id) ->
        {:error, :unknown_player}

      true ->
        {:ok,
         update_player(
           room,
           player_id,
           &Map.update!(&1, :ready?, fn ready? -> not ready? end),
           now
         )}
    end
  end

  def apply_command(room, {:start_match, player_id}, now) do
    cond do
      room.status != :lobby ->
        {:error, :already_started}

      room.host_id != player_id ->
        {:error, :not_host}

      length(room.player_order) < room.min_players ->
        {:error, :not_enough_players}

      not Enum.all?(room.players, fn {_id, player} -> player.ready? end) ->
        {:error, :players_not_ready}

      true ->
        {:ok, start_match(room, now)}
    end
  end

  def apply_command(%Room{current_round: nil}, {:submit_clue, _player_id, _clue}, _now),
    do: {:error, :no_match}

  def apply_command(%Room{current_round: nil}, {:cast_vote, _player_id, _target_id}, _now),
    do: {:error, :no_match}

  def apply_command(%Room{current_round: nil}, {:rematch, _player_id}, _now),
    do: {:error, :no_match}

  def apply_command(room, {:submit_clue, player_id, clue_text}, now) do
    round = room.current_round
    clue = sanitize_clue(clue_text)

    cond do
      round.phase != :clue_turn -> {:error, :wrong_phase}
      round.current_turn_player_id != player_id -> {:error, :not_your_turn}
      clue == "" -> {:error, :invalid_clue}
      true -> {:ok, room |> record_clue(player_id, clue, false, now) |> advance_after_clue(now)}
    end
  end

  def apply_command(room, {:cast_vote, player_id, target_id}, now) do
    round = room.current_round

    cond do
      round.phase != :voting ->
        {:error, :wrong_phase}

      not Map.has_key?(room.players, player_id) ->
        {:error, :unknown_player}

      target_id == player_id ->
        {:error, :cannot_vote_self}

      not Map.has_key?(room.players, target_id) ->
        {:error, :unknown_target}

      Map.has_key?(round.votes, player_id) ->
        {:error, :already_voted}

      true ->
        updated_round = %{round | votes: Map.put(round.votes, player_id, target_id)}
        room = %{room | current_round: updated_round, updated_at: now}

        if map_size(updated_round.votes) == length(room.player_order) do
          {:ok, resolve_round(room, now)}
        else
          {:ok, room}
        end
    end
  end

  def apply_command(room, {:rematch, player_id}, now) do
    if room.current_round.phase == :match_result and room.host_id == player_id do
      players =
        Map.new(room.players, fn {id, player} ->
          {id, %{player | ready?: false, score: 0}}
        end)

      {:ok,
       %{
         room
         | status: :lobby,
           current_round: nil,
           round_history: [],
           players: players,
           updated_at: now
       }}
    else
      {:error, :cannot_rematch}
    end
  end

  def advance_timeout(room, now \\ DateTime.utc_now())
  def advance_timeout(%Room{current_round: nil} = room, _now), do: {:ok, room}

  def advance_timeout(%Room{} = room, now) do
    round = room.current_round

    next_room =
      case round.phase do
        :role_reveal ->
          %{room | current_round: begin_clue_turn(round, room.player_order, now), updated_at: now}

        :clue_turn ->
          room
          |> record_clue(round.current_turn_player_id, "Timed out", true, now)
          |> advance_after_clue(now)

        :discussion ->
          %{room | current_round: begin_voting(round, now), updated_at: now}

        :voting ->
          resolve_round(room, now)

        :round_result ->
          advance_after_round_result(room, now)

        :match_result ->
          room
      end

    {:ok, next_room}
  end

  defp normalize_code(code), do: code |> to_string() |> String.trim() |> String.upcase()

  defp normalize_mode(mode) when mode in [:undercover, :spy], do: mode
  defp normalize_mode("spy"), do: :spy
  defp normalize_mode(_), do: :undercover

  defp sanitize_name(nil), do: ""

  defp sanitize_name(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.slice(0, 24)
  end

  defp sanitize_clue(clue) do
    clue
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 28)
  end

  defp maybe_update_name(player, ""), do: player
  defp maybe_update_name(player, name), do: %{player | name: name}

  defp update_player(room, player_id, fun, now) do
    case room.players[player_id] do
      nil -> room
      player -> %{room | players: Map.put(room.players, player_id, fun.(player)), updated_at: now}
    end
  end

  defp start_match(room, now) do
    players =
      Map.new(room.players, fn {id, player} ->
        {id, %{player | score: 0, connected?: true}}
      end)

    round = build_round(room.mode, room.player_order, 1, room.max_rounds, now)

    %{
      room
      | status: :in_match,
        players: players,
        current_round: round,
        round_history: [],
        updated_at: now
    }
  end

  defp build_round(mode, player_order, round_number, max_rounds, now) do
    prompt = WordPack.draw(mode)

    hidden_ids =
      player_order |> Enum.shuffle() |> Enum.take(hidden_count(mode, length(player_order)))

    assignments =
      Map.new(player_order, fn player_id ->
        assignment =
          case mode do
            :undercover ->
              if player_id in hidden_ids do
                %{role: :undercover, word: prompt.undercover_word}
              else
                %{role: :civilian, word: prompt.civilian_word}
              end

            :spy ->
              if player_id in hidden_ids do
                %{role: :spy, word: nil}
              else
                %{role: :detective, word: prompt.location}
              end
          end

        {player_id, assignment}
      end)

    %Round{
      round_number: round_number,
      phase: :role_reveal,
      phase_started_at: now,
      phase_ends_at: shift_ms(now, @role_reveal_ms),
      current_turn_index: nil,
      current_turn_player_id: nil,
      assignments: assignments,
      clues: [],
      votes: %{},
      prompt: Map.put(prompt, :max_rounds, max_rounds),
      result: nil
    }
  end

  defp hidden_count(:undercover, player_count) when player_count >= 8, do: 2
  defp hidden_count(_, _), do: 1

  defp begin_clue_turn(round, player_order, now) do
    %{
      round
      | phase: :clue_turn,
        phase_started_at: now,
        phase_ends_at: shift_ms(now, @clue_turn_ms),
        current_turn_index: 0,
        current_turn_player_id: List.first(player_order)
    }
  end

  defp begin_discussion(round, now) do
    %{
      round
      | phase: :discussion,
        phase_started_at: now,
        phase_ends_at: shift_ms(now, @discussion_ms),
        current_turn_index: nil,
        current_turn_player_id: nil
    }
  end

  defp begin_voting(round, now) do
    %{
      round
      | phase: :voting,
        phase_started_at: now,
        phase_ends_at: shift_ms(now, @voting_ms)
    }
  end

  defp record_clue(room, player_id, clue, timed_out?, now) do
    round = room.current_round

    entry = %{
      player_id: player_id,
      text: clue,
      timed_out?: timed_out?,
      inserted_at: now
    }

    %{room | current_round: %{round | clues: round.clues ++ [entry]}, updated_at: now}
  end

  defp advance_after_clue(room, now) do
    round = room.current_round
    next_index = round.current_turn_index + 1

    if next_index >= length(room.player_order) do
      %{room | current_round: begin_discussion(round, now), updated_at: now}
    else
      next_player_id = Enum.at(room.player_order, next_index)

      %{
        room
        | current_round: %{
            round
            | current_turn_index: next_index,
              current_turn_player_id: next_player_id,
              phase_started_at: now,
              phase_ends_at: shift_ms(now, @clue_turn_ms)
          },
          updated_at: now
      }
    end
  end

  defp resolve_round(room, now) do
    round = room.current_round
    tally = Enum.frequencies(Map.values(round.votes))
    hidden_ids = hidden_ids(round)

    unique_top_target =
      case Enum.sort_by(tally, fn {player_id, votes} -> {-votes, player_id} end) do
        [] ->
          nil

        [{player_id, votes} | rest] ->
          if Enum.any?(rest, fn {_other_id, other_votes} -> other_votes == votes end) do
            nil
          else
            player_id
          end
      end

    winner =
      if unique_top_target && unique_top_target in hidden_ids do
        :seekers
      else
        :hidden
      end

    winning_ids =
      case winner do
        :seekers -> room.player_order -- hidden_ids
        :hidden -> hidden_ids
      end

    players =
      Map.new(room.players, fn {id, player} ->
        score = if id in winning_ids, do: player.score + 1, else: player.score
        {id, %{player | score: score}}
      end)

    result = %{
      winner: winner,
      hidden_ids: hidden_ids,
      vote_tally: tally,
      top_target_id: unique_top_target,
      revealed_roles: round.assignments
    }

    updated_round = %{
      round
      | phase: :round_result,
        phase_started_at: now,
        phase_ends_at: shift_ms(now, @round_result_ms),
        result: result
    }

    %{
      room
      | players: players,
        current_round: updated_round,
        round_history: room.round_history ++ [result],
        updated_at: now
    }
  end

  defp advance_after_round_result(room, now) do
    round = room.current_round

    if round.round_number >= room.max_rounds do
      %{
        room
        | current_round: %{
            round
            | phase: :match_result,
              phase_started_at: now,
              phase_ends_at: nil
          },
          updated_at: now
      }
    else
      next_round =
        build_round(room.mode, room.player_order, round.round_number + 1, room.max_rounds, now)

      %{room | current_round: next_round, updated_at: now}
    end
  end

  defp hidden_ids(round) do
    for {player_id, %{role: role}} <- round.assignments,
        role in [:undercover, :spy],
        do: player_id
  end

  defp shift_ms(datetime, ms) do
    DateTime.add(datetime, ms, :millisecond)
  end
end
