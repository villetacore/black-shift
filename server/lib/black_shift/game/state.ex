defmodule BlackShift.Game.State do
  @moduledoc "Small helpers shared by the simulation modules for updating the match state value."

  def update_player(s, id, fun), do: update_in(s, [:players, id], fun)

  def update_entity(s, id, fun), do: update_in(s, [:entities, id], fun)

  def add_score(s, team, amount),
    do: %{s | score: List.update_at(s.score, team, &(&1 + amount))}

  @doc "Appends a kill-feed line, keeping the last four."
  def feed(s, text), do: %{s | feed: Enum.take(s.feed ++ [text], -4)}

  @doc "Entity ids in a stable order, so simulation results do not depend on map ordering."
  def entity_ids(s), do: s.entities |> Map.keys() |> Enum.sort()
end
