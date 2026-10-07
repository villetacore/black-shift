defmodule BlackShift.Game.StructuresTest do
  use ExUnit.Case, async: true
  alias BlackShift.Game

  test "clearing both drones awards the wave bonus once, even after pruning" do
    s = Game.new("waves", [%{id: "a"}, %{id: "b"}]) |> Game.step()
    ids = for {id, e} <- s.entities, e.kind == "drone" and e.team == 1, do: id
    [first, last] = ids
    s = BlackShift.Game.Combat.hurt_entity(s, first, 999, "a") |> Game.step()
    assert s.score == [3, 0]
    s = BlackShift.Game.Combat.hurt_entity(s, last, 999, "a")
    assert s.score == [10, 0]
    assert BlackShift.Game.Combat.hurt_entity(s, last, 999, "a").score == [10, 0]
  end

  test "tower acquisition is signalled before damage" do
    s = Game.new("telegraph", [%{id: "human"}, %{id: "enemy"}])
    p = %{s.players["human"] | x: 50.5, y: 21.5, protected_until: 0}

    s = %{
      s
      | players: Map.put(s.players, "human", p),
        entities: Map.take(s.entities, ["tower-1"]),
        tick: 1
    }

    s = Game.step(s)
    assert s.players["human"].hp == 100
    tower = hd(Game.snapshot(s).entities)
    assert tower.warning
    assert tower.target == "human"
  end
end
