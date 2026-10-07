defmodule BlackShift.Game do
  @moduledoc """
  Pure, deterministic match simulation. Each `BlackShift.Match.Server`
  process owns one state value and advances it with `step/1` at
  `tick_rate/0` Hz; no other process mutates it.

  The rules are split by topic:

    * `BlackShift.Game.Player` — spawning, input, movement, progression
    * `BlackShift.Game.Bot` — bot decisions
    * `BlackShift.Game.Combat` — shooting, hit zones, abilities, damage
    * `BlackShift.Game.Weapons` — weapon numbers, accuracy, recoil
    * `BlackShift.Game.Structures` — cores, towers, drone waves
    * `BlackShift.Game.Objective` — rotating relay and its scoring
    * `BlackShift.Game.Supplies` — health pickups
    * `BlackShift.Game.Physics` — collision, gravity, line of sight
    * `BlackShift.Game.Snapshot` — the client-facing view
  """
  alias BlackShift.Game.{Objective, Player, Rules, Snapshot, State, Structures, Supplies}
  alias BlackShift.World.Scene

  def tick_rate, do: Rules.tick_rate()

  @doc "The compiled map sent to clients."
  def arena, do: Scene.scene()

  @doc """
  Creates a match from player descriptions (`%{id: ..., name: ..., class: ..., bot: ...}`).
  Players alternate between team 0 and team 1 in list order.
  """
  def new(id, descriptions) do
    players =
      descriptions
      |> Enum.with_index()
      |> Enum.map(fn {description, index} -> Player.new(description, index) end)

    %{
      id: id,
      players: Map.new(players, &{&1.id, &1}),
      order: Enum.map(players, & &1.id),
      entities: Structures.initial(),
      tick: 0,
      score: [0, 0],
      relay: -1,
      hold_ticks: 0,
      capture_team: -1,
      capture_ticks: 0,
      winner: -1,
      over: false,
      serial: 0,
      waves: %{},
      supplies: Supplies.initial(),
      beams: [],
      history: [],
      feed: ["RELAY ONLINE // SECURE THE CENTRE"]
    }
  end

  @doc "Stores validated client input for a human player; invalid input is ignored."
  def set_input(s, id, input) when is_map(input) do
    with %{bot: false} = p <- s.players[id],
         {:ok, p} <- Player.accept_input(p, input, s.tick) do
      put_in(s, [:players, id], p)
    else
      _ -> s
    end
  end

  def set_input(s, _, _), do: s

  @doc "Hands a disconnected player over to a bot."
  def remove(s, id), do: State.update_player(s, id, &%{&1 | bot: true, name: "BOT / " <> &1.name})

  def step(%{over: true} = s), do: s

  def step(s) do
    s = %{s | tick: s.tick + 1, beams: []}

    s.order
    |> Enum.reduce(s, &Player.step(&2, &1))
    |> Structures.step()
    |> Supplies.step()
    |> Objective.step()
    |> finish_if_decided()
    |> record_history()
  end

  # Recent player positions, for lag-compensated hits and bots' reaction delay.
  defp record_history(s) do
    frame = %{
      tick: s.tick,
      players: Map.new(s.players, fn {id, p} -> {id, Map.take(p, [:x, :y, :z, :crouching])} end)
    }

    %{s | history: Enum.take([frame | s.history], Player.max_rewind_ticks() + 1)}
  end

  def snapshot(s), do: Snapshot.build(s)

  defp finish_if_decided(s) do
    if not s.over and
         (s.tick >= Rules.match_ticks() or Enum.any?(s.score, &(&1 >= Rules.winning_score()))) do
      [a, b] = s.score

      winner =
        cond do
          a > b -> 0
          a < b -> 1
          true -> -1
        end

      %{s | over: true, winner: winner}
    else
      s
    end
  end
end
