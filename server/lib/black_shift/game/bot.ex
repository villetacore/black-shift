defmodule BlackShift.Game.Bot do
  @moduledoc """
  Bot decisions. A bot produces the same input map a human client would send,
  so bots move and shoot through exactly the same simulation rules (momentum,
  spread, recoil, magazines).

  Perception is limited like a player's: a field of view, a short awareness
  radius (footsteps), gunfire heard within earshot and the direction of
  incoming damage. Bots react to where a target was a few ticks ago, remember
  its last known position and pursue it for a while after losing sight.

  Aim starts loose when a target is acquired and settles over about a second;
  it degrades while the bot itself moves. Bots compensate part of their recoil,
  fire in bursts at range and hold a preferred distance for their weapon,
  strafing in the meantime. Wounded bots fall back to health or to cover and
  reload there. Every bot has its own deterministic "skill" seed.
  """
  alias BlackShift.Game.{Objective, Physics, Player, State, Weapons}
  alias BlackShift.World.{Navigation, Scene}

  @sight_range 28.0
  # Half of a 130° field of view.
  @fov 1.13
  # Enemies this close are noticed even behind the bot.
  @awareness 3.0
  @hearing 22.0
  # Seconds of gunfire a shot leaves audible.
  @noise_ticks 8
  @memory_ticks 80
  # Bots react to targets as they were this many ticks ago.
  @perception_lag 3
  @retreat_hp 35
  @reroute_ticks 30
  @waypoint_reached 0.45
  # Radians per tick.
  @max_turn 0.12
  @max_pitch_turn 0.05
  @reaction_ticks 14
  @ability_delay_ticks 24
  @ability_range 3
  @sprint_distance 6.5
  # Aim error (radians) right after acquiring a target, how fast it settles, and its floor.
  @initial_error 0.12
  @settle 0.93
  @min_error 0.012
  @recoil_compensation 0.75
  @cover_refresh_ticks 10
  @stuck_ticks 20

  # Preferred engagement band (metres) and the range bots open fire from.
  @bands %{"ranger" => {6.0, 15.0, 24.0}, "warden" => {1.5, 5.5, 10.0}}

  def think(s, p) do
    skill = :erlang.phash2(p.id, 1000) / 1000
    target = choose_target(s, p)
    p = remember(s, p, target)
    w = Weapons.spec(p.class)
    {near, far, reach} = Map.get(@bands, p.class, @bands["ranger"])

    retreat = p.hp < @retreat_hp
    medicine = if retreat, do: nearest_ready_supply(s, p)
    objective = Objective.current(s)
    seen = if target, do: perceived(s, target)
    target_distance = if target, do: Physics.distance(p, seen), else: 100.0
    engaging = target != nil and target_distance < reach and medicine == nil

    healing =
      p.class == "warden" and
        Enum.any?(s.players, fn {_, ally} ->
          ally.team == p.team and ally.hp > 0 and ally.hp <= Player.max_hp(ally) - 30 and
            Physics.distance(p, ally) < 3.5 and Physics.line_of_sight?(p, ally)
        end)

    attacking =
      engaging and s.tick - p.ai_seen > @ability_delay_ticks and target_distance < @ability_range

    on_point = on_point?(p, objective)

    {goal, p} =
      cond do
        medicine -> {medicine, p}
        retreat and target -> cover(s, p, seen)
        # Close fights are duels; at range the bot keeps pushing the relay and fires on the move.
        engaging and target_distance <= far and not on_point -> {nil, p}
        engaging -> {objective, p}
        memory_fresh?(s, p) -> {p.ai_memory, p}
        true -> {objective, p}
      end

    holding = goal == objective and on_point

    p = if goal && not holding, do: follow(s, p, goal), else: %{p | ai_path: []}
    p = unstick(s, p, goal != nil and not holding)

    # Where to move (world angle and throttle) and where to look.
    {move, throttle, p} =
      cond do
        goal == nil -> duel(s, p, seen, target_distance, near, far)
        # Defend the relay by strafing inside the capture circle.
        holding and engaging -> strafe(s, p, seen, 0.6)
        holding -> {nil, 0.0, p}
        true -> {travel_angle(p, goal), 1.0, p}
      end

    {look_yaw, look_pitch, error} = look(s, p, target, seen, move, holding, skill)
    p = %{p | ai_error: error}

    delta =
      :math.atan2(:math.sin(look_yaw - p.angle), :math.cos(look_yaw - p.angle))

    angle = p.angle + clamp(delta, @max_turn)
    pitch = p.pitch + clamp(look_pitch - p.pitch, @max_pitch_turn)

    fire =
      engaging and s.tick - p.ai_seen >= @reaction_ticks + round(skill * 4) and
        abs(delta) < tolerance(target_distance) and p.ammo > 0 and
        burst_allowed?(s, p, target_distance) and Physics.line_of_sight?(p, target)

    reload =
      p.reload_until == 0 and p.ammo < w.mag and
        (p.ammo == 0 or (target == nil and p.ammo < w.mag * 0.5) or
           (target != nil and not engaging and p.ammo < w.mag * 0.3))

    crouch =
      engaging and fire and p.class == "ranger" and target_distance > 12.0 and
        rem(div(s.tick, 30) + round(skill * 7), 3) == 0

    {forward, strafe} =
      if move,
        do: {:math.cos(move - angle) * throttle, :math.sin(move - angle) * throttle},
        else: {0.0, 0.0}

    blocked =
      move != nil and throttle > 0.5 and
        not Scene.clear?(p.x + :math.cos(move) * 0.42, p.y + :math.sin(move) * 0.42, p.z)

    distance_to_goal = if goal, do: Physics.distance(p, goal), else: 0.0

    %{
      p
      | input_at: s.tick,
        input: %{
          forward: forward,
          strafe: strafe,
          angle: angle,
          pitch: max(-1.15, min(1.15, pitch)),
          jump: blocked or Map.get(p, :ai_jump, false),
          swim: Physics.distance(0, 0, forward, strafe) > 0.1,
          fire: fire,
          sprint:
            not healing and not fire and
              ((not engaging and distance_to_goal > @sprint_distance) or
                 (p.class == "warden" and attacking)),
          crouch: crouch,
          reload: reload,
          ability: healing or attacking,
          view_tick: nil
        }
    }
    |> Map.delete(:ai_jump)
  end

  ## Perception

  defp choose_target(s, p) do
    players =
      for id <- s.order,
          q = s.players[id],
          q.team != p.team and q.hp > 0,
          visible?(p, q),
          do: {score(p, q, 0.0), q}

    structures =
      for id <- State.entity_ids(s),
          e = s.entities[id],
          e.team != p.team and e.hp > 0 and Physics.distance(p, e) < 14.0,
          Physics.line_of_sight?(p, e),
          do: {score(p, e, if(e.kind == "drone", do: 6.0, else: 10.0)), e}

    case Enum.min_by(players ++ structures, &elem(&1, 0), fn -> nil end) do
      nil -> nil
      {_, target} -> target
    end
  end

  defp visible?(p, q) do
    d = Physics.distance(p, q)

    d < @sight_range and (d < @awareness or in_view?(p, q)) and Physics.line_of_sight?(p, q)
  end

  defp in_view?(p, q) do
    bearing = :math.atan2(q.y - p.y, q.x - p.x)
    abs(:math.atan2(:math.sin(bearing - p.angle), :math.cos(bearing - p.angle))) < @fov
  end

  # Lower is better: close, wounded and already-tracked targets come first.
  defp score(p, q, bias) do
    sticky = if p.ai_target == q.id, do: -4.0, else: 0.0
    Physics.distance(p, q) + q.hp / 25 + sticky + bias
  end

  # Acquisition resets reaction and aim; sight, gunfire and incoming damage update memory.
  defp remember(s, p, target) do
    p =
      if target && p.ai_target != target.id,
        do: %{
          p
          | ai_target: target.id,
            ai_seen: s.tick,
            ai_error: @initial_error + 0.004 * Physics.distance(p, target)
        },
        else: if(target, do: p, else: %{p | ai_target: nil})

    cond do
      target ->
        %{p | ai_memory: spot(target, s.tick)}

      attacker = recent_attacker(s, p) ->
        %{p | ai_memory: spot(attacker, s.tick)}

      noise = heard(s, p) ->
        %{p | ai_memory: spot(noise, s.tick)}

      true ->
        p
    end
  end

  defp spot(q, tick), do: %{x: q.x, y: q.y, z: Map.get(q, :z, 0.0), tick: tick}

  defp recent_attacker(s, p) do
    with by when is_binary(by) <- p.hurt_by,
         true <- s.tick - p.hurt_at <= 2,
         %{hp: hp} = q when hp > 0 <- s.players[by] do
      q
    else
      _ -> nil
    end
  end

  defp heard(s, p) do
    s.order
    |> Enum.map(&s.players[&1])
    |> Enum.filter(
      &(&1.team != p.team and &1.hp > 0 and s.tick - &1.last_shot <= @noise_ticks and
          Physics.distance(p, &1) < @hearing)
    )
    |> Enum.min_by(&Physics.distance(p, &1), fn -> nil end)
  end

  defp memory_fresh?(s, p) do
    case p.ai_memory do
      %{tick: tick} = m -> s.tick - tick < @memory_ticks and Physics.distance(p, m) > 1.5
      _ -> false
    end
  end

  # Players are seen with a short delay, like human reaction time; structures do not move.
  defp perceived(_s, %{kind: _} = e), do: e

  defp perceived(s, q) do
    case Enum.find(s.history, &(&1.tick == s.tick - @perception_lag)) do
      %{players: players} -> Map.merge(q, Map.get(players, q.id, %{}))
      nil -> q
    end
  end

  defp nearest_ready_supply(s, p) do
    s.supplies
    |> Enum.filter(&(&1.ready_at <= s.tick))
    |> Enum.min_by(&Physics.distance(p, &1), fn -> nil end)
  end

  ## Movement

  defp follow(s, p, goal) do
    goal_point = {goal.x, goal.y, Map.get(goal, :z, 0.0)}

    moved_goal =
      case p.ai_goal do
        {x, y, z} ->
          Physics.distance(x, y, goal.x, goal.y) > 2.0 or abs(z - elem(goal_point, 2)) > 0.5

        _ ->
          true
      end

    p =
      if s.tick >= p.ai_route_at or moved_goal do
        path = Navigation.path({p.x, p.y, p.z}, goal_point)

        %{
          p
          | ai_path: Navigation.smooth({p.x, p.y, p.z}, path),
            ai_route_at: s.tick + @reroute_ticks,
            ai_goal: goal_point
        }
      else
        p
      end

    path =
      Enum.drop_while(p.ai_path, fn {x, y, z} ->
        Physics.distance(p.x, p.y, x, y) < @waypoint_reached and abs(p.z - z) < 0.4
      end)

    %{p | ai_path: path}
  end

  defp travel_angle(p, goal) do
    {wx, wy} =
      case p.ai_path do
        [{x, y, _} | _] -> {x, y}
        [] -> {goal.x, goal.y}
      end

    :math.atan2(wy - p.y, wx - p.x)
  end

  # Keeps the preferred range: close in, back off, or strafe while shooting.
  defp duel(s, p, target, distance, near, far) do
    toward = :math.atan2(target.y - p.y, target.x - p.x)
    {side, _, p} = strafe(s, p, target, 1.0)

    cond do
      distance > far ->
        # Close the gap diagonally so the approach is not a straight line.
        {toward + p.ai_strafe * 0.45, 1.0, p}

      distance < near ->
        away = toward + :math.pi() - p.ai_strafe * 0.5

        if Scene.clear?(p.x + :math.cos(away) * 0.6, p.y + :math.sin(away) * 0.6, p.z),
          do: {away, 1.0, p},
          else: {side, 1.0, p}

      true ->
        {side, 0.85, p}
    end
  end

  # Side-steps across the line of fire, switching direction at irregular intervals or at walls.
  defp strafe(s, p, target, throttle) do
    toward = :math.atan2(target.y - p.y, target.x - p.x)

    p =
      if s.tick >= p.ai_strafe_at do
        switch = 8 + :erlang.phash2({p.id, s.tick}, 16)
        %{p | ai_strafe: -p.ai_strafe, ai_strafe_at: s.tick + switch}
      else
        p
      end

    side = toward + p.ai_strafe * :math.pi() / 2

    p =
      if Scene.clear?(p.x + :math.cos(side) * 0.6, p.y + :math.sin(side) * 0.6, p.z),
        do: p,
        else: %{p | ai_strafe: -p.ai_strafe, ai_strafe_at: s.tick + 10}

    {toward + p.ai_strafe * :math.pi() / 2, throttle, p}
  end

  defp on_point?(p, objective),
    do: Physics.distance(p, objective) < 1.2 and abs(p.z - objective.z) < 0.5

  # A nearby standing spot the threat cannot see; recomputed every few ticks.
  defp cover(s, p, threat) do
    case Map.get(p, :ai_cover) do
      {spot, until} when until > s.tick ->
        {spot, p}

      _ ->
        spot =
          for radius <- [2.5, 4.5],
              i <- 0..11,
              angle = i * :math.pi() / 6,
              x = p.x + :math.cos(angle) * radius,
              y = p.y + :math.sin(angle) * radius,
              z = Scene.standing_height(x, y, p.z + 0.3),
              abs(z - p.z) < 0.35 and Scene.clear?(x, y, z),
              point = %{x: x, y: y, z: z},
              not Physics.line_of_sight?(threat, point) do
            point
          end
          |> Enum.min_by(&Physics.distance(p, &1), fn -> nil end)

        spot = spot || p.ai_memory || %{x: p.x, y: p.y, z: p.z}
        {spot, Map.put(p, :ai_cover, {spot, s.tick + @cover_refresh_ticks})}
    end
  end

  # A bot that has barely moved for a second while travelling jumps, sidesteps and replans.
  defp unstick(s, p, travelling) do
    {x, y, since} = p.ai_stuck

    cond do
      not travelling ->
        %{p | ai_stuck: {p.x, p.y, s.tick}}

      s.tick - since < @stuck_ticks ->
        p

      Physics.distance(p.x, p.y, x, y) < 0.4 ->
        p
        |> Map.merge(%{ai_stuck: {p.x, p.y, s.tick}, ai_route_at: 0, ai_strafe: -p.ai_strafe})
        |> Map.put(:ai_jump, true)

      true ->
        %{p | ai_stuck: {p.x, p.y, s.tick}}
    end
  end

  ## Aim

  defp look(s, p, target, seen, move, holding, skill) do
    cond do
      target != nil ->
        aim(s, p, seen, skill)

      p.ai_memory != nil and s.tick - p.ai_memory.tick < @memory_ticks ->
        # Pre-aim where the enemy was last seen or heard.
        m = p.ai_memory
        {:math.atan2(m.y - p.y, m.x - p.x), pitch_to(p, m.x, m.y, m.z + 1.35), 0.0}

      holding ->
        # Watch the approach from the enemy side, sweeping slowly.
        %{x: x, y: y} = Scene.anchor("spawns", 1 - p.team)
        sweep = :math.sin(s.tick * 0.045 + skill * 6) * 0.9
        {:math.atan2(y - p.y, x - p.x) + sweep, 0.0, 0.0}

      move != nil ->
        {move, travel_pitch(p), 0.0}

      true ->
        {p.angle, 0.0, 0.0}
    end
  end

  defp aim(s, p, seen, skill) do
    floor = @min_error * (0.6 + skill)
    own = Physics.speed(p) / Player.walk_speed() * 0.02
    error = max(floor, p.ai_error * @settle)
    seed = :erlang.phash2(p.id, 1000) / 100.0

    wobble =
      (error + own) *
        (:math.sin(s.tick * 0.19 + seed) * 0.62 + :math.sin(s.tick * 0.071 + seed) * 0.38)

    wobble_pitch = (error + own) * 0.45 * :math.sin(s.tick * 0.13 + seed * 2)
    yaw = :math.atan2(seen.y - p.y, seen.x - p.x) - p.recoil_yaw * @recoil_compensation

    pitch =
      pitch_to(p, seen.x, seen.y, Physics.aim_height(seen)) - p.recoil * @recoil_compensation

    {yaw + wobble, pitch + wobble_pitch, error}
  end

  defp pitch_to(p, x, y, z),
    do:
      :math.atan2(z - (p.z + Physics.eye_height(p)), max(Physics.distance(p.x, p.y, x, y), 0.01))

  # Look along slopes and stairs while walking instead of at the floor ahead.
  defp travel_pitch(p) do
    case p.ai_path do
      [{x, y, z} | _] -> clamp(pitch_to(p, x, y, z + Physics.eye_height(p)), 0.35)
      [] -> 0.0
    end
  end

  # Fire only when the crosshair is roughly on the body at this range.
  defp tolerance(distance), do: max(0.04, :math.atan(0.4 / max(distance, 0.5)))

  # Long range: short taps that let the bloom recover; mid range: bursts; close: full auto.
  defp burst_allowed?(s, p, distance) do
    limit =
      cond do
        distance > 14 -> 3
        distance > 8 -> 6
        true -> 1000
      end

    p.burst < limit or s.tick - p.last_shot >= 10
  end

  defp clamp(value, limit), do: max(-limit, min(limit, value))
end
