defmodule BlackShift.Network.Listener do
  @moduledoc """
  Owns the listening socket. A linked acceptor loop starts one
  `BlackShift.Network.Session` per connection under the session supervisor.
  """
  use GenServer
  require Logger
  alias BlackShift.Network.{Protocol, Session}

  @sessions BlackShift.Network.SessionSupervisor

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The bound `{ip, port}`; useful when the configured port is 0."
  def address, do: GenServer.call(__MODULE__, :address)

  @impl true
  def init(_) do
    ip = Application.fetch_env!(:blackshift, :bind)
    port = Application.fetch_env!(:blackshift, :port)

    {:ok, socket} =
      :gen_tcp.listen(port, [
        :binary,
        ip: ip,
        packet: :line,
        packet_size: Protocol.max_line_bytes(),
        active: false,
        reuseaddr: true,
        nodelay: true,
        backlog: 128,
        send_timeout: 3_000,
        send_timeout_close: true
      ])

    {:ok, {ip, port}} = :inet.sockname(socket)
    spawn_link(fn -> accept(socket) end)
    Logger.info("BLACK SHIFT // #{:inet.ntoa(ip)}:#{port} // Elixir/OTP 20 Hz // Mnesia")
    {:ok, %{socket: socket, address: {ip, port}}}
  end

  @impl true
  def handle_call(:address, _, state), do: {:reply, state.address, state}

  defp accept(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        hand_over(socket)
        accept(listener)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        exit({:accept_failed, reason})
    end
  end

  defp hand_over(socket) do
    with {:ok, pid} <- DynamicSupervisor.start_child(@sessions, {Session, socket}) do
      case :gen_tcp.controlling_process(socket, pid) do
        :ok ->
          send(pid, :ready)

        _ ->
          :gen_tcp.close(socket)
          Process.exit(pid, :shutdown)
      end
    else
      _ -> :gen_tcp.close(socket)
    end
  end
end
