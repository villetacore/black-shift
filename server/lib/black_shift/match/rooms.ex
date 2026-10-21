defmodule BlackShift.Match.Rooms do
  @moduledoc "Private six-slot rooms. Room membership survives a match; empty slots become bots."
  use GenServer
  alias BlackShift.Match.Server

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def create(pid, player), do: GenServer.call(__MODULE__, {:create, pid, player})
  def join(pid, player, code), do: GenServer.call(__MODULE__, {:join, pid, player, code})
  def action(pid, command), do: GenServer.call(__MODULE__, {:action, pid, command})
  def complete(code, match), do: GenServer.call(__MODULE__, {:complete, code, match})

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:create, pid, player}, _, rooms) do
    cond do
      member_room(rooms, pid) != nil ->
        {:reply, {:error, "Already in a room"}, rooms}

      map_size(rooms) >= 64 ->
        {:reply, {:error, "Room capacity reached"}, rooms}

      true ->
        code = new_code(rooms)

        room = %{
          code: code,
          host: pid,
          members: [member(pid, player, 0)],
          match: nil,
          ref: nil,
          round: 1
        }

        publish(room)
        {:reply, {:ok, code}, Map.put(rooms, code, room)}
    end
  end

  def handle_call({:join, pid, player, code}, _, rooms) do
    case rooms[code] do
      nil ->
        {:reply, {:error, "Room not found"}, rooms}

      %{match: match} when not is_nil(match) ->
        {:reply, {:error, "Match already running"}, rooms}

      %{members: members} when length(members) >= 6 ->
        {:reply, {:error, "Room is full"}, rooms}

      room ->
        if member_room(rooms, pid) do
          {:reply, {:error, "Already in a room"}, rooms}
        else
          cyan = Enum.count(room.members, &(&1.team == 0))
          amber = length(room.members) - cyan
          team = if cyan <= amber, do: 0, else: 1
          room = %{room | members: room.members ++ [member(pid, player, team)]}
          publish(room)
          {:reply, {:ok, code}, Map.put(rooms, code, room)}
        end
    end
  end

  def handle_call({:action, pid, command}, _, rooms) do
    case member_room(rooms, pid) do
      nil ->
        {:reply, {:error, "Not in a room"}, rooms}

      {_code, %{match: match}} when not is_nil(match) ->
        {:reply, {:error, "Match already running"}, rooms}

      {code, room} ->
        case change(room, pid, command) do
          {:ok, updated} ->
            publish(updated)
            {:reply, :ok, Map.put(rooms, code, updated)}

          {:error, reason} ->
            {:reply, {:error, reason}, rooms}
        end
    end
  end

  def handle_call({:complete, code, match}, _, rooms) do
    case rooms[code] do
      %{match: ^match} = room ->
        Process.demonitor(room.ref, [:flush])

        room = %{
          room
          | match: nil,
            ref: nil,
            round: room.round + 1,
            members: Enum.map(room.members, &%{&1 | team: 1 - &1.team, ready: false})
        }

        # The match sends this payload together with its result, preserving wire order.
        {:reply, public(room), Map.put(rooms, code, room)}

      _ ->
        {:reply, nil, rooms}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, rooms) do
    rooms =
      Enum.reduce(rooms, %{}, fn {code, room}, acc ->
        cond do
          room.ref == ref ->
            room = %{
              room
              | match: nil,
                ref: nil,
                members: Enum.map(room.members, &%{&1 | ready: false})
            }

            Enum.each(room.members, fn m -> send(m.pid, {:room_return, code, public(room)}) end)
            Map.put(acc, code, room)

          Enum.any?(room.members, &(&1.ref == ref)) ->
            members = Enum.reject(room.members, &(&1.pid == pid))

            if members == [] do
              if room.ref, do: Process.demonitor(room.ref, [:flush])
              acc
            else
              host = if room.host == pid, do: hd(members).pid, else: room.host
              room = %{room | members: members, host: host}
              publish(room)
              Map.put(acc, code, room)
            end

          true ->
            Map.put(acc, code, room)
        end
      end)

    {:noreply, rooms}
  end

  defp change(room, pid, %{"action" => "ready", "ready" => ready}) when is_boolean(ready),
    do: {:ok, update_member(room, pid, &%{&1 | ready: ready})}

  defp change(room, pid, %{"action" => "team", "team" => team}) when team in [0, 1] do
    if Enum.count(room.members, &(&1.team == team and &1.pid != pid)) >= 3 do
      {:error, "Team is full"}
    else
      {:ok, update_member(room, pid, &%{&1 | team: team, ready: false})}
    end
  end

  defp change(room, pid, %{"action" => "class", "class" => class})
       when class in ["ranger", "warden"],
       do:
         {:ok,
          update_member(room, pid, &%{&1 | player: %{&1.player | class: class}, ready: false})}

  defp change(room, pid, %{"action" => "start"}) do
    cond do
      room.host != pid ->
        {:error, "Only the host can start"}

      not Enum.all?(room.members, & &1.ready) ->
        {:error, "All players must be ready"}

      true ->
        members = Enum.map(room.members, &{&1.pid, &1.player})

        players =
          for index <- 0..5 do
            team = rem(index, 2)

            case Enum.at(Enum.filter(room.members, &(&1.team == team)), div(index, 2)) do
              nil ->
                %{
                  id: "room-bot-#{room.code}-#{room.round}-#{index}",
                  name: "UNIT-0#{index + 1}",
                  class: if(div(index, 2) == 1, do: "warden", else: "ranger"),
                  bot: true
                }

              m ->
                m.player
            end
          end

        case DynamicSupervisor.start_child(
               BlackShift.Match.Supervisor,
               {Server, {members, %{players: players, room: room.code}}}
             ) do
          {:ok, match} -> {:ok, %{room | match: match, ref: Process.monitor(match)}}
          _ -> {:error, "Server at match capacity"}
        end
    end
  end

  defp change(_, _, _), do: {:error, "Invalid room action"}

  defp member(pid, player, team),
    do: %{pid: pid, player: player, team: team, ready: false, ref: Process.monitor(pid)}

  defp member_room(rooms, pid),
    do: Enum.find(rooms, fn {_, r} -> Enum.any?(r.members, &(&1.pid == pid)) end)

  defp update_member(room, pid, fun),
    do: %{
      room
      | members: Enum.map(room.members, fn m -> if m.pid == pid, do: fun.(m), else: m end)
    }

  defp new_code(rooms) do
    code = :crypto.strong_rand_bytes(4) |> Base.encode32(padding: false) |> binary_part(0, 6)
    if Map.has_key?(rooms, code), do: new_code(rooms), else: code
  end

  defp publish(%{match: nil} = room),
    do: Enum.each(room.members, fn m -> send(m.pid, {:room_state, room.code, public(room)}) end)

  defp publish(_), do: :ok

  defp public(room) do
    %{
      type: "room",
      code: room.code,
      round: room.round,
      host: Enum.find(room.members, &(&1.pid == room.host)).player.id,
      players:
        Enum.map(room.members, fn m ->
          %{
            id: m.player.id,
            name: m.player.name,
            class: m.player.class,
            team: m.team,
            ready: m.ready
          }
        end)
    }
  end
end
