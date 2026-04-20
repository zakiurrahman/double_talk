defmodule DoubleTalk.Games.Engine.Projector do
  @moduledoc false

  def project(room, viewer_id) do
    viewer = room.players[viewer_id]
    round = room.current_round
    clues_by_player = if round, do: Map.new(round.clues, &{&1.player_id, &1}), else: %{}
    revealed? = round && round.phase in [:round_result, :match_result]
    assignment = round && round.assignments[viewer_id]

    %{
      room_code: room.code,
      mode: room.mode,
      status: room.status,
      host_id: room.host_id,
      viewer_id: viewer_id,
      joined?: not is_nil(viewer),
      viewer: %{
        id: viewer_id,
        name: viewer && viewer.name,
        ready?: viewer && viewer.ready?,
        connected?: viewer && viewer.connected?,
        secret: project_secret(round, assignment)
      },
      players:
        Enum.map(room.player_order, fn player_id ->
          player = room.players[player_id]
          player_assignment = if revealed? && round, do: round.assignments[player_id], else: nil

          %{
            id: player.id,
            name: player.name,
            ready?: player.ready?,
            connected?: player.connected?,
            score: player.score,
            clue: clues_by_player[player_id],
            has_voted?: round && Map.has_key?(round.votes, player_id),
            revealed_role: player_assignment && player_assignment.role,
            revealed_word: player_assignment && player_assignment.word
          }
        end),
      round: project_round(room, round),
      can: %{
        join: room.status == :lobby and is_nil(viewer),
        toggle_ready: room.status == :lobby and not is_nil(viewer),
        start_match: room.status == :lobby and viewer_id == room.host_id,
        submit_clue:
          round && round.phase == :clue_turn && round.current_turn_player_id == viewer_id,
        vote: round && round.phase == :voting && not is_nil(viewer),
        rematch: round && round.phase == :match_result && viewer_id == room.host_id
      },
      room_rules: %{
        min_players: room.min_players,
        max_players: room.max_players,
        max_rounds: room.max_rounds
      }
    }
  end

  defp project_round(_room, nil), do: nil

  defp project_round(room, round) do
    %{
      round_number: round.round_number,
      phase: round.phase,
      phase_started_at: round.phase_started_at,
      phase_ends_at: round.phase_ends_at,
      current_turn_player_id: round.current_turn_player_id,
      prompt: %{
        category: round.prompt.category,
        public_hint: round.prompt.public_hint
      },
      clues:
        Enum.map(round.clues, fn clue ->
          %{
            player_id: clue.player_id,
            player_name: room.players[clue.player_id].name,
            text: clue.text,
            timed_out?: clue.timed_out?
          }
        end),
      votes: round.phase in [:round_result, :match_result] && round.votes,
      result: round.result
    }
  end

  defp project_secret(nil, _assignment), do: nil
  defp project_secret(_round, nil), do: nil

  defp project_secret(round, assignment) do
    %{
      role: assignment.role,
      word: assignment.word,
      visible?:
        round.phase in [
          :role_reveal,
          :clue_turn,
          :discussion,
          :voting,
          :round_result,
          :match_result
        ]
    }
  end
end
