defmodule BlackShift.Game.PhysicsTest do
  use ExUnit.Case, async: true
  import BlackShift.Fixtures
  alias BlackShift.Game
  alias BlackShift.Game.Physics
  alias BlackShift.World.Scene

  test "jump has gravity, lands, and permits standing on low cover" do
    s = duel() |> place("a", 7.6, 10.5) |> Game.set_input("a", %{"jump" => true}) |> Game.step()
    assert s.players["a"].z > 0
    refute s.players["a"].grounded
    s = steps(s, 7)
    assert s.players["a"].z > 1.25
    p = Physics.move(s.players["a"], 0.9, 0)
    assert p.x > 8.4
    s = put_in(s, [:players, "a"], p) |> steps(30)
    assert_in_delta s.players["a"].z, 1.25, 0.001
    assert s.players["a"].grounded
  end

  test "jump grace is consumed and repeated packets cannot add impulse" do
    s = versus_bot() |> Game.set_input("human", %{"jump" => true}) |> Game.step()
    velocity = s.players["human"].vz
    s = s |> Game.set_input("human", %{"jump" => true}) |> Game.step()
    assert s.players["human"].vz < velocity
    assert s.players["human"].coyote_until == -1
  end

  test "ceiling limits the whole player capsule" do
    s =
      versus_bot()
      |> put_in([:players, "human", :z], 3.1)
      |> put_in([:players, "human", :vz], 8.0)
      |> Game.step()

    assert s.players["human"].z + 1.84 <= 5.0001
  end

  test "ramp climbs continuously onto the catwalk without jumping" do
    s = Game.new("ramp", [%{id: "a"}, %{id: "b"}])
    p = %{s.players["a"] | x: 18.6, y: 10.8, z: 0.0, grounded: true}
    p = Enum.reduce(1..38, p, fn _, p -> Physics.move(p, 0.17, 0) end)
    assert p.x > 24.5
    assert_in_delta p.z, 2.30, 0.03
  end

  test "movement accelerates, keeps momentum briefly and brakes on the ground" do
    s = duel() |> place("a", 10, 14.5) |> Game.set_input("a", %{"forward" => 1})
    first = Game.step(s).players["a"]
    assert first.x - 10 > 0.05 and first.x - 10 < 0.17
    running = steps(s, 6)
    assert_in_delta running.players["a"].vx, 3.4, 0.01

    released = Game.set_input(running, "a", %{"forward" => 0})
    coasting = Game.step(released)
    assert coasting.players["a"].x > running.players["a"].x
    stopped = steps(released, 8)
    assert stopped.players["a"].vx == 0
    assert stopped.players["a"].x - running.players["a"].x < 0.4
  end

  test "jumps carry momentum and steering in the air is limited" do
    s = duel() |> place("a", 10, 14.5) |> Game.set_input("a", %{"forward" => 1}) |> steps(6)
    s = Game.set_input(s, "a", %{"forward" => 0, "strafe" => 1, "jump" => true})
    airborne = steps(s, 4)
    a = airborne.players["a"]
    refute a.grounded
    # Still flying forward: neither friction nor the sideways key stopped the run.
    assert a.vx > 3.3
    assert a.vy > 0 and a.vy < 1.5
  end

  test "walls absorb the velocity running into them" do
    s =
      duel()
      |> place("a", 1.3, 12.5)
      |> Game.set_input("a", %{"forward" => 1, "angle" => :math.pi() * 0.75})
      |> steps(10)

    a = s.players["a"]
    assert a.vx == 0
    assert a.vy > 1.5
  end

  test "crouching lowers the body, slows walking and needs headroom to stand" do
    s = duel() |> place("a", 10, 14.5) |> Game.set_input("a", %{"forward" => 1, "crouch" => true})
    s = steps(s, 8)
    a = s.players["a"]
    assert a.crouching
    assert_in_delta a.vx, 1.7, 0.01
    assert Physics.hitbox_height(a) < 1.3
    assert Physics.eye_height(a) < 1.0

    stood = s |> Game.set_input("a", %{"forward" => 0}) |> Game.step()
    refute stood.players["a"].crouching

    # Under the gallery floor (underside at 2.7 m) a body standing on a 1.3 m box has no headroom.
    low = put_in(s, [:players, "a"], %{a | x: 32.5, y: 21.5, z: 1.3})
    assert Scene.clear?(32.5, 21.5, 1.3, Physics.crouch_body())
    refute Scene.clear?(32.5, 21.5, 1.3)
    kept = low |> Game.set_input("a", %{"crouch" => false}) |> Game.step()
    assert kept.players["a"].crouching
  end

  test "long falls hurt, short drops do not" do
    drop = fn height ->
      s = duel() |> place("a", 13.5, 30.5) |> put_in([:players, "a", :z], height)
      s = put_in(s, [:players, "a", :grounded], false)

      Enum.reduce_while(1..80, s, fn _, s ->
        s = Game.step(s)
        if s.players["a"].grounded, do: {:halt, s}, else: {:cont, s}
      end)
    end

    assert drop.(3.0).players["a"].hp == 100
    hurt = drop.(7.0).players["a"].hp
    assert hurt < 100 and hurt > 50
    assert Physics.impact_damage(11.0) == 0
  end
end
