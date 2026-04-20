defmodule DoubleTalk.Games.Player do
  @moduledoc false

  @enforce_keys [:id, :name]
  defstruct [:id, :name, ready?: false, connected?: false, score: 0, joined_at: nil]
end
