defmodule BlackShift.Game.PlayerTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.Game

  test "server clamps vertical aim and ignores client coordinates" do
    s = duel() |> Game.set_input("a", %{"pitch" => 99, "z" => 100, "vz" => 900}) |> Game.step()
    assert s.players["a"].pitch == 1.15
    assert s.players["a"].z == 0
    assert Map.has_key?(hd(Game.snapshot(s).players), :z)
  end

  test "invalid input is rejected, speed is normalized, and ability is latched" do
    s = duel() |> place("a", 10, 14.5)
    assert Game.set_input(s, "a", %{"forward" => "bad"}) == s

    # Top speed is reached within a few ticks and diagonal input is not faster.
    moving = s |> Game.set_input("a", %{"forward" => 100, "strafe" => 100}) |> steps(6)
    p = moving.players["a"]
    next = Game.step(moving).players["a"]
    assert_in_delta :math.sqrt((next.x - p.x) ** 2 + (next.y - p.y) ** 2), 0.17, 0.0001

    sprinting = s |> Game.set_input("a", %{"forward" => 1, "sprint" => true}) |> steps(6)
    assert sprinting.players["a"].sprinting
    next = Game.step(sprinting).players["a"]
    assert_in_delta next.x - sprinting.players["a"].x, 0.255, 0.0001

    # Backpedalling, crouching and shooting are not sprinting.
    back = s |> Game.set_input("a", %{"forward" => -1, "sprint" => true}) |> Game.step()
    refute back.players["a"].sprinting

    firing =
      s |> Game.set_input("a", %{"forward" => 1, "sprint" => true, "fire" => true}) |> Game.step()

    refute firing.players["a"].sprinting

    s =
      s
      |> Game.set_input("a", %{"ability" => true})
      |> Game.set_input("a", %{"ability" => false})
      |> Game.step()

    assert s.players["a"].cooldown == 8
  end

  test "reload presses are latched and the view tick is validated" do
    s = duel() |> update_in([:players, "a"], &%{&1 | ammo: 3})

    s =
      s
      |> Game.set_input("a", %{"reload" => true, "view_tick" => "now"})
      |> Game.set_input("a", %{"reload" => false})

    assert s.players["a"].input.view_tick == nil
    assert Game.step(s).players["a"].reload_until > 0
  end
end
