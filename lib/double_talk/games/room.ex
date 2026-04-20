defmodule DoubleTalk.Games.Room do
  @moduledoc false

  defstruct [
    :code,
    :host_id,
    :mode,
    :status,
    :current_round,
    :updated_at,
    players: %{},
    player_order: [],
    round_history: [],
    max_players: 10,
    min_players: 4,
    max_rounds: 5
  ]
end
