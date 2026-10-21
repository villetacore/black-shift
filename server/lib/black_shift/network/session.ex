defmodule BlackShift.Network.Session do
  @moduledoc """
  One process per TCP connection.

  Validates and rate-limits client messages, forwards input to its match and
  writes outgoing messages to the socket. Matches never call `:gen_tcp.send/2`
  themselves; they `deliver/2` to the session, so a slow client cannot block a
  simulation.

  Phases: `:lobby` → `:queued` → `:playing` → back to `:lobby` after a result.
  """
  use GenServer, restart: :temporary
  alias BlackShift.Match.Matchmaker
  alias BlackShift.Network.Protocol

  # A client whose outgoing queue grows beyond this is too slow and is dropped.
  @max_outbox 32
  @max_messages_per_second 120
  # Silent connections, and connections idling in the lobby, are closed after this.
  @idle_timeout_ms 15_000
  @idle_check_ms 1_000

  def start_link(socket), do: GenServer.start_link(__MODULE__, socket)

  @doc "Queues a message for the client without ever blocking the caller."
  def deliver(pid, message) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, n} when n < @max_outbox -> send(pid, {:wire, message})
      {:message_queue_len, _} -> Process.exit(pid, :shutdown)
      nil -> :ok
    end
  end

  @impl true
  def init(socket) do
    now = now()

    {:ok,
     %{
       socket: socket,
       id: "p#{System.unique_integer([:positive, :monotonic])}",
       phase: :lobby,
       room: nil,
       match: nil,
       monitor: nil,
       last_seen: now,
       lobby_at: now,
       window: now,
       count: 0
     }}
  end

  # Sent by the listener once socket ownership has been transferred to this process.
  @impl true
  def handle_info(:ready, s) do
    :ok = :inet.setopts(s.socket, active: :once)
    Process.send_after(self(), :idle, @idle_check_ms)
    wire(s, Protocol.hello(s.id))
  end

  def handle_info({:tcp, socket, bytes}, %{socket: socket} = s) do
    s = count_message(s)

    with true <-
           s.count <= @max_messages_per_second and byte_size(bytes) <= Protocol.max_line_bytes(),
         {:ok, message} <- Protocol.decode(bytes),
         {:noreply, s} <- dispatch(message, s),
         :ok <- :inet.setopts(socket, active: :once) do
      {:noreply, s}
    else
      {:stop, reason, state} -> {:stop, reason, state}
      _ -> {:stop, :normal, s}
    end
  end

  def handle_info({:wire, payload}, s), do: wire(s, payload)

  def handle_info({:attach_match, pid}, s) do
    {:noreply, %{s | phase: :playing, match: pid, monitor: Process.monitor(pid)}}
  end

  def handle_info({:finished, pid, payload}, %{match: pid} = s) do
    Process.demonitor(s.monitor, [:flush])
    phase = if s.room, do: :room, else: :lobby
    wire(%{s | phase: phase, match: nil, monitor: nil, lobby_at: now()}, payload)
  end

  def handle_info({:room_state, code, payload}, s) do
    wire(%{s | room: code, phase: if(s.match, do: :playing, else: :room)}, payload)
  end

  def handle_info({:room_return, code, payload}, s) do
    if s.monitor, do: Process.demonitor(s.monitor, [:flush])
    wire(%{s | room: code, phase: :room, match: nil, monitor: nil}, payload)
  end

  def handle_info({:DOWN, ref, :process, _, _reason}, %{monitor: ref, room: room} = s)
      when not is_nil(room) do
    {:noreply, %{s | phase: :room, match: nil, monitor: nil}}
  end

  def handle_info({:DOWN, ref, :process, _, reason}, %{monitor: ref} = s) do
    :gen_tcp.send(
      s.socket,
      Protocol.encode(Protocol.error("Match unavailable: #{inspect(reason)}"))
    )

    {:stop, :normal, s}
  end

  def handle_info(:idle, s) do
    now = now()

    if now - s.last_seen > @idle_timeout_ms or
         (s.phase == :lobby and now - s.lobby_at > @idle_timeout_ms) do
      {:stop, :normal, s}
    else
      Process.send_after(self(), :idle, @idle_check_ms)
      {:noreply, s}
    end
  end

  def handle_info({:tcp_closed, _}, s), do: {:stop, :normal, s}
  def handle_info({:tcp_error, _, _}, s), do: {:stop, :normal, s}

  @impl true
  def terminate(_, s), do: :gen_tcp.close(s.socket)

  # Fixed one-second window rate limit.
  defp count_message(s) do
    now = now()

    if now - s.window >= 1_000,
      do: %{s | window: now, count: 1, last_seen: now},
      else: %{s | count: s.count + 1, last_seen: now}
  end

  defp dispatch(%{"type" => "ping"}, s), do: wire(s, Protocol.pong())

  defp dispatch(%{"type" => "join"}, %{phase: phase} = s) when phase != :lobby,
    do: wire(s, Protocol.error("Already queued or in a match"))

  defp dispatch(%{"type" => "join"} = message, s) do
    with {:ok, mode, player} <- Protocol.parse_join(message),
         :ok <- Matchmaker.join(self(), Map.put(player, :id, s.id), mode) do
      {:noreply, %{s | phase: :queued}}
    else
      {:error, reason} -> wire(s, Protocol.error(reason))
    end
  end

  defp dispatch(%{"type" => type} = message, %{phase: :lobby} = s)
       when type in ["room_create", "room_join"] do
    with {:ok, _, player} <- Protocol.parse_join(Map.put(message, "mode", "practice")),
         {:ok, code} <- enter_room(type, Map.put(player, :id, s.id), message) do
      {:noreply, %{s | phase: :room, room: code}}
    else
      {:error, reason} -> wire(s, %{type: "room_error", message: reason})
    end
  end

  defp dispatch(%{"type" => "room_action"} = message, %{phase: :room} = s) do
    case BlackShift.Match.Rooms.action(self(), message) do
      :ok -> {:noreply, s}
      {:error, reason} -> wire(s, %{type: "room_error", message: reason})
    end
  end

  defp dispatch(%{"type" => type}, s) when type in ["room_create", "room_join", "room_action"],
    do: wire(s, %{type: "room_error", message: "Room action unavailable in this phase"})

  defp dispatch(%{"type" => "input"} = message, %{phase: :playing} = s) do
    GenServer.cast(s.match, {:input, self(), message})
    {:noreply, s}
  end

  defp dispatch(_, s), do: {:noreply, s}

  defp enter_room("room_create", player, _), do: BlackShift.Match.Rooms.create(self(), player)

  defp enter_room("room_join", player, message) do
    code = message["code"]

    if is_binary(code) and byte_size(code) == 6 and String.match?(code, ~r/^[A-Z2-7]{6}$/),
      do: BlackShift.Match.Rooms.join(self(), player, code),
      else: {:error, "Enter a six-character room code"}
  end

  defp wire(s, payload) do
    case :gen_tcp.send(s.socket, Protocol.encode(payload)) do
      :ok -> {:noreply, s}
      {:error, _} -> {:stop, :normal, s}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
