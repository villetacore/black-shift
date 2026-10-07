defmodule BlackShift.Game.Snapshot do
  @moduledoc """
  The public view of a match sent to clients (`snapshot` message) and stored
  as the final result. Internal fields such as inputs, AI state and timers in
  ticks are never exposed.
  """
  alias BlackShift.Game.{Objective, Rules, State, Structures, Weapons}

  @player_fields ~w(id name class team x y z vx vy angle pitch grounded sprinting crouching immersion fire_at ammo hp kills deaths level xp cooldown respawn bot hits hit_head hit_kill hurt_at hurt_dir)a
  @entity_fields ~w(id kind team x y z hp max_hp)a

  def build(s) do
    %{
      type: "snapshot",
      match: s.id,
      tick: s.tick,
      seconds: max(0, div(Rules.match_ticks() - s.tick, Rules.tick_rate())),
      players: Enum.map(s.order, &player(s, s.players[&1])),
      entities: Enum.map(State.entity_ids(s), &entity(s, s.entities[&1])),
      beams: s.beams,
      score: s.score,
      relay: s.relay,
      capture: Objective.capture(s),
      wave: Structures.wave(s),
      objective: Objective.current(s),
      supplies: Enum.map(s.supplies, &Map.put(&1, :ready, &1.ready_at <= s.tick)),
      winner: s.winner,
      over: s.over,
      feed: s.feed
    }
  end

  # Weapon state is converted to what a HUD needs: seconds, radians and the magazine size.
  defp player(s, p) do
    w = Weapons.spec(p.class)

    p
    |> Map.take([:boost | @player_fields])
    |> Map.merge(%{
      mag: w.mag,
      weapon: w.name,
      reload:
        if(p.reload_until > 0, do: Rules.seconds(max(0, p.reload_until - s.tick)), else: 0.0),
      spread: Float.round(Weapons.cone(p), 4),
      recoil: Float.round(p.recoil, 4),
      recoil_yaw: Float.round(p.recoil_yaw, 4)
    })
  end

  defp entity(s, e) do
    Map.merge(Map.take(e, @entity_fields), %{
      target: e.locked,
      warning: e.locked != nil and s.tick - e.lock_at < Structures.lock_ticks()
    })
  end
end
