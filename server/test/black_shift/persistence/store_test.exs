defmodule BlackShift.Persistence.StoreTest do
  use ExUnit.Case, async: false
  alias BlackShift.Game
  alias BlackShift.Persistence.Store

  test "restarting the application preserves Mnesia results" do
    id = "restart-#{System.unique_integer([:positive])}"
    result = Game.new(id, [%{id: "qa"}]) |> Map.merge(%{over: true, winner: 1}) |> Game.snapshot()
    assert :ok = Store.save(result)
    assert :ok = Application.stop(:blackshift)
    assert {:ok, _} = Application.ensure_all_started(:blackshift)
    assert Enum.any?(Store.recent(), &(&1.id == id and &1.snapshot.winner == 1))
  end

  test "completed snapshots are stored on disk transactionally" do
    id = "result-#{System.unique_integer([:positive])}"

    result =
      Game.new(id, [%{id: "test"}]) |> Map.merge(%{over: true, winner: 0}) |> Game.snapshot()

    assert :ok = Store.save(result)
    assert :mnesia.table_info(:match_results, :storage_type) == :disc_copies
    assert Enum.any?(Store.recent(), &(&1.id == id and &1.snapshot == result))
    assert :mnesia.sync_log() == :ok
  end
end
