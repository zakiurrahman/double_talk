defmodule DoubleTalk.GameRooms.RoomServer do
  @moduledoc false

  use GenServer

  alias DoubleTalk.GameRooms
  alias DoubleTalk.Games.Engine
  alias DoubleTalk.Games.Engine.Projector

  def start_link(opts) do
    code = Keyword.fetch!(opts, :code)
    GenServer.start_link(__MODULE__, opts, name: GameRooms.via_tuple(code))
  end

  @impl true
  def init(opts) do
    room =
      Engine.new_room(
        Keyword.fetch!(opts, :code),
        Keyword.fetch!(opts, :host),
        Keyword.get(opts, :mode, :undercover)
      )

    {:ok, schedule_timeout(%{room: room, timer_ref: nil})}
  end

  @impl true
  def handle_call({:get_view, viewer_id}, _from, state) do
    {:reply, {:ok, Projector.project(state.room, viewer_id)}, state}
  end

  def handle_call({:join, attrs}, _from, state), do: apply_and_reply(state, {:join_player, attrs})

  def handle_call({:leave, player_id}, _from, state),
    do: apply_and_reply(state, {:leave_player, player_id})

  def handle_call({:toggle_ready, player_id}, _from, state),
    do: apply_and_reply(state, {:toggle_ready, player_id})

  def handle_call({:start_match, player_id}, _from, state),
    do: apply_and_reply(state, {:start_match, player_id})

  def handle_call({:submit_clue, player_id, clue}, _from, state),
    do: apply_and_reply(state, {:submit_clue, player_id, clue})

  def handle_call({:cast_vote, player_id, target_id}, _from, state),
    do: apply_and_reply(state, {:cast_vote, player_id, target_id})

  def handle_call({:rematch, player_id}, _from, state),
    do: apply_and_reply(state, {:rematch, player_id})

  @impl true
  def handle_cast({:disconnect, player_id}, state) do
    {:ok, room} = Engine.apply_command(state.room, {:disconnect_player, player_id})
    state = schedule_timeout(%{state | room: room})
    broadcast(room.code)
    {:noreply, state}
  end

  @impl true
  def handle_info(:phase_timeout, state) do
    now = DateTime.utc_now()

    case state.room.current_round do
      %{phase_ends_at: %DateTime{} = phase_ends_at} ->
        if DateTime.compare(now, phase_ends_at) in [:eq, :gt] do
          {:ok, room} = Engine.advance_timeout(state.room, now)
          state = schedule_timeout(%{state | room: room})
          broadcast(room.code)
          {:noreply, state}
        else
          {:noreply, schedule_timeout(state)}
        end

      _round ->
        {:noreply, %{state | timer_ref: nil}}
    end
  end

  defp apply_and_reply(state, command) do
    case Engine.apply_command(state.room, command, DateTime.utc_now()) do
      {:ok, room} ->
        state = schedule_timeout(%{state | room: room})
        broadcast(room.code)
        {:reply, {:ok, room}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp schedule_timeout(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    case state.room.current_round do
      %{phase_ends_at: %DateTime{} = phase_ends_at} ->
        ms = max(DateTime.diff(phase_ends_at, DateTime.utc_now(), :millisecond), 0)
        %{state | timer_ref: Process.send_after(self(), :phase_timeout, ms + 10)}

      _round ->
        %{state | timer_ref: nil}
    end
  end

  defp broadcast(code) do
    Phoenix.PubSub.broadcast(DoubleTalk.PubSub, GameRooms.topic(code), {:room_updated, code})
  end
end
