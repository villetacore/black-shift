defmodule BlackShift.Game.Combat do
  @moduledoc """
  Hitscan weapons, class abilities, damage, kills and their rewards.

  Weapon numbers live in `BlackShift.Game.Weapons`. A shot leaves the eye
  along the view direction plus the shooter's authoritative recoil, spread by
  the current accuracy cone. Players are hit in three zones (head, torso,
  legs). Human shots are tested against where targets were at the tick the
  client was displaying, within `Player.max_rewind_ticks/0`.
  """
  alias BlackShift.Game.{Physics, Player, State, Structures, Weapons}
  alias BlackShift.World.Scene

  @damage_per_level 0.09
  # Bots deal less damage than humans so practice stays winnable.
  @bot_damage 0.75
  @structure_hit_radius 0.42
  # Hit zones of a player body, as radius and share of the hit box height.
  @head_radius 0.17
  @head_depth 0.30
  @torso_radius 0.30
  @legs_radius 0.24
  @legs_share 0.43
  # Being hit jolts the victim's aim upwards (radians).
  @flinch 0.012

  @kill_xp 55
  @kill_score 5
  @structure_xp 30
  @structure_score 3

  @ability_cooldown_ticks 160
  # Ranger: Phase Dash, a burst of 12 m/s for the next 4 ticks (2.4 m) that then slides out.
  @dash_speed 12.0
  @dash_ticks 4
  @dash_distance 2.4
  # Warden: Field Pulse.
  @pulse_radius 3.5
  @pulse_heal 30
  @pulse_player_damage 35
  @pulse_structure_damage 45
  @pulse_push 5.0
  @pulse_lift 2.5

  def ability_cooldown_ticks, do: @ability_cooldown_ticks

  @doc """
  Per-tick weapon upkeep: accuracy and recoil recover, a requested reload
  starts and a running reload completes (one shell at a time for shotguns).
  """
  def handle_weapon(s, id, input) do
    State.update_player(s, id, fn p ->
      w = Weapons.spec(p.class)

      p = %{
        p
        | spread: p.spread * w.bloom_recovery,
          recoil: p.recoil * w.recoil_recovery,
          recoil_yaw: p.recoil_yaw * w.recoil_recovery
      }

      p =
        if input.reload and p.ammo < w.mag and p.reload_until == 0,
          do: %{p | reload_until: s.tick + w.reload},
          else: p

      cond do
        p.reload_until == 0 or s.tick < p.reload_until -> p
        not w.per_shell or p.ammo + 1 >= w.mag -> %{p | ammo: w.mag, reload_until: 0}
        true -> %{p | ammo: p.ammo + 1, reload_until: s.tick + w.reload}
      end
    end)
  end

  @doc "Fires the player's weapon along its view direction, if the weapon is ready."
  def shoot(s, id) do
    p = s.players[id]
    w = Weapons.spec(p.class)

    cond do
      s.over or p.hp <= 0 or s.tick < p.fire_at ->
        s

      p.ammo <= 0 ->
        if p.reload_until == 0,
          do: State.update_player(s, id, &%{&1 | reload_until: s.tick + w.reload}),
          else: s

      # A magazine reload must finish; a shotgun can fire the shells it has loaded so far.
      p.reload_until > 0 and not w.per_shell ->
        s

      true ->
        fire(s, p, w)
    end
  end

  defp fire(s, p, w) do
    burst = if s.tick - p.last_shot <= w.interval + 1, do: p.burst + 1, else: 1
    view = Player.view_tick(p, s.tick)
    targets = targets(s, p, view)
    eye = p.z + Physics.eye_height(p)
    aim_yaw = p.angle + p.recoil_yaw
    aim_pitch = max(-1.4, min(1.4, p.pitch + p.recoil))

    {s, hits} =
      p
      |> Weapons.offsets(s.tick)
      |> Enum.reduce({s, %{}}, fn {yaw, pitch}, {s, hits} ->
        ray(s, p, w, eye, aim_yaw + yaw, aim_pitch + pitch, targets, hits)
      end)

    {side, up} = Weapons.kick(p.class, burst)
    ammo = p.ammo - 1

    s =
      State.update_player(
        s,
        p.id,
        &%{
          &1
          | fire_at: s.tick + w.interval,
            ammo: ammo,
            reload_until: if(ammo == 0, do: s.tick + w.reload, else: 0),
            last_shot: s.tick,
            burst: burst,
            spread: min(w.max_bloom, &1.spread + w.bloom),
            recoil: &1.recoil + up,
            recoil_yaw: &1.recoil_yaw + side
        }
      )

    apply_hits(s, p, hits)
  end

  # Everything a shot can hit; players are placed where the shooter saw them.
  defp targets(s, p, view) do
    rewound = if view < s.tick, do: rewind(s, view), else: %{}

    players =
      for qid <- s.order,
          q = s.players[qid],
          q.team != p.team and q.hp > 0,
          do: {:player, qid, Map.merge(q, Map.get(rewound, qid, %{}))}

    entities =
      for eid <- State.entity_ids(s),
          e = s.entities[eid],
          e.team != p.team and e.hp > 0,
          do: {:entity, eid, e}

    players ++ entities
  end

  defp rewind(s, view) do
    case Enum.find(s.history, &(&1.tick == view)) do
      nil -> %{}
      frame -> frame.players
    end
  end

  defp ray(s, p, w, eye, yaw, pitch, targets, hits) do
    dir = {:math.cos(yaw) * :math.cos(pitch), :math.sin(yaw) * :math.cos(pitch), :math.sin(pitch)}
    {dx, dy, dz} = dir
    origin = {p.x, p.y, eye}
    wall = Scene.raycast([p.x, p.y, eye], [dx, dy, dz], w.range)

    {d, hit} =
      Enum.reduce(targets, {wall, nil}, fn {kind, qid, q}, {best, hit} ->
        case intersect(kind, origin, dir, q, best) do
          {near, zone} -> {near, {kind, qid, zone}}
          nil -> {best, hit}
        end
      end)

    s =
      beam(s, Map.put(p, :beam_z, eye), %{x: p.x + dx * d, y: p.y + dy * d, beam_z: eye + dz * d})

    case hit do
      nil ->
        {s, hits}

      {kind, qid, zone} ->
        multiplier =
          case zone do
            :head -> w.head
            :legs -> w.legs
            _ -> 1.0
          end

        damage = w.damage * multiplier * Weapons.falloff(w, d) * scale(p)

        {s,
         Map.update(
           hits,
           {kind, qid},
           %{damage: damage, head: zone == :head, push: {dx * w.push, dy * w.push}},
           fn h ->
             {px, py} = h.push

             %{
               h
               | damage: h.damage + damage,
                 head: h.head or zone == :head,
                 push: {px + dx * w.push, py + dy * w.push}
             }
           end
         )}
    end
  end

  defp scale(p) do
    level = 1.0 + @damage_per_level * (p.level - 1)
    if p.bot, do: level * @bot_damage, else: level
  end

  # Nearest hit closer than `best`: {distance, zone} or nil.
  defp intersect(:entity, origin, dir, e, best) do
    base = Map.get(e, :z, 0.0)

    case ray_box(
           origin,
           dir,
           e,
           @structure_hit_radius,
           base,
           base + Physics.hitbox_height(e),
           best
         ) do
      :miss -> nil
      near -> {near, :body}
    end
  end

  defp intersect(:player, origin, dir, q, best) do
    base = q.z
    top = base + Physics.hitbox_height(q)
    knees = base + (top - base) * @legs_share
    neck = top - @head_depth

    [
      {:head, @head_radius, neck, top},
      {:torso, @torso_radius, knees, neck},
      {:legs, @legs_radius, base, knees}
    ]
    |> Enum.reduce(nil, fn {zone, radius, lo, hi}, found ->
      limit = if found, do: elem(found, 0), else: best

      case ray_box(origin, dir, q, radius, lo, hi, limit) do
        :miss -> found
        near -> {near, zone}
      end
    end)
  end

  defp apply_hits(s, _p, hits) when map_size(hits) == 0, do: s

  defp apply_hits(s, p, hits) do
    {s, head, kill} =
      hits
      |> Enum.sort()
      |> Enum.reduce({s, false, false}, fn
        {{:player, qid}, h}, {s, head, kill} ->
          alive = s.players[qid].hp > 0
          {px, py} = h.push
          s = State.update_player(s, qid, &Physics.push(&1, px, py))
          s = hurt_player(s, qid, max(1, round(h.damage)), p.id, p)
          {s, head or h.head, kill or (alive and s.players[qid].hp <= 0)}

        {{:entity, eid}, h}, {s, head, kill} ->
          alive = s.entities[eid].hp > 0
          s = hurt_entity(s, eid, max(1, round(h.damage)), p.id)
          {s, head, kill or (alive and s.entities[eid].hp <= 0)}
      end)

    State.update_player(s, p.id, &%{&1 | hits: &1.hits + 1, hit_head: head, hit_kill: kill})
  end

  @doc "Uses the player's class ability (dash or pulse), if it is off cooldown."
  def ability(s, id) do
    p = s.players[id]

    if s.over or p.hp <= 0 or s.tick < p.ability_at do
      s
    else
      s = State.update_player(s, id, &%{&1 | ability_at: s.tick + @ability_cooldown_ticks})

      if p.class == "warden",
        do: pulse(s, p),
        else: dash(s, p)
    end
  end

  # The dash follows the movement keys (or the view when standing still). It is
  # a burst of velocity, so walls stop it naturally; the speed bonus is granted
  # only when there is room to actually travel.
  defp dash(s, p) do
    {dx, dy} = dash_direction(p)
    probe = Physics.move(p, dx * @dash_distance, dy * @dash_distance)

    State.update_player(s, p.id, fn player ->
      player = %{
        player
        | vx: dx * @dash_speed,
          vy: dy * @dash_speed,
          dash_until: s.tick + @dash_ticks + 1,
          crouching: false
      }

      if Physics.distance(p, probe) >= 0.5,
        do: %{player | boost_until: s.tick + 20, boost: 1.0},
        else: player
    end)
  end

  defp dash_direction(p) do
    %{forward: f, strafe: r} = p.input

    if abs(f) + abs(r) < 0.01 do
      {:math.cos(p.angle), :math.sin(p.angle)}
    else
      {sin, cos} = {:math.sin(p.angle), :math.cos(p.angle)}
      {x, y} = {cos * f - sin * r, sin * f + cos * r}
      n = max(1.0e-6, :math.sqrt(x * x + y * y))
      {x / n, y / n}
    end
  end

  # Q heals; Shift+Q trades healing for offensive pressure and throws enemies back.
  defp pulse(s, p) do
    offensive = p.input.sprint

    s =
      Enum.reduce(s.order, s, fn qid, s ->
        q = s.players[qid]

        cond do
          not (q.hp > 0 and in_pulse?(p, q)) ->
            s

          q.team == p.team and not offensive ->
            State.update_player(s, qid, &Player.heal(&1, @pulse_heal))

          q.team != p.team and offensive ->
            d = max(0.3, Physics.distance(p, q))
            {px, py} = {(q.x - p.x) / d * @pulse_push, (q.y - p.y) / d * @pulse_push}

            s
            |> State.update_player(qid, &Physics.push(&1, px, py, @pulse_lift))
            |> hurt_player(qid, @pulse_player_damage, p.id, p)

          true ->
            s
        end
      end)

    Enum.reduce(State.entity_ids(s), s, fn eid, s ->
      e = s.entities[eid]

      if offensive and e.team != p.team and in_pulse?(p, e),
        do: hurt_entity(s, eid, @pulse_structure_damage, p.id),
        else: s
    end)
  end

  defp in_pulse?(p, q),
    do:
      Physics.distance(p, q) ** 2 + (Physics.aim_height(p) - Physics.aim_height(q)) ** 2 <
        @pulse_radius ** 2 and Physics.line_of_sight?(p, q)

  @doc """
  Damages a player. Spawn protection and death are handled here; `killer` gets
  the kill. `source` is the body the damage came from (for the victim's damage
  direction indicator) or `:fall`.
  """
  def hurt_player(s, id, amount, killer \\ nil, source \\ nil) do
    p = s.players[id]

    cond do
      s.over or p.hp <= 0 or s.tick < p.protected_until ->
        s

      p.hp > amount ->
        State.update_player(s, id, &wound(&1, amount, s.tick, killer, source))

      true ->
        s =
          State.update_player(
            s,
            id,
            &(&1 |> wound(amount, s.tick, killer, source) |> Player.die(s.tick))
          )

        cond do
          killer ->
            s
            |> State.update_player(killer, &Player.reward(%{&1 | kills: &1.kills + 1}, @kill_xp))
            |> State.add_score(s.players[killer].team, @kill_score)
            |> State.feed(s.players[killer].name <> " > " <> p.name)

          source == :fall ->
            State.feed(s, "FALL > " <> p.name)

          true ->
            State.feed(s, "DEFENCE > " <> p.name)
        end
    end
  end

  defp wound(p, amount, tick, killer, source) do
    dir =
      case source do
        %{x: x, y: y} -> :math.atan2(y - p.y, x - p.x)
        _ -> nil
      end

    flinch = if is_map(source), do: @flinch, else: 0.0

    %{
      p
      | hp: max(0, p.hp - amount),
        hurt_at: tick,
        hurt_dir: dir,
        hurt_by: killer,
        recoil: p.recoil + flinch
    }
  end

  @doc "Damages a structure. A core is immune while its team still has a tower; losing it ends the match."
  def hurt_entity(s, id, amount, killer \\ nil) do
    e = s.entities[id]

    shielded =
      e.kind == "core" and
        Enum.any?(s.entities, fn {_, t} -> t.kind == "tower" and t.team == e.team and t.hp > 0 end)

    cond do
      s.over or e.hp <= 0 or shielded ->
        s

      e.hp > amount ->
        State.update_entity(s, id, &%{&1 | hp: &1.hp - amount})

      true ->
        s = State.update_entity(s, id, &%{&1 | hp: 0})
        s = Structures.drone_destroyed(s, e)

        s =
          if e.kind == "tower",
            do:
              State.feed(
                s,
                "TOWER DOWN // " <>
                  if(e.team == 0, do: "CYAN CORE EXPOSED", else: "AMBER CORE EXPOSED")
              ),
            else: s

        s =
          if killer,
            do:
              s
              |> State.update_player(killer, &Player.reward(&1, @structure_xp))
              |> State.add_score(s.players[killer].team, @structure_score),
            else: s

        if e.kind == "core",
          do: State.feed(%{s | over: true, winner: 1 - e.team}, "CORE DESTROYED"),
          else: s
    end
  end

  @doc "Records a tracer from `a` to `b` for this tick's snapshot."
  def beam(s, a, b) do
    tracer = %{
      x: a.x,
      y: a.y,
      z: Map.get(a, :beam_z, Physics.aim_height(a)),
      ex: b.x,
      ey: b.y,
      ez: Map.get(b, :beam_z, Physics.aim_height(b)),
      team: a.team
    }

    %{s | beams: [tracer | s.beams]}
  end

  # Slab test of a ray against an axis-aligned box around the target; returns the entry distance or :miss.
  defp ray_box({ox, oy, oz}, {dx, dy, dz}, target, radius, lo, hi, limit) do
    slabs = [
      {ox, dx, target.x - radius, target.x + radius},
      {oy, dy, target.y - radius, target.y + radius},
      {oz, dz, lo, hi}
    ]

    result =
      Enum.reduce_while(slabs, {0.0, limit}, fn {origin, direction, lo, hi}, {near, far} ->
        if abs(direction) < 1.0e-8 do
          if origin < lo or origin > hi, do: {:halt, :miss}, else: {:cont, {near, far}}
        else
          a = (lo - origin) / direction
          b = (hi - origin) / direction
          near = max(near, min(a, b))
          far = min(far, max(a, b))
          if near > far, do: {:halt, :miss}, else: {:cont, {near, far}}
        end
      end)

    case result do
      {near, _} -> near
      :miss -> :miss
    end
  end
end
