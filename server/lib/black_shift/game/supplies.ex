defmodule BlackShift.Game.Supplies do
  @moduledoc "Ground-level health pickups that heal the first wounded player in reach, then recharge."
  alias BlackShift.Game.{Physics, Player, State}
  alias BlackShift.World.Scene

  @heal 45
  @pickup_radius 0.8
  @recharge_ticks 700
  # Players on raised platforms cannot reach a pickup on the floor.
  @max_pickup_height 0.5

  def initial,
    do:
      for(
        p <- Scene.supplies(),
        do: %{x: p["x"], y: p["y"], z: Map.get(p, "z", 0.0), ready_at: 0}
      )

  def step(s) do
    s.supplies
    |> Enum.with_index()
    |> Enum.reduce(s, fn {supply, index}, s ->
      player =
        if supply.ready_at <= s.tick, do: Enum.find(s.order, &can_pick_up?(s.players[&1], supply))

      if player do
        s = State.update_player(s, player, &Player.heal(&1, @heal))

        %{
          s
          | supplies:
              List.replace_at(s.supplies, index, %{supply | ready_at: s.tick + @recharge_ticks})
        }
      else
        s
      end
    end)
  end

  defp can_pick_up?(p, supply) do
    p.hp > 0 and p.hp < Player.max_hp(p) and Physics.distance(p, supply) < @pickup_radius and
      abs(p.z - supply.z) < @max_pickup_height and Physics.line_of_sight?(p, supply)
  end
end
