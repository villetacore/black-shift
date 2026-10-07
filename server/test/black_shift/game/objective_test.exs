defmodule BlackShift.Game.ObjectiveTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.Game
  alias BlackShift.Game.Objective

  test "relay cannot be captured through the floor above it" do
    s = duel() |> place("a", 32.5, 21.5) |> put_in([:players, "a", :z], 3.0)
    s = Objective.step(%{s | tick: 100})
    assert s.capture_ticks == 0
  end

  test "rotation warning fires once 15 seconds before the relay moves" do
    s = duel()

    refute Enum.any?(
             Objective.step(%{s | tick: 899}).feed,
             &String.starts_with?(&1, "RELAY SHIFT")
           )

    assert Enum.any?(
             Objective.step(%{s | tick: 900}).feed,
             &String.starts_with?(&1, "RELAY SHIFT")
           )

    refute Enum.any?(
             Objective.step(%{s | tick: 901}).feed,
             &String.starts_with?(&1, "RELAY SHIFT")
           )
  end

  test "contested relay gives no score; uninterrupted capture secures it before it scores" do
    s = duel() |> place("a", 32.5, 21.5) |> place("b", 33.5, 21.5)
    s = Game.step(%{s | tick: 19})
    assert s.relay == -1 and s.score == [0, 0]
    s = %{s | tick: 39} |> place("b", 20, 12.5) |> steps(41)
    assert s.relay == 0 and s.capture_ticks == 40 and s.capture_team == 0
    assert s.score == [1, 0]
    assert s.players["a"].xp == 8
  end

  test "continuous hold awards a bonus and contest resets it" do
    s = Game.new("hold", [%{id: "a"}, %{id: "b"}])
    point = Objective.current(s)
    s = place(s, "a", point.x, point.y)

    s = %{
      s
      | tick: 100,
        relay: 0,
        hold_ticks: 299,
        capture_team: 0,
        capture_ticks: 40,
        entities: %{}
    }

    next = Game.step(s)
    assert next.score == [5, 0]

    contested = next |> place("b", point.x + 1, point.y) |> Game.step()
    assert contested.hold_ticks == 0
    assert contested.relay == 0
    assert Objective.current(%{tick: 1199}).next_name == Objective.current(%{tick: 1200}).name
  end

  test "objective rotates and snapshot reports its authoritative position" do
    s = Game.step(%{versus_bot() | tick: 1199})
    assert Game.snapshot(s).objective.name == "PUMP HOUSE"
    assert Game.snapshot(s).objective.y == 6.5
  end

  test "health pickup is bounded and has a cooldown" do
    s =
      versus_bot()
      |> place("human", 11.5, 5.5)
      |> put_in([:players, "human", :hp], 20)
      |> Game.step()

    assert s.players["human"].hp == 65
    assert hd(s.supplies).ready_at == 701
    assert Game.step(s).players["human"].hp == 65
  end

  test "partial capture decays, enemy capture takes two seconds and rotation resets ownership" do
    s = duel() |> place("a", 33, 21.5) |> place("b", 20, 12.5)
    s = %{s | tick: 100}
    s = Enum.reduce(1..20, s, fn _, state -> Objective.step(state) end)
    assert s.capture_ticks == 20
    s = place(s, "b", 33, 21.5) |> Objective.step()
    assert s.capture_ticks == 18 and Objective.capture(s).contested
    s = place(s, "a", 20, 12.5)
    s = Enum.reduce(1..39, s, fn _, state -> Objective.step(state) end)
    assert s.relay == -1 and s.capture_team == 1
    s = Objective.step(s)
    assert s.relay == 1
    rotated = Objective.step(%{s | tick: 1200})
    assert rotated.relay == -1 and rotated.capture_ticks == 0
  end
end
