defmodule BlackShift.Match.Matchmaker do
  @moduledoc """
  FIFO matchmaking. Practice starts a match immediately; online pairs the
  first two waiting sessions. Waiting sessions are monitored, so a client that
  disconnects leaves the queue.
  """
  use GenServer
  alias BlackShift.Match.Server
  alias BlackShift.Network.{Protocol, Session}

  @matches BlackShift.Match.Supervisor
  @players_per_online_match 2

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def join(pid, player, mode), do: GenServer.call(__MODULE__, {:join, pid, player, mode})

  @impl true
  def init(_), do: {:ok, []}

  @impl true
  def handle_call({:join, pid, player, mode}, _, queue) do
    if DynamicSupervisor.count_children(@matches).active >=
         Application.fetch_env!(:blackshift, :max_matches) do
      {:reply, {:error, "Server at capacity"}, queue}
    else
      join(mode, pid, player, queue)
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, queue),
    do: {:noreply, Enum.reject(queue, fn {_, _, monitor} -> monitor == ref end)}

  defp join("practice", pid, player, queue),
    do: {:reply, start_match([{pid, player}], true), queue}

  defp join("online", pid, player, []), do: {:reply, :ok, enqueue(pid, player)}

  defp join("online", pid, player, [{other, other_player, ref}]) do
    Process.demonitor(ref, [:flush])

    if Process.alive?(other) do
      result = start_match([{other, other_player}, {pid, player}], false)

      if result != :ok,
        do: Session.deliver(other, Protocol.error("Match failed to start"))

      {:reply, result, []}
    else
      {:reply, :ok, enqueue(pid, player)}
    end
  end

  defp enqueue(pid, player) do
    Session.deliver(pid, Protocol.queue(1, @players_per_online_match))
    [{pid, player, Process.monitor(pid)}]
  end

  defp start_match(members, practice?) do
    case DynamicSupervisor.start_child(@matches, {Server, {members, practice?}}) do
      {:ok, _} -> :ok
      _ -> {:error, "Match failed to start"}
    end
  end
end
