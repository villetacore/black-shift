defmodule BlackShift.Network.SessionTest do
  use ExUnit.Case, async: false
  alias BlackShift.Network.Listener
  alias BlackShift.Persistence.Store

  defp connect do
    {ip, port} = Listener.address()

    {:ok, socket} =
      :gen_tcp.connect(
        ip,
        port,
        [:binary, packet: :line, packet_size: 1_048_576, buffer: 1_048_576, active: false],
        2_000
      )

    on_exit(fn -> :gen_tcp.close(socket) end)
    assert %{"type" => "hello", "version" => 1} = read(socket, "hello")
    socket
  end

  defp write(socket, value), do: :gen_tcp.send(socket, [:json.encode(value), "\n"])

  defp join(socket, mode),
    do: write(socket, %{type: "join", version: 1, mode: mode, name: "QA", class: "ranger"})

  defp read(socket, type, attempts \\ 100)
  defp read(_, type, 0), do: flunk("Missing message #{type}")

  defp read(socket, type, attempts) do
    assert {:ok, bytes} = :gen_tcp.recv(socket, 0, 3_000)
    message = :json.decode(bytes)
    if message["type"] == type, do: message, else: read(socket, type, attempts - 1)
  end

  defp match_pid(id) do
    DynamicSupervisor.which_children(BlackShift.Match.Supervisor)
    |> Enum.find_value(fn {_, pid, _, _} ->
      if :sys.get_state(pid).game.id == id, do: pid
    end)
  end

  test "two real TCP clients enter the same online match on opposite teams" do
    a = connect()
    join(a, "online")
    assert read(a, "queue")["waiting"] == 1
    b = connect()
    join(b, "online")
    ma = read(a, "start")
    mb = read(b, "start")
    assert ma["match"] == mb["match"]
    assert ma["team"] != mb["team"]
    assert length(read(a, "snapshot")["players"]) == 2
  end

  test "practice bots, successful persistence, and requeue on the same socket" do
    socket = connect()
    join(socket, "practice")
    start = read(socket, "start")
    assert length(read(socket, "snapshot")["players"]) == 6
    pid = match_pid(start["match"])
    :sys.replace_state(pid, fn s -> put_in(s, [:game, :score], [200, 0]) end)
    assert %{"saved" => true, "winner" => 0} = read(socket, "result")
    assert Enum.any?(Store.recent(), &(&1.id == start["match"] and &1.snapshot.over))
    join(socket, "practice")
    assert read(socket, "start")["match"] != start["match"]
  end

  @tag capture_log: true
  test "a crashing match does not crash another match or the listener" do
    a = connect()
    join(a, "practice")
    ma = read(a, "start")
    b = connect()
    join(b, "practice")
    mb = read(b, "start")
    other = match_pid(mb["match"])
    Process.exit(match_pid(ma["match"]), :kill)
    assert read(a, "error")["message"] =~ "Match unavailable"
    assert Process.alive?(other)
    assert read(b, "snapshot")["match"] == mb["match"]
    connect()
  end

  test "malformed input closes only its connection" do
    a = connect()
    :gen_tcp.send(a, "not json\n")
    assert {:error, :closed} = :gen_tcp.recv(a, 0, 2_000)
    b = connect()
    write(b, %{type: "ping"})
    assert read(b, "pong")["type"] == "pong"
  end

  test "duplicate join is rejected without creating a second match" do
    a = connect()
    join(a, "practice")
    read(a, "start")
    join(a, "practice")
    assert read(a, "error")["message"] =~ "Already queued"
  end
end
