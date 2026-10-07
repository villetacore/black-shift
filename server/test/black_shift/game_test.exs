defmodule BlackShift.GameTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.{Game, Game.Objective, World.Navigation, World.Scene}

  test "arena and spawn positions are valid" do
    assert Game.arena()["format"] == 2
    assert length(Game.arena()["objects"]) > 20
    s = duel()
    assert Enum.all?(Map.values(s.players) ++ Map.values(s.entities), &Scene.clear?(&1.x, &1.y))
  end

  test "all six practice spawn slots are clear and connected" do
    s = Game.new("spawns", Enum.map(0..5, &%{id: "p#{&1}"}))

    for p <- Map.values(s.players) do
      assert Scene.clear?(p.x, p.y, p.z)
      point = Objective.current(s)
      assert Navigation.path({p.x, p.y}, {point.x, point.y}) != []
    end
  end

  test "stale input stops and snapshot excludes internal state" do
    s = duel() |> place("a", 10, 12.5) |> Game.set_input("a", %{"forward" => 1}) |> steps(30)
    assert Game.step(s).players["a"].x == s.players["a"].x
    assert s.players["a"].vx == 0
    snapshot = Game.snapshot(s)
    refute Map.has_key?(hd(snapshot.players), :input)
    assert is_binary(IO.iodata_to_binary(:json.encode(snapshot)))
  end

  @tag timeout: 30_000
  test "a full bot match terminates" do
    s = duel() |> Game.remove("a") |> Game.remove("b")

    s =
      Enum.reduce_while(1..6_001, s, fn _, s ->
        next = Game.step(s)
        if next.over, do: {:halt, next}, else: {:cont, next}
      end)

    assert s.over
    assert map_size(s.entities) <= 104
  end
end
