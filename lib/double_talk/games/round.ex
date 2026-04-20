defmodule DoubleTalk.Games.Round do
  @moduledoc false

  defstruct [
    :round_number,
    :phase,
    :phase_started_at,
    :phase_ends_at,
    :current_turn_index,
    :current_turn_player_id,
    :prompt,
    :result,
    assignments: %{},
    clues: [],
    votes: %{}
  ]
end
