defmodule BlackShift.Game.Weapons do
  @moduledoc """
  Weapon specifications and the deterministic ballistics shared by players and bots.

  Every value that shapes a gunfight lives here:

    * **Rate and magazine** — `interval` ticks between shots, `mag` rounds, a
      `reload` time in ticks. A `per_shell` weapon loads one round per reload
      period and can fire between rounds.
    * **Damage** — per pellet, scaled by hit zone (`head`, `legs`) and by
      distance: full damage up to `falloff_start`, then linearly down to
      `falloff_min` of it at `range`.
    * **Accuracy** — the cone a shot can leave in, in radians: `base` while
      standing still, plus `moving` at full walking speed, plus `airborne`,
      plus `bloom` that each shot adds (up to `max_bloom`) and that recovers by
      `bloom_recovery` per tick. Crouching multiplies the cone by `crouch`.
    * **Recoil** — each shot lifts the aim by `kick` and nudges it sideways by
      up to `side_kick`, following a fixed per-shot pattern; the offset decays
      by `recoil_recovery` per tick. Recoil is authoritative: the client
      mirrors it in the camera and players pull down to compensate.
    * **Impact** — `push` m/s of knockback per pellet.

  Randomness is derived from a hash of the shooter, the tick and the pellet,
  so a match replays identically from the same inputs.
  """

  @weapons %{
    "ranger" => %{
      name: "SM-9",
      interval: 4,
      mag: 25,
      reload: 36,
      per_shell: false,
      pellets: 1,
      damage: 19,
      head: 1.8,
      legs: 0.75,
      range: 30.0,
      falloff_start: 9.0,
      falloff_min: 0.55,
      base: 0.006,
      moving: 0.024,
      airborne: 0.07,
      bloom: 0.008,
      max_bloom: 0.04,
      bloom_recovery: 0.78,
      crouch: 0.6,
      pellet_cone: 0.0,
      kick: 0.017,
      side_kick: 0.006,
      recoil_recovery: 0.85,
      push: 0.25
    },
    "warden" => %{
      name: "SG-12",
      interval: 16,
      mag: 6,
      reload: 10,
      per_shell: true,
      pellets: 8,
      damage: 9,
      head: 1.5,
      legs: 0.75,
      range: 16.0,
      falloff_start: 4.5,
      falloff_min: 0.3,
      base: 0.004,
      moving: 0.012,
      airborne: 0.04,
      bloom: 0.0,
      max_bloom: 0.0,
      bloom_recovery: 0.78,
      crouch: 0.8,
      pellet_cone: 0.06,
      kick: 0.075,
      side_kick: 0.012,
      recoil_recovery: 0.82,
      push: 0.55
    }
  }

  @walk_speed 3.4

  def spec(class), do: Map.get(@weapons, class, @weapons["ranger"])

  @doc "Accuracy cone for the shooter's current stance and motion, in radians."
  def cone(p) do
    w = spec(p.class)
    motion = min(1.5, speed(p) / @walk_speed)
    air = if Map.get(p, :grounded, true), do: 0.0, else: w.airborne
    cone = w.base + w.moving * motion + air + Map.get(p, :spread, 0.0)
    if Map.get(p, :crouching, false), do: cone * w.crouch, else: cone
  end

  defp speed(p), do: :math.sqrt(Map.get(p, :vx, 0.0) ** 2 + Map.get(p, :vy, 0.0) ** 2)

  @doc "Damage multiplier for a hit at `distance` metres."
  def falloff(w, distance) do
    cond do
      distance <= w.falloff_start ->
        1.0

      distance >= w.range ->
        w.falloff_min

      true ->
        1.0 - (1.0 - w.falloff_min) * (distance - w.falloff_start) / (w.range - w.falloff_start)
    end
  end

  @doc """
  Direction offsets `{yaw, pitch}` for each pellet of one shot. The first pellet
  of a spread weapon goes through the cone's centre-weighted distribution; the
  others fill the fixed pellet cone with jitter.
  """
  def offsets(p, tick) do
    w = spec(p.class)
    cone = cone(p)

    for i <- 0..(w.pellets - 1) do
      {u1, u2, u3} =
        {random(p.id, tick, i, 1), random(p.id, tick, i, 2), random(p.id, tick, i, 3)}

      # The mean of two uniforms concentrates shots towards the centre, like real dispersion.
      radius = cone * (u1 + u2) / 2
      theta = u3 * 2 * :math.pi()
      {pyaw, ppitch} = pellet(w, i, random(p.id, tick, i, 4))

      {pyaw + radius * :math.cos(theta), ppitch + radius * :math.sin(theta)}
    end
  end

  # Pellet 0 is centred; the rest form a ring with radial jitter so the pattern is fair but not fixed.
  defp pellet(%{pellets: 1}, _, _), do: {0.0, 0.0}
  defp pellet(_, 0, _), do: {0.0, 0.0}

  defp pellet(w, i, jitter) do
    angle = (i - 1) / (w.pellets - 1) * 2 * :math.pi() + jitter * 0.6
    radius = w.pellet_cone * (0.55 + 0.45 * jitter)
    {radius * :math.cos(angle), radius * :math.sin(angle)}
  end

  @doc "Recoil added by the `n`-th shot of a spray: always up, sideways along a fixed sway."
  def kick(class, n) do
    w = spec(class)
    {w.side_kick * :math.sin(n * 0.9) * min(1.0, n / 3), w.kick}
  end

  @doc "Uniform value in [0, 1) derived from the shot's identity."
  def random(id, tick, pellet, channel),
    do: :erlang.phash2({id, tick, pellet, channel}, 1_000_000) / 1_000_000
end
