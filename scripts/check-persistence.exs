# Run in two separate BEAM instances with the same isolated BS_DB_DIR.
{:ok, _} = Application.ensure_all_started(:blackshift)

case System.fetch_env!("BS_PROBE_PHASE") do
  "write" ->
    state = BlackShift.Game.new("durability-probe", [%{id: "qa"}])
    snapshot = BlackShift.Game.snapshot(%{state | over: true, winner: 0})
    :ok = BlackShift.Persistence.Store.save(snapshot)
    IO.puts("Persistence probe written")

  "read" ->
    true = Enum.any?(BlackShift.Persistence.Store.recent(), &(&1.id == "durability-probe" and &1.snapshot.winner == 0))
    IO.puts("Persistence verified across BEAM restart")
end
