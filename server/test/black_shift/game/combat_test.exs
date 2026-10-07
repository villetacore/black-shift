defmodule BlackShift.Game.CombatTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.Game
  alias BlackShift.Game.{Combat, Weapons}

  # An open firing lane along y = 14.5.
  defp lane(ax, bx), do: duel() |> place("a", ax, 14.5) |> place("b", bx, 14.5)

  defp aim(s, id, pitch), do: put_in(s, [:players, id, :pitch], pitch)

  test "pitch changes 3D hits and bullets can pass over low cover" do
    s = duel() |> place("a", 7.5, 10.5) |> place("b", 9.5, 10.5)
    assert Combat.shoot(s, "a").players["b"].hp == 81
    upward = put_in(s, [:players, "a", :pitch], 1.0) |> Combat.shoot("a")
    assert upward.players["b"].hp == 100
    assert hd(upward.beams).ez > hd(upward.beams).z
  end

  test "shots are occluded and weapon cooldown is authoritative" do
    s = duel() |> place("a", 1.5, 9.5) |> place("b", 5.5, 9.5) |> Combat.shoot("a")
    assert s.players["b"].hp == 100
    s = %{s | tick: 10} |> place("a", 10.5, 10.5) |> place("b", 12.5, 10.5) |> Combat.shoot("a")
    assert s.players["b"].hp == 81
    assert Combat.shoot(s, "a").players["b"].hp == 81
  end

  test "head, torso and legs take different damage" do
    s = lane(5.5, 7.5)
    # Eye at 1.48 m: aim at the head (~1.7 m), torso (level) and legs (~0.4 m) two metres away.
    head = s |> aim("a", 0.11) |> Combat.shoot("a")
    torso = Combat.shoot(s, "a")
    legs = s |> aim("a", -0.48) |> Combat.shoot("a")
    assert 100 - head.players["b"].hp == 34
    assert 100 - torso.players["b"].hp == 19
    assert 100 - legs.players["b"].hp == 14
    assert head.players["a"].hit_head and head.players["a"].hits == 1
    refute torso.players["a"].hit_head
  end

  test "damage falls off with distance and stops at the weapon's range" do
    near = lane(5.5, 13.5) |> Combat.shoot("a")
    far = lane(5.5, 25.5) |> Combat.shoot("a")
    out = lane(3.5, 35.5) |> Combat.shoot("a")
    assert 100 - near.players["b"].hp == 19
    assert (100 - far.players["b"].hp) in 12..15
    assert out.players["b"].hp == 100
  end

  test "a crouching target ducks under a shot aimed at a standing head" do
    s = lane(5.5, 7.5) |> aim("a", 0.11)
    s = put_in(s, [:players, "b", :crouching], true)
    assert Combat.shoot(s, "a").players["b"].hp == 100
  end

  test "magazines empty, block fire while reloading and refill after the reload time" do
    w = Weapons.spec("ranger")
    s = lane(5.5, 30.5) |> aim("a", 0.5)

    s =
      Enum.reduce(1..w.mag, s, fn _, s ->
        %{Combat.shoot(s, "a") | tick: s.tick + w.interval}
      end)

    assert s.players["a"].ammo == 0
    reloading = s.players["a"].reload_until
    assert reloading > s.tick
    assert Combat.shoot(s, "a") == s

    s =
      Enum.reduce(s.tick..reloading, s, fn tick, s ->
        Combat.handle_weapon(%{s | tick: tick}, "a", %{reload: false})
      end)

    assert s.players["a"].ammo == w.mag
    assert s.players["a"].reload_until == 0
  end

  test "a shotgun reloads shell by shell and can fire between shells" do
    w = Weapons.spec("warden")
    s = lane(5.5, 30.5) |> update_in([:players, "b"], &%{&1 | ammo: 2})
    s = Combat.handle_weapon(s, "b", %{reload: true})
    assert s.players["b"].reload_until == w.reload
    s = Combat.handle_weapon(%{s | tick: w.reload}, "b", %{reload: false})
    assert s.players["b"].ammo == 3
    assert s.players["b"].reload_until == 2 * w.reload
    fired = Combat.shoot(%{s | tick: w.reload + 1}, "b")
    assert fired.players["b"].ammo == 2
    assert fired.players["b"].reload_until == 0
  end

  test "sustained fire climbs with recoil and blooms, then both recover" do
    s = lane(5.5, 30.5) |> aim("a", 0.6)

    sprayed =
      Enum.reduce(1..6, s, fn _, s ->
        s = %{s | tick: s.tick + 4}
        s |> Combat.handle_weapon("a", %{reload: false}) |> Combat.shoot("a")
      end)

    a = sprayed.players["a"]
    assert a.recoil > 0.04
    assert a.spread > 0.02
    assert a.burst == 6
    assert Weapons.cone(a) > Weapons.cone(s.players["a"])

    rested =
      Enum.reduce(1..20, sprayed, fn _, s ->
        Combat.handle_weapon(%{s | tick: s.tick + 1}, "a", %{reload: false})
      end)

    assert rested.players["a"].recoil < 0.005
    assert rested.players["a"].spread < 0.001
  end

  test "moving and jumping widen the cone, crouching tightens it" do
    p = duel().players["a"]
    still = Weapons.cone(p)
    assert Weapons.cone(%{p | vx: 3.4}) > still * 4
    assert Weapons.cone(%{p | grounded: false}) > still * 10
    assert Weapons.cone(%{p | crouching: true}) < still
  end

  test "hits knock the target back and tell it where they came from" do
    s = lane(5.5, 7.5) |> Combat.shoot("a")
    b = s.players["b"]
    assert b.vx > 0
    assert_in_delta b.hurt_dir, :math.pi(), 0.01
    assert b.hurt_at == s.tick
  end

  test "lag compensation hits targets where the shooter saw them" do
    s = lane(5.5, 9.5) |> Game.step() |> Game.step()
    seen = s.tick
    # The target has since stepped out of the line of fire.
    s = s |> place("b", 9.5, 16.5) |> Game.step()
    missed = Combat.shoot(s, "a")
    assert missed.players["b"].hp == 100

    rewound =
      s
      |> Game.set_input("a", %{"view_tick" => seen, "angle" => 0})
      |> Combat.shoot("a")

    assert rewound.players["b"].hp < 100

    too_old = put_in(s, [:players, "a", :input, :view_tick], seen - 50)
    assert Combat.shoot(too_old, "a").players["b"].hp == 100
  end

  test "kill attribution, respawn, and spawn protection" do
    s = duel() |> Combat.hurt_player("b", 120, "a")
    assert s.players["a"].kills == 1
    assert s.players["b"].deaths == 1
    s = steps(s, 100)
    assert s.players["b"].hp == 100
    assert s.players["b"].ammo == Weapons.spec("warden").mag
    assert Combat.hurt_player(s, "b", 25).players["b"].hp == 100
    assert Combat.hurt_player(%{s | tick: 160}, "b", 25).players["b"].hp == 75
  end

  test "tower shields core and core destruction finishes match" do
    s = duel() |> Combat.hurt_entity("core-1", 999, "a")
    assert s.entities["core-1"].hp == 800
    s = s |> Combat.hurt_entity("tower-1", 999, "a") |> Combat.hurt_entity("core-1", 999, "a")
    assert s.over and s.winner == 0
    assert Game.step(s) == s
  end

  test "dash cannot cross walls" do
    s =
      duel()
      |> place("a", 1.3, 12.5)
      |> Game.set_input("a", %{"angle" => :math.pi(), "ability" => true})

    s = steps(s, 8)
    assert s.players["a"].x >= 0.7
  end

  test "healing pulse leaves enemies intact and shares cooldown with attack pulse" do
    s = duel() |> place("a", 10.5, 12.5) |> place("b", 12.5, 12.5)
    s = update_in(s, [:players, "a"], &%{&1 | class: "warden", hp: 40}) |> Combat.ability("a")
    assert s.players["a"].hp == 70
    assert s.players["b"].hp == 100
    assert Combat.ability(s, "a") == s
    s = %{s | tick: 160} |> put_in([:players, "a", :input, :sprint], true) |> Combat.ability("a")
    assert s.players["a"].hp == 70
    assert s.players["b"].hp == 65
    # The attack pulse throws enemies away and off their feet.
    assert s.players["b"].vx > 0 and s.players["b"].vz > 0
  end

  test "dash bursts along the movement keys, grants a speed bonus and slides out" do
    s =
      duel()
      |> place("a", 10.5, 14.5)
      |> Game.set_input("a", %{"strafe" => 1, "angle" => 0})
      |> Combat.ability("a")

    assert s.players["a"].boost_until == 20
    dashed = steps(s, 4)
    assert dashed.players["a"].y - 14.5 > 2.2
    assert abs(dashed.players["a"].x - 10.5) < 0.05

    blocked =
      duel()
      |> place("a", 0.7, 12.5)
      |> put_in([:players, "a", :angle], :math.pi())
      |> Combat.ability("a")

    assert blocked.players["a"].boost_until == 0
  end
end
