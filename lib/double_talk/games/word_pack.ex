defmodule DoubleTalk.Games.WordPack do
  @moduledoc false

  @undercover_pairs [
    {"Beach", "Island"},
    {"Coffee", "Espresso"},
    {"Pirate", "Ninja"},
    {"Laptop", "Tablet"},
    {"Forest", "Jungle"},
    {"Train", "Subway"},
    {"Concert", "Festival"},
    {"Whale", "Dolphin"},
    {"Castle", "Palace"},
    {"Tennis", "Badminton"},
    {"Volcano", "Mountain"},
    {"Breakfast", "Brunch"}
  ]

  @spy_locations [
    "Airport",
    "Hospital",
    "Museum",
    "Movie Set",
    "Submarine",
    "Casino",
    "Cruise Ship",
    "Space Station",
    "School",
    "Art Gallery",
    "Train Station",
    "Embassy"
  ]

  def draw(:undercover) do
    {civilian_word, undercover_word} = Enum.random(@undercover_pairs)

    %{
      deck: :undercover,
      category: "Related words",
      public_hint: "Most players share a word. Hidden players get a similar one.",
      civilian_word: civilian_word,
      undercover_word: undercover_word
    }
  end

  def draw(:spy) do
    location = Enum.random(@spy_locations)

    %{
      deck: :spy,
      category: "Location",
      public_hint: "Most players know the location. The spy gets nothing.",
      location: location
    }
  end
end
