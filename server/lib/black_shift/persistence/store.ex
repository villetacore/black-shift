defmodule BlackShift.Persistence.Store do
  @moduledoc """
  Finished match results in a local, disk-backed Mnesia table.

  Live simulations never read the database; only final snapshots are written.
  The Erlang node name must stay stable for a given data directory.
  """
  use GenServer

  @table :match_results

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_) do
    dir = Application.fetch_env!(:blackshift, :db_dir) |> Path.expand()
    File.mkdir_p!(dir)
    Application.put_env(:mnesia, :dir, String.to_charlist(dir))

    case :mnesia.create_schema([node()]) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
      error -> raise "Mnesia schema: #{inspect(error)}"
    end

    :ok = :mnesia.start()

    case :mnesia.create_table(@table,
           attributes: [:id, :finished, :snapshot],
           disc_copies: [node()],
           type: :ordered_set
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table}} -> :ok
      error -> raise "Mnesia table: #{inspect(error)}"
    end

    :ok = :mnesia.wait_for_tables([@table], 10_000)
    {:ok, dir}
  end

  @doc "Durably stores a final snapshot: synchronous transaction followed by a log flush."
  def save(snapshot) do
    record = {@table, snapshot.match, System.system_time(:millisecond), snapshot}

    case :mnesia.sync_transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} -> :mnesia.sync_log()
      error -> error
    end
  end

  @doc "Up to `limit` stored results, starting from the highest match id."
  def recent(limit \\ 20) do
    {:atomic, records} = :mnesia.transaction(fn -> collect(:mnesia.last(@table), limit, []) end)
    records
  end

  defp collect(:"$end_of_table", _, acc), do: Enum.reverse(acc)
  defp collect(_, 0, acc), do: Enum.reverse(acc)

  defp collect(key, remaining, acc) do
    [{@table, id, finished, snapshot}] = :mnesia.read(@table, key)
    result = %{id: id, finished: finished, snapshot: snapshot}
    collect(:mnesia.prev(@table, key), remaining - 1, [result | acc])
  end
end
