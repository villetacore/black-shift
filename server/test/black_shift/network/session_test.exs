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

  defp room_enter(socket, code \\ nil) do
    write(socket, %{
      type: if(code, do: "room_join", else: "room_create"),
      version: 1,
      name: "Room QA",
      class: "ranger",
      code: code
    })
  end

  defp room_action(socket, action, extras \\ %{}),
    do: write(socket, Map.merge(%{type: "room_action", action: action}, extras))

  defp room_until(socket, predicate, attempts \\ 20)
  defp room_until(_, _, 0), do: flunk("Room state did not converge")

  defp room_until(socket, predicate, attempts) do
    room = read(socket, "room")
    if predicate.(room), do: room, else: room_until(socket, predicate, attempts - 1)
  end

  test "private room starts with bots and returns all humans for a side-swapped rematch" do
    a = connect()
    room_enter(a)
    first = read(a, "room")
    b = connect()
    room_enter(b, first["code"])
    room = read(b, "room")
    assert length(room["players"]) == 2
    room_action(b, "start")
    assert read(b, "room_error")["message"] =~ "host"
    room_action(a, "start")
    assert read(a, "room_error")["message"] =~ "ready"
    room_action(a, "ready", %{ready: true})
    room_action(b, "ready", %{ready: true})
    room_until(a, &Enum.all?(&1["players"], fn p -> p["ready"] end))
    room_action(a, "start")
    ma = read(a, "start")
    mb = read(b, "start")
    assert ma["match"] == mb["match"]
    players = read(a, "snapshot")["players"]
    assert length(players) == 6
    assert Enum.count(players, & &1["bot"]) == 4
    assert Enum.count(players, &(&1["team"] == 0)) == 3
    assert Enum.count(players, &(&1["team"] == 1)) == 3
    pid = match_pid(ma["match"])
    :sys.replace_state(pid, fn s -> put_in(s, [:game, :score], [200, 0]) end)
    result = read(a, "result")
    assert result["room"]["round"] == 2
    p = Enum.find(result["room"]["players"], &(&1["id"] == ma["id"]))
    assert p["team"] == 1 - ma["team"]
    refute p["ready"]
    read(b, "result")
    room_action(a, "ready", %{ready: true})
    room_action(b, "ready", %{ready: true})
    room_until(a, &Enum.all?(&1["players"], fn p -> p["ready"] end))
    room_action(a, "start")
    next = read(a, "start")
    assert next["match"] != ma["match"]
    assert next["team"] != ma["team"]
  end

  test "room enforces six humans, team capacity and membership phase" do
    host = connect()
    room_enter(host)
    code = read(host, "room")["code"]

    members =
      for _ <- 1..5 do
        socket = connect()
        room_enter(socket, code)
        read(socket, "room")
        socket
      end

    extra = connect()
    room_enter(extra, code)
    assert read(extra, "room_error")["message"] =~ "full"
    room_action(hd(members), "team", %{team: 0})
    assert read(hd(members), "room_error")["message"] =~ "full"
    Enum.each([host | members], &room_action(&1, "ready", %{ready: true}))

    room_until(
      host,
      &(length(&1["players"]) == 6 and Enum.all?(&1["players"], fn p -> p["ready"] end))
    )

    room_action(host, "start")
    read(host, "start")
    players = read(host, "snapshot")["players"]
    assert length(players) == 6
    refute Enum.any?(players, & &1["bot"])
    room_action(host, "team", %{team: 1})
    assert read(host, "room_error")["message"] =~ "phase"
  end

  test "host disconnect transfers ownership and malformed codes are rejected" do
    a = connect()
    room_enter(a)
    initial = read(a, "room")
    b = connect()
    room_enter(b, initial["code"])
    read(b, "room")
    :gen_tcp.close(a)
    room = room_until(b, &(length(&1["players"]) == 1))
    assert room["host"] == hd(room["players"])["id"]
    assert room["host"] != initial["host"]
    room_action(b, "ready", %{ready: true})
    room_until(b, &hd(&1["players"])["ready"])
    room_action(b, "class", %{class: "warden"})
    room = room_until(b, &(hd(&1["players"])["class"] == "warden"))
    refute hd(room["players"])["ready"]
    c = connect()
    room_enter(c, 12345)
    assert read(c, "room_error")["message"] =~ "six-character"
  end

  @tag capture_log: true
  test "crashed room match returns to lobby without dropping the connection" do
    a = connect()
    room_enter(a)
    read(a, "room")
    room_action(a, "ready", %{ready: true})
    room_until(a, &hd(&1["players"])["ready"])
    room_action(a, "start")
    start = read(a, "start")
    Process.exit(match_pid(start["match"]), :kill)
    room = read(a, "room")
    refute hd(room["players"])["ready"]
    write(a, %{type: "ping"})
    assert read(a, "pong")["type"] == "pong"
  end
end
