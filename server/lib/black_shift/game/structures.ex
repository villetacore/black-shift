defmodule BlackShift.Game.Structures do
  @moduledoc """
  Team structures: cores, sentinel towers and periodic drone waves.

  Towers and drones lock onto a target and warn it before the first shot;
  drones without a target route toward the enemy core.
  """
  alias BlackShift.Game.{Combat, Physics, Rules, State}
  alias BlackShift.World.{Navigation, Scene}

  @core_hp 800
  @tower_hp 350
  @drone_hp 55

  @wave_interval_ticks 240
  @tower_range 5.5
  @drone_range 4.0
  # Delay between acquiring a target and the first shot; doubles as the warning window.
  @lock_ticks 16
  @fire_interval_ticks 20
  @tower_damage 12
  @drone_damage 6
  # Metres per tick.
  @drone_speed 0.055
  @drone_reroute_ticks 80

  def lock_ticks, do: @lock_ticks

  def wave(s) do
    %{
      remaining:
        Rules.seconds(
          @wave_interval_ticks - rem(s.tick - 1 + @wave_interval_ticks, @wave_interval_ticks)
        ),
      active: Enum.count(s.entities, fn {_, e} -> e.kind == "drone" and e.hp > 0 end)
    }
  end

  # Track a wave independently of drone pruning, so its bonus is awarded once.
  def drone_destroyed(s, %{kind: "drone", wave: key, team: team}) do
    left = Map.fetch!(s.waves, key) - 1

    if left == 0 do
      %{s | waves: Map.delete(s.waves, key)}
      |> State.add_score(1 - team, 4)
      |> State.feed("WAVE CLEARED // " <> if(team == 1, do: "CYAN +4", else: "AMBER +4"))
    else
      %{s | waves: Map.put(s.waves, key, left)}
    end
  end

  def drone_destroyed(s, _), do: s

  @doc "Cores and towers for both teams at the map's base positions."
  def initial do
    for team <- 0..1, kind <- ["core", "tower"], into: %{} do
      %{x: x, y: y, z: z} = Scene.anchor(if(kind == "core", do: "cores", else: "towers"), team)
      hp = if kind == "core", do: @core_hp, else: @tower_hp
      e = new(kind <> "-#{team}", kind, team, x, y, hp, z)
      {e.id, e}
    end
  end

  defp new(id, kind, team, x, y, hp, z),
    do: %{
      id: id,
      kind: kind,
      team: team,
      x: x,
      y: y,
      z: z,
      vz: 0.0,
      grounded: true,
      coyote_until: -1,
      hp: hp,
      max_hp: hp,
      fire_at: 0,
      locked: nil,
      lock_at: -100,
      route: [],
      route_at: 0
    }

  @doc "Spawns drone waves, updates every structure and removes destroyed drones."
  def step(s) do
    s =
      if rem(s.tick, @wave_interval_ticks) == @wave_interval_ticks - 59,
        do: State.feed(s, "DRONE WAVE // IN 3s"),
        else: s

    s = if rem(s.tick, @wave_interval_ticks) == 1, do: spawn_wave(s), else: s
    s = Enum.reduce(State.entity_ids(s), s, &step_entity(&2, &1))
    %{s | entities: Map.reject(s.entities, fn {_, e} -> e.kind == "drone" and e.hp <= 0 end)}
  end

  # Two drones per team, one on each side of the spawn point.
  defp spawn_wave(s) do
    for(team <- 0..1, lane <- [-1, 1], do: {team, lane})
    |> Enum.reduce(s, fn {team, lane}, s ->
      serial = s.serial + 1
      %{x: x, y: y, z: z} = Scene.anchor("spawns", team)
      key = {s.tick, team}
      e = new("drone-#{serial}", "drone", team, x, y + lane, @drone_hp, z) |> Map.put(:wave, key)

      %{
        s
        | serial: serial,
          entities: Map.put(s.entities, e.id, e),
          waves: Map.update(s.waves, key, 1, &(&1 + 1))
      }
    end)
  end

  defp step_entity(s, id) do
    e = s.entities[id]
    e = if e.kind == "drone", do: Physics.fall(e, false, s.tick), else: e
    s = State.update_entity(s, id, fn _ -> e end)

    if s.over or e.hp <= 0 or e.kind == "core" do
      s
    else
      target = nearest_target(s, e)

      cond do
        target != nil and e.locked != elem(target, 1).id ->
          State.update_entity(
            s,
            id,
            &%{&1 | locked: elem(target, 1).id, lock_at: s.tick, fire_at: s.tick + @lock_ticks}
          )

        target != nil and s.tick >= e.fire_at ->
          fire(s, e, target)

        target == nil and e.kind == "drone" ->
          advance(s, e)

        target == nil ->
          State.update_entity(s, id, &%{&1 | locked: nil})

        true ->
          s
      end
    end
  end

  defp nearest_target(s, e) do
    reach = if e.kind == "tower", do: @tower_range, else: @drone_range

    (Enum.map(s.order, &{:player, s.players[&1]}) ++
       Enum.map(State.entity_ids(s), &{:entity, s.entities[&1]}))
    |> Enum.filter(fn {_, q} ->
      q.hp > 0 and q.team != e.team and Physics.distance(e, q) < reach and
        Physics.line_of_sight?(e, q)
    end)
    |> Enum.min_by(fn {_, q} -> Physics.distance(e, q) end, fn -> nil end)
  end

  defp fire(s, e, {kind, q}) do
    s = State.update_entity(s, e.id, &%{&1 | fire_at: s.tick + @fire_interval_ticks})
    damage = if e.kind == "tower", do: @tower_damage, else: @drone_damage

    s =
      if kind == :player,
        do: Combat.hurt_player(s, q.id, damage, nil, e),
        else: Combat.hurt_entity(s, q.id, damage)

    Combat.beam(s, e, q)
  end

  defp advance(s, e) do
    destination = s.entities["core-#{1 - e.team}"]

    e =
      if s.tick >= e.route_at and destination do
        %{
          e
          | route:
              Navigation.path({e.x, e.y, e.z}, {destination.x, destination.y, destination.z}),
            route_at: s.tick + @drone_reroute_ticks
        }
      else
        e
      end

    route =
      Enum.drop_while(e.route, fn {x, y, z} ->
        Physics.distance(e.x, e.y, x, y) < 0.12 and abs(e.z - z) < 0.4
      end)

    {dx, dy} =
      case route do
        [{x, y, _} | _] ->
          length = max(0.001, Physics.distance(e.x, e.y, x, y))
          {(x - e.x) / length * @drone_speed, (y - e.y) / length * @drone_speed}

        [] ->
          {0.0, 0.0}
      end

    moved = Physics.move(e, dx, dy)

    State.update_entity(s, e.id, fn _ ->
      %{moved | locked: nil, route: route}
    end)
  end
end
