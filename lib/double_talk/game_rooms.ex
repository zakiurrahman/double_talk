defmodule DoubleTalk.GameRooms do
  @moduledoc false

  alias DoubleTalk.GameRooms.RoomServer

  @registry DoubleTalk.GameRooms.Registry
  @supervisor DoubleTalk.GameRooms.RoomSupervisor

  def create_room(host_attrs, mode \\ :undercover) do
    code = unique_code()

    case DynamicSupervisor.start_child(
           @supervisor,
           {RoomServer, code: code, host: host_attrs, mode: mode}
         ) do
      {:ok, _pid} -> {:ok, code}
      {:error, {:already_started, _pid}} -> create_room(host_attrs, mode)
      {:error, reason} -> {:error, reason}
    end
  end

  def subscribe(code) do
    Phoenix.PubSub.subscribe(DoubleTalk.PubSub, topic(code))
  end

  def topic(code), do: "room:#{normalize_code(code)}"

  def exists?(code), do: lookup_pid(code) != nil

  def join(code, attrs), do: with_room(code, &GenServer.call(&1, {:join, attrs}))
  def disconnect(code, player_id), do: maybe_call(code, {:disconnect, player_id})
  def leave(code, player_id), do: with_room(code, &GenServer.call(&1, {:leave, player_id}))

  def toggle_ready(code, player_id),
    do: with_room(code, &GenServer.call(&1, {:toggle_ready, player_id}))

  def start_match(code, player_id),
    do: with_room(code, &GenServer.call(&1, {:start_match, player_id}))

  def submit_clue(code, player_id, clue),
    do: with_room(code, &GenServer.call(&1, {:submit_clue, player_id, clue}))

  def cast_vote(code, player_id, target_id),
    do: with_room(code, &GenServer.call(&1, {:cast_vote, player_id, target_id}))

  def rematch(code, player_id), do: with_room(code, &GenServer.call(&1, {:rematch, player_id}))
  def get_view(code, viewer_id), do: with_room(code, &GenServer.call(&1, {:get_view, viewer_id}))

  def via_tuple(code), do: {:via, Registry, {@registry, normalize_code(code)}}

  defp normalize_code(code), do: code |> to_string() |> String.trim() |> String.upcase()

  defp with_room(code, fun) do
    case lookup_pid(code) do
      nil -> {:error, :room_not_found}
      pid -> fun.(pid)
    end
  end

  defp maybe_call(code, message) do
    case lookup_pid(code) do
      nil ->
        :ok

      pid ->
        GenServer.cast(pid, message)
        :ok
    end
  end

  defp lookup_pid(code) do
    code
    |> normalize_code()
    |> then(&Registry.lookup(@registry, &1))
    |> case do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp unique_code do
    code =
      4
      |> :crypto.strong_rand_bytes()
      |> Base.encode32(padding: false)
      |> binary_part(0, 4)

    if exists?(code), do: unique_code(), else: code
  end
end
