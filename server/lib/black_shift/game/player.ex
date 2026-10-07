defmodule BlackShift.Game.Player do
  @moduledoc "Player lifecycle, progression, input handling and the per-tick player update."
  alias BlackShift.Game.{Bot, Combat, Liquid, Physics, Rules, State, Weapons}
  alias BlackShift.World.Scene

  @base_hp 100
  @hp_per_level 10
  @max_level 5
  @xp_per_level 100
  @spawn_protection_ticks 60
  @respawn_ticks 100
  # Spawn slots are spread along the y axis around the team spawn point.
  @spawn_spacing 1.2
  # Top speeds in metres per second (0.17 and 0.255 m per tick at 20 Hz).
  @walk_speed 3.4
  @sprint_speed 5.1
  @crouch_speed 1.7
  # Clients that stop sending input are treated as idle after this many ticks.
  @input_timeout_ticks 20
  @max_pitch 1.15
  # Lag compensation never rewinds further than this (400 ms).
  @max_rewind_ticks 8
  # Hard landings keep this share of horizontal speed.
  @landing_keep 0.6

  def walk_speed, do: @walk_speed
  def max_rewind_ticks, do: @max_rewind_ticks

  def new(description, index) do
    %{class: "ranger", name: "Operator", bot: false}
    |> Map.merge(description)
    |> Map.merge(%{
      team: rem(index, 2),
      spawn_slot: div(index, 2),
      kills: 0,
      deaths: 0,
      level: 1,
      xp: 0,
      cooldown: 0.0,
      fire_at: 0,
      ability_at: 0,
      respawn_at: 0,
      hits: 0,
      hit_head: false,
      hit_kill: false,
      hurt_at: -100,
      hurt_dir: nil,
      hurt_by: nil
    })
    |> spawn(0)
  end

  def spawn(p, tick) do
    angle = if p.team == 0, do: 0.0, else: :math.pi()
    %{x: x, y: y, z: z} = Scene.anchor("spawns", p.team)

    Map.merge(p, %{
      x: x,
      y: y + @spawn_spacing - rem(p.spawn_slot, 3) * @spawn_spacing,
      z: z,
      vx: 0.0,
      vy: 0.0,
      vz: 0.0,
      impact: 0.0,
      grounded: true,
      sprinting: false,
      crouching: false,
      immersion: 0.0,
      coyote_until: tick,
      dash_until: tick,
      ammo: Weapons.spec(p.class).mag,
      reload_until: 0,
      spread: 0.0,
      recoil: 0.0,
      recoil_yaw: 0.0,
      burst: 0,
      last_shot: -100,
      ai_target: nil,
      ai_seen: tick,
      ai_memory: nil,
      ai_path: [],
      ai_route_at: 0,
      ai_goal: nil,
      ai_strafe: 1,
      ai_strafe_at: tick,
      ai_stuck: {x, y, tick},
      ai_error: 0.0,
      angle: angle,
      pitch: 0.0,
      hp: max_hp(p),
      respawn: 0.0,
      boost_until: tick,
      boost: 0.0,
      protected_until: tick + @spawn_protection_ticks,
      input: neutral_input(angle),
      input_at: tick
    })
  end

  def max_hp(p), do: @base_hp + @hp_per_level * (p.level - 1)

  def heal(p, amount), do: %{p | hp: min(p.hp + amount, max_hp(p))}

  def die(p, tick),
    do: %{
      p
      | hp: 0,
        deaths: p.deaths + 1,
        respawn_at: tick + @respawn_ticks,
        boost_until: tick,
        boost: 0.0,
        crouching: false
    }

  @doc "Grants experience; every #{@xp_per_level} XP raises the level up to #{@max_level}."
  def reward(p, xp) do
    xp = p.xp + xp

    level =
      Enum.reduce(2..@max_level, p.level, fn level, current ->
        if xp >= (level - 1) * @xp_per_level, do: max(level, current), else: current
      end)

    %{p | xp: xp, level: level}
  end

  def neutral_input(angle \\ 0.0),
    do: %{
      forward: 0.0,
      strafe: 0.0,
      angle: angle,
      pitch: 0.0,
      jump: false,
      swim: false,
      fire: false,
      sprint: false,
      crouch: false,
      reload: false,
      ability: false,
      view_tick: nil
    }

  @doc """
  Validates a raw client `input` message and stores it on the player.

  Jump, reload and ability presses are latched until the next tick consumes
  them, so a short key press between two input packets is not lost.
  `view_tick` is the snapshot tick the client was displaying; shots are
  checked against where targets were at that tick (lag compensation).
  """
  def accept_input(p, raw, tick) do
    forward = Map.get(raw, "forward", 0)
    strafe = Map.get(raw, "strafe", 0)
    angle = Map.get(raw, "angle", 0)
    pitch = Map.get(raw, "pitch", 0)
    view_tick = Map.get(raw, "view_tick")

    if Enum.all?([forward, strafe, angle, pitch], &(is_number(&1) and abs(&1) < 1.0e9)) do
      {:ok,
       %{
         p
         | input_at: tick,
           input: %{
             forward: clamp(forward, 1),
             strafe: clamp(strafe, 1),
             angle: :math.fmod(angle, 2 * :math.pi()),
             pitch: clamp(pitch, @max_pitch),
             jump: p.input.jump or Map.get(raw, "jump") == true,
             swim: Map.get(raw, "swim") == true,
             fire: Map.get(raw, "fire") == true,
             sprint: Map.get(raw, "sprint") == true,
             crouch: Map.get(raw, "crouch") == true,
             reload: p.input.reload or Map.get(raw, "reload") == true,
             ability: p.input.ability or Map.get(raw, "ability") == true,
             view_tick: if(is_integer(view_tick), do: view_tick, else: nil)
           }
       }}
    else
      :error
    end
  end

  defp clamp(value, limit), do: max(-limit, min(limit, value))

  @doc "Tick the player's shots are checked against: the client's view, within the rewind window."
  def view_tick(%{bot: true}, tick), do: tick

  def view_tick(p, tick) do
    case p.input.view_tick do
      nil -> tick
      view -> max(tick - @max_rewind_ticks, min(tick, view))
    end
  end

  @doc "Advances one player by one tick: respawn timer, bot decisions, movement and actions."
  def step(s, id) do
    p = s.players[id]

    cond do
      s.over ->
        s

      p.hp <= 0 ->
        State.update_player(s, id, fn p ->
          if s.tick >= p.respawn_at,
            do: spawn(p, s.tick),
            else: %{p | respawn: Rules.seconds(p.respawn_at - s.tick)}
        end)

      true ->
        p = if p.bot, do: Bot.think(s, p), else: p

        input =
          if s.tick - p.input_at > @input_timeout_ticks,
            do: %{neutral_input(p.angle) | pitch: p.input.pitch},
            else: p.input

        p = stance(p, input)
        p = Physics.fall(p, input.jump, s.tick)
        p = walk(p, input, s.tick)
        s = put_in(s, [:players, id], p)
        damage = Physics.impact_damage(p.impact)
        s = if damage > 0, do: Combat.hurt_player(s, id, damage, nil, :fall), else: s
        s = Combat.handle_weapon(s, id, input)
        s = if input.ability, do: Combat.ability(s, id), else: s
        s = if input.fire, do: Combat.shoot(s, id), else: s

        State.update_player(
          s,
          id,
          &%{
            &1
            | cooldown: max(0.0, Rules.seconds(&1.ability_at - s.tick)),
              boost: max(0.0, Rules.seconds(&1.boost_until - s.tick))
          }
        )
    end
  end

  # Crouching is held; standing back up needs headroom, so players stay low under pipes.
  # A jump press stands the player up first.
  defp stance(p, input) do
    wants = input.crouch and not input.jump

    cond do
      wants -> %{p | crouching: true}
      p.crouching -> %{p | crouching: not Scene.clear?(p.x, p.y, p.z, Physics.standing_body())}
      true -> p
    end
  end

  defp walk(p, input, tick) do
    wet = Liquid.immersion(p)

    medium =
      cond do
        wet > 0.35 -> :water
        p.grounded -> :ground
        true -> :air
      end

    # Diagonal input is normalised so it is not faster than straight movement.
    n = max(1.0, Physics.distance(0, 0, input.forward, input.strafe))

    # Sprinting is a forward run: no backpedalling, strafing-only, crouching or shooting.
    sprint =
      input.sprint and p.grounded and input.forward > 0 and not p.crouching and wet < 0.15 and
        not input.fire

    speed =
      cond do
        sprint -> @sprint_speed
        p.crouching -> @crouch_speed
        true -> @walk_speed
      end

    speed = if tick < p.boost_until, do: speed * 1.25, else: speed
    speed = speed * (1.0 - 0.55 * wet)
    {sin, cos} = {:math.sin(input.angle), :math.cos(input.angle)}

    wish =
      {(cos * input.forward - sin * input.strafe) / n,
       (sin * input.forward + cos * input.strafe) / n}

    p =
      if Physics.hard_landing?(p.impact),
        do: %{p | vx: p.vx * @landing_keep, vy: p.vy * @landing_keep},
        else: p

    # A dash carries its own momentum: no friction or steering until it ends.
    p = if tick < p.dash_until, do: p, else: Physics.accelerate(p, wish, speed, medium)
    {cx, cy} = Liquid.drift(p)

    Physics.slide(
      %{
        p
        | angle: input.angle,
          pitch: input.pitch,
          sprinting: sprint,
          immersion: wet,
          input: %{input | ability: false, jump: false, reload: false}
      },
      cx,
      cy
    )
  end
end
