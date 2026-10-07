defmodule BlackShift.Game.ElevationTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.Game.{Physics, Structures, Supplies}
  alias BlackShift.Game

  test "a bot follows a ramp route to the upper relay using real movement" do
    s = Game.new("upper", [%{id: "bot", bot: true}, %{id: "enemy"}])
    s = %{s | tick: 3601, entities: %{}} |> place("enemy", 55.5, 21.5) |> place("bot", 18.5, 10.5)

    result =
      Enum.reduce_while(1..600, s, fn _, state ->
        next = Game.step(state)
        if next.players["bot"].z > 2.2 and next.relay == 0, do: {:halt, next}, else: {:cont, next}
      end)

    assert result.players["bot"].z > 2.2
    assert result.relay == 0
  end

  test "drone movement preserves height and beam origins follow its floor" do
    s = duel() |> Game.step()

    id =
      Enum.find_value(s.entities, fn {id, e} -> if e.kind == "drone" and e.team == 0, do: id end)

    drone = %{
      s.entities[id]
      | x: 33.5,
        y: 22.5,
        z: 3.0,
        route_at: 999,
        route: [{34.5, 22.5, 3.0}]
    }

    s = %{s | entities: Map.put(s.entities, id, drone)}
    moved = Structures.step(%{s | tick: 2}).entities[id]
    assert moved.z == 3.0
    assert moved.x > drone.x
    assert Physics.aim_height(moved) == 3.4
  end

  test "health pickup on loading terrace cannot be collected from underneath" do
    s = duel() |> place("a", 55.5, 37.5) |> put_in([:players, "a", :hp], 20)
    assert Supplies.step(s).players["a"].hp == 20
    s = put_in(s, [:players, "a", :z], 1.2)
    assert Supplies.step(s).players["a"].hp == 65
  end
end
