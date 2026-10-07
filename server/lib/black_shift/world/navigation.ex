defmodule BlackShift.World.Navigation do
  @moduledoc "Layered navigation graph sampled from collision geometry; ramps connect floors, ceilings separate them."
  alias BlackShift.World.Scene

  @doc "Build once before accepting matches, so the first player does not stall."
  def warmup do
    graph()
    :ok
  end

  # Keep the legacy horizontal API for callers that do not need elevations.
  def path({sx, sy}, {gx, gy}),
    do: path({sx, sy, 0.0}, {gx, gy, 0.0}) |> Enum.map(fn {x, y, _} -> {x, y} end)

  def path({sx, sy, sz}, {gx, gy, gz}) do
    {cells, edges} = graph()
    start = nearest(cells, sx, sy, sz)
    goal = nearest(cells, gx, gy, gz)

    if start && goal,
      do: search(:queue.from_list([start]), %{start => nil}, goal, edges),
      else: []
  end

  @doc """
  Shortens a grid path by string pulling: from each anchor, jump to the
  farthest of the next waypoints that can be walked in a straight line on the
  same floor. Ramps, steps and stairs keep their waypoints. The result follows
  the same floors as the input but cuts the grid's zig-zags.
  """
  def smooth(_start, []), do: []

  def smooth(start, path), do: pull(start, path, [])

  @lookahead 8

  defp pull(_anchor, [], acc), do: Enum.reverse(acc)

  defp pull(anchor, path, acc) do
    reach =
      path
      |> Enum.take(@lookahead)
      |> Enum.with_index()
      |> Enum.reduce_while(0, fn {point, index}, best ->
        if straight?(anchor, point), do: {:cont, index}, else: {:halt, best}
      end)

    {skipped, rest} = Enum.split(path, reach + 1)
    next = List.last(skipped)
    pull(next, rest, [next | acc])
  end

  # A straight walk on one flat floor: the body fits and the floor stays at the same height.
  defp straight?({x, y, z}, {tx, ty, tz}) do
    length = :math.sqrt((tx - x) ** 2 + (ty - y) ** 2)
    samples = max(1, ceil(length / 0.3))

    abs(z - tz) < 0.05 and
      Enum.all?(1..samples, fn i ->
        px = x + (tx - x) * i / samples
        py = y + (ty - y) * i / samples
        Scene.clear?(px, py, tz) and abs(Scene.standing_height(px, py, tz + 0.1) - tz) < 0.05
      end)
  end

  defp nearest(cells, x, y, z),
    do:
      Map.get(cells, {floor(x), floor(y)}, [])
      |> Enum.min_by(fn {_, _, h} -> abs(h / 1000 - z) end, fn -> nil end)

  defp graph do
    case :persistent_term.get({__MODULE__, :graph}, nil) do
      nil ->
        [w, h, _] = Scene.bounds()

        cells =
          for x <- 0..(trunc(w) - 1), y <- 0..(trunc(h) - 1), into: %{} do
            {{x, y}, Enum.map(Scene.surfaces(x + 0.5, y + 0.5), &{x, y, round(&1 * 1000)})}
          end

        edges =
          for {_, nodes} <- cells, node = {x, y, _} <- nodes, into: %{} do
            neighbors =
              for key <- [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}],
                  target <- Map.get(cells, key, []),
                  connected?(node, target),
                  do: target

            {node, neighbors}
          end

        result = {cells, edges}
        :persistent_term.put({__MODULE__, :graph}, result)
        result

      result ->
        result
    end
  end

  # Sample the whole edge: endpoints alone can connect across walls or floors.
  defp connected?({x, y, z}, {tx, ty, tz}) do
    result =
      Enum.reduce_while(1..10, z / 1000, fn i, height ->
        px = x + 0.5 + (tx - x) * i / 10
        py = y + 0.5 + (ty - y) * i / 10
        next = Scene.standing_height(px, py, height + 0.10)

        if next >= height - 0.60 and Scene.clear?(px, py, next),
          do: {:cont, next},
          else: {:halt, :blocked}
      end)

    is_number(result) and abs(result - tz / 1000) < 0.04
  end

  defp search(queue, visited, goal, edges) do
    case :queue.out(queue) do
      {:empty, _} ->
        []

      {{:value, ^goal}, _} ->
        unwind(visited, goal, []) |> Enum.drop(1)

      {{:value, node}, queue} ->
        {queue, visited} =
          Enum.reduce(Map.get(edges, node, []), {queue, visited}, fn next, {q, seen} ->
            if Map.has_key?(seen, next),
              do: {q, seen},
              else: {:queue.in(next, q), Map.put(seen, next, node)}
          end)

        search(queue, visited, goal, edges)
    end
  end

  defp unwind(_, nil, result), do: result

  defp unwind(visited, {x, y, h} = node, result),
    do: unwind(visited, visited[node], [{x + 0.5, y + 0.5, h / 1000} | result])
end
