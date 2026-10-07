defmodule BlackShift.Fixtures do
  @moduledoc "Match states shared by simulation tests."
  alias BlackShift.Game

  @doc "Ranger `a` (team 0) against warden `b` (team 1), without spawn protection."
  def duel do
    "test"
    |> Game.new([%{id: "a", name: "A"}, %{id: "b", name: "B", class: "warden"}])
    |> unprotected()
  end

  @doc "Human `human` against bot `bot`, without structures or spawn protection."
  def versus_bot do
    s = Game.new("quality", [%{id: "human"}, %{id: "bot", bot: true}])
    unprotected(%{s | entities: %{}})
  end

  def place(s, id, x, y), do: update_in(s, [:players, id], &%{&1 | x: x, y: y})

  def steps(s, n), do: Enum.reduce(1..n, s, fn _, s -> Game.step(s) end)

  defp unprotected(s),
    do: %{s | players: Map.new(s.players, fn {id, p} -> {id, %{p | protected_until: 0}} end)}
end
