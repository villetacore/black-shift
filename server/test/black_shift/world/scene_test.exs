defmodule BlackShift.World.SceneTest do
  use ExUnit.Case, async: true
  alias BlackShift.World.Scene

  test "scene has arbitrary positions rotations and convex shapes" do
    scene = Scene.scene()
    assert scene["format"] == 2
    assert Enum.any?(scene["objects"], &(&1["shape"] == "ramp"))
    assert Enum.any?(scene["objects"], &(&1["shape"] == "cylinder"))
    assert Enum.any?(scene["objects"], &(&1["yaw"] != 0))

    for o <- scene["objects"] do
      assert Enum.all?(o["vertices"], fn p -> length(p) == 3 and Enum.all?(p, &is_number/1) end)

      for plane <- o["planes"] do
        [a, b, c, _] = plane
        assert_in_delta a * a + b * b + c * c, 1, 0.00001
      end
    end
  end

  test "bridge has independent floor underneath and walkable upper surface" do
    assert Scene.clear?(25.5, 12.5, 0)
    assert Scene.solid?(25.5, 12.5, 2.18)
    assert Scene.clear?(25.5, 12.5, 2.30)
    assert_in_delta Scene.support(25.5, 12.5, 3), 2.30, 0.001
    assert_in_delta Scene.ceiling(25.5, 12.5, 1.84), 2.06, 0.001
  end

  test "ray hits rotated cover and can pass under an elevated brush" do
    assert Scene.raycast([25.5, 10, 1.0], [0, 1, 0], 3.0) == 3.0
    assert Scene.raycast([25.5, 10, 2.18], [0, 1, 0], 3.0) == 0.0
    assert Scene.raycast([17, 9, 0.6], [1, 0, 0], 4.0) < 3.0
  end
end
