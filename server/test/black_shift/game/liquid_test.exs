defmodule BlackShift.Game.LiquidTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.Game.{Liquid, Physics, Combat}
  alias BlackShift.Game

  test "liquids are bounded in all three dimensions" do
    assert Liquid.at(32, 2, 0)["id"] == "cooling-water"
    assert Liquid.at(32, 2, 2) == nil
    assert Liquid.at(30, 2, 0) == nil
    assert Liquid.at(32, 2, -3) == nil
  end

  test "deep water arrests a fall and floats the player without passing through the floor" do
    p = %{duel().players["a"] | x: 32.0, y: 2.0, z: 1.0, vz: -12.0, grounded: false}
    p = Enum.reduce(1..100, p, fn tick, p -> Physics.fall(p, false, tick) end)
    assert p.z > 0.3 and p.z < 1.4
    assert abs(p.vz) < 0.1
    assert Physics.fall(p, true, 101).z > p.z
  end

  test "shallow water slows walking and applies a current but allows jumping" do
    s = duel() |> place("a", 40, 40)
    wet = s |> Game.set_input("a", %{"forward" => 1, "sprint" => true}) |> Game.step()
    assert wet.players["a"].x > 40
    assert wet.players["a"].x < 40.17
    refute wet.players["a"].sprinting
    jumped = s |> Game.set_input("a", %{"jump" => true}) |> Game.step()
    assert jumped.players["a"].z > 0.3
  end

  test "held swim exits the cooling basin using its authored steps" do
    s = duel() |> place("a", 32, 1.9)
    s = Game.set_input(s, "a", %{"forward" => 1, "swim" => true})

    s =
      Enum.reduce(1..130, s, fn _, s ->
        s |> Game.set_input("a", %{"forward" => 1, "swim" => true}) |> Game.step()
      end)

    assert s.players["a"].x > 38.5
    assert s.players["a"].z >= 0.0
  end

  test "shotgun pellets, cooldown and close-range damage are authoritative" do
    s = duel() |> place("b", 7.5, 10.5) |> place("a", 9.5, 10.5)
    s = put_in(s, [:players, "b", :angle], 0.0)
    fired = Combat.shoot(s, "b")
    assert length(fired.beams) == 8
    assert fired.players["a"].hp in 10..40
    assert fired.players["b"].fire_at == 16
    assert fired.players["b"].ammo == 5
    assert Combat.shoot(fired, "b") == fired
    blocked = s |> place("b", 1.5, 9.5) |> place("a", 5.5, 9.5) |> Combat.shoot("b")
    assert blocked.players["a"].hp == 100
  end
end
