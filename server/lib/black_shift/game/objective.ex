defmodule BlackShift.Game.Objective do
  @moduledoc """
  The rotating relay objective.

  The active point moves through the map's objectives every minute. A team must
  secure a point for a short, visible capture window before it scores. Empty
  and contested points stop scoring and bleed capture progress, giving
  defenders time to respond.
  """
  alias BlackShift.Game.{Physics, Player, Rules, State}
  alias BlackShift.World.Scene

  @rotation_seconds 60
  @capture_radius 2
  @capture_ticks 40
  @capture_decay 2
  @rotation_warning_seconds 15
  @hold_bonus_ticks 300
  @hold_bonus_score 5
  @tick_score 1
  @tick_xp 8

  defp rotation_ticks, do: @rotation_seconds * Rules.tick_rate()

  @doc "Capture state safe for snapshots: side, normalised progress and contest status."
  def capture(s) do
    %{
      team: s.capture_team,
      progress: s.capture_ticks / @capture_ticks,
      active: s.capture_team >= 0 and contenders(s, current(s)) == s.capture_team,
      contested: contenders(s, current(s)) == :contested
    }
  end

  @doc "The active objective at the state's tick and the one that follows it."
  def current(%{tick: tick}) do
    points = Scene.objectives()
    index = rem(div(tick, rotation_ticks()), length(points))
    point = Enum.at(points, index)
    next = Enum.at(points, rem(index + 1, length(points)))

    %{
      x: point["x"],
      y: point["y"],
      z: Map.get(point, "z", 0.0),
      name: point["name"],
      remaining: @rotation_seconds - div(rem(tick, rotation_ticks()), Rules.tick_rate()),
      next_name: next["name"],
      next_x: next["x"],
      next_y: next["y"],
      next_z: Map.get(next, "z", 0.0)
    }
  end

  def step(s) do
    s
    |> announce_rotation()
    |> update_control()
  end

  defp announce_rotation(s) do
    cond do
      rem(s.tick, rotation_ticks()) == 0 ->
        s
        |> Map.merge(%{relay: -1, hold_ticks: 0, capture_team: -1, capture_ticks: 0})
        |> State.feed("RELAY MOVED // " <> current(s).name)

      rem(s.tick, rotation_ticks()) ==
          (@rotation_seconds - @rotation_warning_seconds) * Rules.tick_rate() ->
        State.feed(s, "RELAY SHIFT // NEXT " <> current(s).next_name)

      true ->
        s
    end
  end

  defp update_control(s) do
    point = current(s)
    occupants = occupants(s, point)
    s = update_capture(s, contenders(occupants))
    holding = s.relay >= 0 and contenders(occupants) == s.relay
    hold = if holding, do: s.hold_ticks + 1, else: 0
    s = %{s | hold_ticks: hold}

    s =
      if hold > 0 and rem(hold, @hold_bonus_ticks) == 0,
        do: s |> State.add_score(s.relay, @hold_bonus_score) |> State.feed("RELAY HOLD // +5"),
        else: s

    if holding and rem(s.tick, Rules.tick_rate()) == 0 do
      Enum.reduce(occupants, State.add_score(s, s.relay, @tick_score), fn p, state ->
        State.update_player(state, p.id, &Player.reward(&1, @tick_xp))
      end)
    else
      s
    end
  end

  defp occupants(s, point) do
    s.players
    |> Map.values()
    |> Enum.filter(
      &(&1.hp > 0 and abs(&1.z - point.z) < 0.65 and
          Physics.distance(&1.x, &1.y, point.x, point.y) < @capture_radius and
          Physics.line_of_sight?(&1, point))
    )
  end

  defp contenders(s, point), do: s |> occupants(point) |> contenders()

  defp contenders(occupants) do
    case Enum.uniq(Enum.map(occupants, & &1.team)) do
      [team] -> team
      [] -> -1
      _ -> :contested
    end
  end

  defp update_capture(s, team) when is_integer(team) and team >= 0 do
    ticks = if team == s.capture_team, do: min(s.capture_ticks + 1, @capture_ticks), else: 1
    s = %{s | capture_team: team, capture_ticks: ticks}

    if ticks == @capture_ticks and s.relay != team do
      %{s | relay: team, hold_ticks: 0} |> State.feed("RELAY SECURED // " <> team_name(team))
    else
      s
    end
  end

  defp update_capture(s, _) do
    ticks = max(0, s.capture_ticks - @capture_decay)
    %{s | capture_team: if(ticks == 0, do: -1, else: s.capture_team), capture_ticks: ticks}
  end

  defp team_name(0), do: "CYAN"
  defp team_name(1), do: "AMBER"
end
