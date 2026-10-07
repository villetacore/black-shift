defmodule BlackShift.Match.Server do
  @moduledoc """
  One isolated process per live match: runs the simulation at the game tick
  rate, broadcasts snapshots and persists the result.

  Crashed matches are not silently recreated: sessions are told the match is
  unavailable. Disconnected players are replaced by bots, and a match without
  any connected client stops without saving a result.
  """
  use GenServer, restart: :temporary
  require Logger
  alias BlackShift.Game
  alias BlackShift.Network.{Protocol, Session}
  alias BlackShift.Persistence.Store

  # Snapshots go out every tick (20 Hz), so remote movement and hit feedback stay smooth.
  @snapshot_every 1
  @persist_retry_ms 1_000
  @practice_bots [
    {"UNIT-01", "ranger"},
    {"UNIT-02", "warden"},
    {"UNIT-03", "ranger"},
    {"UNIT-04", "ranger"},
    {"UNIT-05", "ranger"}
  ]

  @doc "`members` is a list of `{session_pid, player_description}`."
  def start_link({members, practice?}), do: GenServer.start_link(__MODULE__, {members, practice?})

  @impl true
  def init({members, practice?}) do
    id = "#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive, :monotonic])}"
    humans = Enum.map(members, &elem(&1, 1))
    players = if practice?, do: humans ++ practice_bots(id), else: humans
    game = Game.new(id, players)
    sessions = Map.new(members, fn {pid, p} -> {pid, %{id: p.id, ref: Process.monitor(pid)}} end)

    Enum.each(sessions, fn {pid, p} ->
      send(pid, {:attach_match, self()})

      Session.deliver(
        pid,
        Protocol.start(id, p.id, game.players[p.id].team, Game.arena(), Game.tick_rate())
      )

      Session.deliver(pid, Game.snapshot(game))
    end)

    Process.send_after(self(), :tick, tick_ms())
    Logger.info("match #{id} started, practice=#{practice?}")
    {:ok, %{game: game, sessions: sessions, deadline: now() + tick_ms()}}
  end

  defp practice_bots(match_id) do
    @practice_bots
    |> Enum.with_index(1)
    |> Enum.map(fn {{name, class}, i} ->
      %{id: "bot-#{match_id}-#{i}", name: name, class: class, bot: true}
    end)
  end

  @impl true
  def handle_cast({:input, pid, input}, s) do
    case s.sessions[pid] do
      nil -> {:noreply, s}
      %{id: id} -> {:noreply, %{s | game: Game.set_input(s.game, id, input)}}
    end
  end

  @impl true
  def handle_info(:tick, s) do
    game = Game.step(s.game)

    if rem(game.tick, @snapshot_every) == 0 or game.over do
      broadcast(s, Game.snapshot(game))
    end

    s = %{s | game: game}

    if game.over do
      finish(s)
    else
      # Ticks follow monotonic time; a late tick does not queue up catch-up ticks.
      now = now()
      deadline = max(s.deadline + tick_ms(), now + 1)
      Process.send_after(self(), :tick, deadline - now)
      {:noreply, %{s | deadline: deadline}}
    end
  end

  def handle_info(:persist, s), do: finish(s)

  def handle_info({:DOWN, ref, :process, pid, _}, s) do
    case s.sessions[pid] do
      %{ref: ^ref, id: id} ->
        s = %{s | sessions: Map.delete(s.sessions, pid), game: Game.remove(s.game, id)}
        if map_size(s.sessions) == 0, do: {:stop, :normal, s}, else: {:noreply, s}

      _ ->
        {:noreply, s}
    end
  end

  # The result is announced only after it is durably stored; storage errors are retried.
  defp finish(s) do
    case Store.save(Game.snapshot(s.game)) do
      :ok ->
        result = Protocol.result(s.game.id, s.game.winner)
        Enum.each(s.sessions, fn {pid, _} -> send(pid, {:finished, self(), result}) end)
        {:stop, :normal, s}

      error ->
        Logger.error("Result persistence failed for #{s.game.id}: #{inspect(error)}")
        Process.send_after(self(), :persist, @persist_retry_ms)
        {:noreply, s}
    end
  end

  defp broadcast(s, message),
    do: Enum.each(s.sessions, fn {pid, _} -> Session.deliver(pid, message) end)

  defp tick_ms, do: div(1000, Game.tick_rate())
  defp now, do: System.monotonic_time(:millisecond)
end
