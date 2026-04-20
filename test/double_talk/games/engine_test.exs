defmodule DoubleTalk.Games.EngineTest do
  use ExUnit.Case, async: true

  alias DoubleTalk.Games.Engine
  alias DoubleTalk.Games.Engine.Projector

  test "match start assigns secrets and keeps them private to each player" do
    room =
      "ABCD"
      |> seeded_room()
      |> ready_everyone()
      |> start_match()

    assert room.status == :in_match
    assert room.current_round.phase == :role_reveal
    assert map_size(room.current_round.assignments) == 4

    player_one_view = Projector.project(room, "p1")
    player_two_view = Projector.project(room, "p2")

    assert player_one_view.viewer.secret.role in [:civilian, :undercover]
    assert player_one_view.viewer.secret.word
    assert Enum.all?(player_one_view.players, &is_nil(&1.revealed_role))
    assert player_two_view.viewer.secret.role in [:civilian, :undercover]
  end

  test "a unique vote on the hidden player gives the seekers the round" do
    room =
      "WXYZ"
      |> seeded_room()
      |> ready_everyone()
      |> start_match()
      |> advance_timeout()

    assert room.current_round.phase == :clue_turn

    room =
      Enum.reduce(room.player_order, room, fn player_id, acc ->
        submit_clue(acc, player_id, "clue-#{player_id}")
      end)

    assert room.current_round.phase == :discussion

    room = advance_timeout(room)
    assert room.current_round.phase == :voting

    hidden_player_id =
      room.current_round.assignments
      |> Enum.find(fn {_id, assignment} -> assignment.role == :undercover end)
      |> elem(0)

    voters = Enum.reject(room.player_order, &(&1 == hidden_player_id))

    room =
      Enum.reduce(voters, room, fn player_id, acc ->
        cast_vote(acc, player_id, hidden_player_id)
      end)

    room = cast_vote(room, hidden_player_id, List.first(voters))

    assert room.current_round.phase == :round_result
    assert room.current_round.result.winner == :seekers

    seekers = room.player_order -- [hidden_player_id]
    assert Enum.all?(seekers, &(room.players[&1].score == 1))
    assert room.players[hidden_player_id].score == 0
  end

  defp seeded_room(code) do
    host = %{id: "p1", name: "Alpha"}
    room = Engine.new_room(code, host, :undercover, now())

    room
    |> join("p2", "Bravo")
    |> join("p3", "Charlie")
    |> join("p4", "Delta")
  end

  defp ready_everyone(room) do
    Enum.reduce(room.player_order, room, fn player_id, acc ->
      {:ok, room} = Engine.apply_command(acc, {:toggle_ready, player_id}, now())
      room
    end)
  end

  defp start_match(room) do
    {:ok, room} = Engine.apply_command(room, {:start_match, "p1"}, now())
    room
  end

  defp submit_clue(room, player_id, clue) do
    {:ok, room} = Engine.apply_command(room, {:submit_clue, player_id, clue}, now())
    room
  end

  defp cast_vote(room, player_id, target_id) do
    {:ok, room} = Engine.apply_command(room, {:cast_vote, player_id, target_id}, now())
    room
  end

  defp advance_timeout(room) do
    {:ok, room} = Engine.advance_timeout(room, now())
    room
  end

  defp join(room, player_id, name) do
    {:ok, room} = Engine.apply_command(room, {:join_player, %{id: player_id, name: name}}, now())
    room
  end

  defp now, do: DateTime.utc_now()
end
