defmodule BlackShift.World.NavigationTest do
  use ExUnit.Case, async: true
  alias BlackShift.Game.Objective
  alias BlackShift.World.{Navigation, Scene}

  test "district supplies, objectives and bases have connected layered routes" do
    map = Scene.scene()
    assert map["bounds"] == [60, 44, 12]
    assert length(map["zones"]) == 6

    goals =
      Enum.map(map["supplies"] ++ map["objectives"], &{&1["x"], &1["y"], Map.get(&1, "z", 0.0)}) ++
        Enum.map(map["cores"] ++ map["towers"], fn [x, y] -> {x, y, 0.0} end)

    for [x, y] <- map["spawns"], goal <- goals do
      assert Navigation.path({x, y, 0.0}, goal) != [], "unreachable #{inspect(goal)}"
    end

    assert_in_delta Scene.ceiling(32.5, 21.5, 1.84), 2.7, 0.001
    assert Scene.ceiling(38.5, 6.5, 1.84) < 5
  end

  test "all objective rooms are connected to both spawns" do
    for tick <- [0, 1200, 2400, 3600], spawn <- [{4.5, 22.7}, {55.5, 22.7}] do
      goal = Objective.current(%{tick: tick})
      {sx, sy} = spawn
      path = Navigation.path({sx, sy, 0.0}, {goal.x, goal.y, goal.z})
      assert path != []
      assert List.last(path) == {goal.x, goal.y, goal.z}
      assert Enum.all?(path, fn {x, y, z} -> Scene.clear?(x, y, z) end)
    end
  end

  test "stacked surfaces remain separate and ramps reach the gallery" do
    assert Scene.surfaces(33.5, 22.5) == [0.0, 3.0]
    path = Navigation.path({32.5, 21.5, 0.0}, {33.5, 22.5, 3.0})
    assert path != []
    assert List.last(path) == {33.5, 22.5, 3.0}
    assert length(path) > 4
  end
end
