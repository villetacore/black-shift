defmodule BlackShift.Game.Physics do
  @moduledoc """
  Movement, gravity and line of sight against the 3D scene.

  Bodies are maps with `x`, `y` (horizontal, metres) and, for players, `z`
  (feet height), `vz` and `grounded`. Players also carry a horizontal velocity
  `vx`/`vy` in metres per second: input accelerates it, ground friction brakes
  it and walls absorb the component that runs into them, so movement has
  weight and momentum instead of snapping to full speed. Structures carry a
  `kind` that defines their hit volume.
  """
  alias BlackShift.Game.{Liquid, Rules}
  alias BlackShift.World.Scene

  @player_height 1.84
  @eye_height 1.48
  @crouch_height 1.26
  @crouch_eye_height 0.98
  # Collision bodies stop just below the hit box so heads do not scrape ceilings.
  @crouch_body 1.22
  # Horizontal movement is split into steps of at most this length so bodies cannot tunnel.
  @move_substep 0.08
  @step_height 0.30
  @step_probe 0.2
  @foot_probe 0.19
  @jump_speed 8.1

  # Ticks after leaving a ledge during which a jump is still accepted.
  @coyote_ticks 3

  # Ground movement in the style of classic shooters, in SI units. Friction
  # removes `@friction` of the speed per second (at least `@stop_speed`), and
  # acceleration closes the gap to the wished speed at `@ground_accel` times
  # that speed per second. Together they reach full speed in ~0.15 s and stop
  # in ~0.25 s.
  @ground_accel 12.0
  @air_accel 1.6
  @water_accel 6.0
  @friction 7.0
  @water_friction 3.5
  @stop_speed 1.6

  # Landing faster than this hurts (a gallery drop is ~11 m/s, a jump off it ~13.8 m/s).
  @safe_impact 13.0
  @impact_damage 7.0
  # Landings harder than this cost horizontal momentum.
  @hard_landing 9.0

  def player_height, do: @player_height

  @doc "Eye height above the feet; lower while crouching."
  def eye_height(p \\ %{})
  def eye_height(%{crouching: true}), do: @crouch_eye_height
  def eye_height(_), do: @eye_height

  @doc "Top of the collision body above the feet."
  def body_height(%{crouching: true}), do: @crouch_body
  def body_height(_), do: Scene.body_height()

  def standing_body, do: Scene.body_height()
  def crouch_body, do: @crouch_body

  def distance(x, y, ex, ey), do: :math.sqrt((ex - x) ** 2 + (ey - y) ** 2)

  @doc "Horizontal distance between two bodies."
  def distance(a, b), do: distance(a.x, a.y, b.x, b.y)

  @doc "Height that shots and line-of-sight checks aim at."
  def aim_height(%{kind: "drone"} = e), do: Map.get(e, :z, 0.0) + 0.4
  def aim_height(%{kind: "tower"} = e), do: Map.get(e, :z, 0.0) + 1.4
  def aim_height(%{kind: "core"} = e), do: Map.get(e, :z, 0.0) + 1.1
  def aim_height(%{crouching: true} = p), do: Map.get(p, :z, 0.0) + 0.88
  def aim_height(player), do: Map.get(player, :z, 0.0) + 1.35

  @doc "Height of the hit box that bullets are tested against."
  def hitbox_height(%{kind: "drone"}), do: 0.72
  def hitbox_height(%{kind: "tower"}), do: 1.78
  def hitbox_height(%{kind: "core"}), do: 2.0
  def hitbox_height(%{crouching: true}), do: @crouch_height
  def hitbox_height(_player), do: @player_height

  def line_of_sight?(a, b) do
    za = aim_height(a)
    zb = aim_height(b)
    dx = b.x - a.x
    dy = b.y - a.y
    dz = zb - za
    length = :math.sqrt(dx * dx + dy * dy + dz * dz)

    length < 0.001 or
      Scene.raycast([a.x, a.y, za], [dx / length, dy / length, dz / length], length) >=
        length - 0.01
  end

  @doc "Moves a body horizontally, sliding along walls and stepping onto low ledges."
  def move(body, dx, dy) do
    n = trunc(distance(0, 0, dx, dy) / @move_substep) + 1
    height = body_height(body)

    Enum.reduce(1..n, body, fn _, body ->
      body = horizontal(body, body.x + dx / n, body.y, height)
      horizontal(body, body.x, body.y + dy / n, height)
    end)
  end

  defp horizontal(body, x, y, height) do
    cond do
      Scene.clear?(x, y, body.z, height) ->
        %{body | x: x, y: y}

      Map.get(body, :grounded, false) ->
        z =
          for ox <- [-@step_probe, @step_probe], oy <- [-@step_probe, @step_probe] do
            Scene.support(x + ox, y + oy, body.z + @step_height)
          end
          |> Enum.max()

        if z > body.z and z <= body.z + @step_height and Scene.clear?(x, y, z, height),
          do: %{body | x: x, y: y, z: z},
          else: body

      true ->
        body
    end
  end

  @doc """
  Integrates one tick of horizontal velocity: moves by `vx`/`vy` plus an
  external displacement (water current), then drops the part of the velocity
  that a wall absorbed so players slide along walls instead of sticking.
  """
  def slide(p, extra_dx \\ 0.0, extra_dy \\ 0.0) do
    dt = 1 / Rules.tick_rate()
    dx = p.vx * dt + extra_dx
    dy = p.vy * dt + extra_dy
    moved = move(p, dx, dy)
    vx = if blocked?(moved.x - p.x, dx), do: 0.0, else: p.vx
    vy = if blocked?(moved.y - p.y, dy), do: 0.0, else: p.vy
    %{moved | vx: vx, vy: vy}
  end

  defp blocked?(actual, wanted), do: abs(wanted) > 1.0e-6 and abs(actual) < abs(wanted) * 0.5

  @doc """
  Applies one tick of friction and acceleration towards `wish` (a horizontal
  unit vector scaled by 0..1) at up to `max_speed` m/s. `medium` is `:ground`,
  `:air` or `:water`; the air keeps momentum and allows only slight steering.
  """
  def accelerate(p, {wx, wy}, max_speed, medium) do
    dt = 1 / Rules.tick_rate()
    {vx, vy} = friction(p.vx, p.vy, medium, dt)
    wish_length = distance(0, 0, wx, wy)

    {vx, vy} =
      if wish_length < 1.0e-6 do
        {vx, vy}
      else
        {dir_x, dir_y} = {wx / wish_length, wy / wish_length}
        wish_speed = max_speed * min(1.0, wish_length)
        current = vx * dir_x + vy * dir_y
        gap = wish_speed - current
        rate = %{ground: @ground_accel, air: @air_accel, water: @water_accel}[medium]
        gain = if gap > 0, do: min(rate * wish_speed * dt, gap), else: 0.0
        {vx + dir_x * gain, vy + dir_y * gain}
      end

    %{p | vx: vx, vy: vy}
  end

  defp friction(vx, vy, :air, _dt), do: {vx, vy}

  defp friction(vx, vy, medium, dt) do
    speed = distance(0, 0, vx, vy)
    rate = if medium == :water, do: @water_friction, else: @friction

    if speed < 1.0e-4 do
      {0.0, 0.0}
    else
      kept = max(0.0, speed - max(speed, @stop_speed) * rate * dt) / speed
      {vx * kept, vy * kept}
    end
  end

  @doc "Adds an impulse (m/s) to a body's velocity; vertical pushes lift it off the ground."
  def push(p, dx, dy, dz \\ 0.0) do
    p = %{p | vx: Map.get(p, :vx, 0.0) + dx, vy: Map.get(p, :vy, 0.0) + dy}
    if dz > 0, do: %{p | vz: max(p.vz, 0.0) + dz, grounded: false}, else: p
  end

  @doc "Current horizontal speed in m/s."
  def speed(p), do: distance(0, 0, Map.get(p, :vx, 0.0), Map.get(p, :vy, 0.0))

  @doc """
  Applies one tick of gravity, landing, ceilings and (optionally) a jump.
  On the landing tick `impact` holds the downward speed (m/s); otherwise 0.
  """
  def fall(p, jump, tick) do
    support =
      for dx <- [-@foot_probe, @foot_probe], dy <- [-@foot_probe, @foot_probe] do
        Scene.support(p.x + dx, p.y + dy, p.z)
      end
      |> Enum.max()

    head = body_height(p) + 0.02

    ceiling =
      for dx <- [-@foot_probe, @foot_probe], dy <- [-@foot_probe, @foot_probe] do
        Scene.ceiling(p.x + dx, p.y + dy, p.z + head) - head
      end
      |> Enum.min()

    grounded = abs(p.z - support) < 0.002 and p.vz <= 0
    p = if grounded, do: %{p | coyote_until: tick + @coyote_ticks}, else: p
    jumping = jump and tick <= p.coyote_until
    velocity = if jumping, do: @jump_speed, else: p.vz
    p = if jumping, do: %{p | coyote_until: -1}, else: p
    {velocity, gravity} = Liquid.velocity(p, jump, velocity)
    z = p.z + velocity / Rules.tick_rate()

    cond do
      z <= support ->
        impact = if Map.get(p, :grounded, true), do: 0.0, else: max(0.0, -velocity)
        Map.merge(p, %{z: support, vz: 0.0, grounded: true, impact: impact})

      z > ceiling ->
        Map.merge(p, %{z: ceiling, vz: min(0.0, velocity), grounded: false, impact: 0.0})

      true ->
        Map.merge(p, %{z: z, vz: velocity - gravity, grounded: false, impact: 0.0})
    end
  end

  @doc "Damage for a landing at `impact` m/s (0 for ordinary jumps and gallery drops)."
  def impact_damage(impact) when impact > @safe_impact,
    do: round((impact - @safe_impact) * @impact_damage)

  def impact_damage(_), do: 0

  @doc "True when a landing is hard enough to stagger (costs horizontal speed)."
  def hard_landing?(impact), do: impact > @hard_landing
end
