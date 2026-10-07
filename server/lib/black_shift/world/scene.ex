defmodule BlackShift.World.Scene do
  @moduledoc """
  The authoritative 3D map: authored convex brushes plus match layout
  (spawns, bases, objectives, supplies). Collision, support, ceilings and
  line-of-sight queries all run against the same compiled brushes.

  The map JSON is embedded at compile time, so a release does not depend on
  the working directory. Rebuild the server after editing it.
  """
  alias BlackShift.World.Geometry

  @external_resource Path.expand("../../../priv/maps/foundry.json", __DIR__)
  @source :json.decode(File.read!(@external_resource))

  # Horizontal clearance kept from the map boundary and from brushes.
  @boundary_margin 0.7
  # The player collision body is a box: radius 0.2, from z + 0.02 to z + 1.82.
  @body_radius 0.2
  @body_height 1.82
  @body_center 0.92
  @body_half_height 0.90

  @doc "Compiled scene, also sent to clients in the `start` message."
  def scene do
    case :persistent_term.get({__MODULE__, :scene}, nil) do
      nil ->
        compiled =
          Map.update!(@source, "objects", &Enum.map(&1, fn o -> Geometry.compile_brush(o) end))

        :persistent_term.put({__MODULE__, :scene}, compiled)
        compiled

      compiled ->
        compiled
    end
  end

  def objects, do: scene()["objects"]
  def bounds, do: scene()["bounds"]
  def spawn(team), do: Enum.at(scene()["spawns"], team)
  def core(team), do: Enum.at(scene()["cores"], team)
  def tower(team), do: Enum.at(scene()["towers"], team)
  def objectives, do: scene()["objectives"]
  def supplies, do: scene()["supplies"]
  def floor_z, do: Map.get(scene(), "floor_z", 0.0)

  @doc "Team anchors accept legacy [x,y] or explicit [x,y,z]."
  def anchor(kind, team) do
    case Enum.at(scene()[kind], team) do
      [x, y] -> %{x: x, y: y, z: floor_z()}
      [x, y, z] -> %{x: x, y: y, z: z}
    end
  end

  @doc "All standable layers at a horizontal point, including stacked floors."
  def surfaces(x, y) do
    tops = for o <- candidates(x, y, 0), {lo, hi} <- [interval(o, x, y)], hi >= lo, do: hi

    [floor_z() | tops]
    |> Enum.map(&standing_height(x, y, &1 + 0.01))
    |> Enum.uniq_by(&round(&1 * 1000))
    |> Enum.filter(&clear?(x, y, &1))
    |> Enum.sort()
  end

  @doc "Support of the whole footprint, matching walking physics on slopes."
  def standing_height(x, y, limit) do
    for(dx <- [-0.19, 0.19], dy <- [-0.19, 0.19], do: support(x + dx, y + dy, limit + 0.2))
    |> Enum.max()
  end

  @doc "True when the point lies strictly inside a colliding brush."
  def solid?(x, y, z), do: Enum.any?(candidates(x, y, 0), &contains?(&1, [x, y, z]))

  def body_height, do: @body_height

  @doc """
  True when a player body standing with its feet at `z` fits at `(x, y)`.
  `height` is the body's top above the feet (lower while crouching).
  """
  def clear?(x, y, z \\ 0.0, height \\ @body_height) do
    [width, depth, _] = bounds()
    {center, half} = body_extent(height)

    x >= @boundary_margin and y >= @boundary_margin and x <= width - @boundary_margin and
      y <= depth - @boundary_margin and
      Enum.all?(candidates(x, y, @body_radius), fn o ->
        [_, _, [bottom, top]] = o["aabb"]

        z + 0.02 >= top or z + height <= bottom or
          Enum.any?(o["planes"], fn [a, b, c, d] ->
            a * x + b * y + c * (z + center) >=
              d + abs(a) * @body_radius + abs(b) * @body_radius + abs(c) * half - 0.00001
          end)
      end)
  end

  # The standing body keeps its authored constants; other heights share its 2 cm foot gap.
  defp body_extent(@body_height), do: {@body_center, @body_half_height}
  defp body_extent(height), do: {0.02 + (height - 0.02) / 2, (height - 0.02) / 2}

  @doc "Highest walkable surface at `(x, y)` that is not above `limit`."
  def support(x, y, limit) do
    candidates(x, y, 0)
    |> Enum.reduce(floor_z(), fn o, top ->
      case interval(o, x, y) do
        {lo, hi} when hi >= lo and hi <= limit + 0.001 -> max(top, hi)
        _ -> top
      end
    end)
  end

  @doc "Lowest brush underside at `(x, y)` that is not below `head`."
  def ceiling(x, y, head) do
    candidates(x, y, 0)
    |> Enum.reduce(Enum.at(bounds(), 2) * 1.0, fn o, bottom ->
      case interval(o, x, y) do
        {lo, hi} when hi >= lo and lo >= head - 0.001 -> min(bottom, lo)
        _ -> bottom
      end
    end)
  end

  @doc "Distance along a unit `direction` to the first colliding brush, capped at `limit`."
  def raycast(origin, direction, limit) do
    objects()
    |> Enum.filter(& &1["collision"])
    |> Enum.reduce(limit, fn o, best ->
      case clip_ray(o["planes"], origin, direction, best) do
        {near, far} when far >= near and near < best -> near
        _ -> best
      end
    end)
  end

  defp candidates(x, y, r) do
    grid = spatial_index()

    for(
      gx <- floor((x - r) / 4)..floor((x + r) / 4),
      gy <- floor((y - r) / 4)..floor((y + r) / 4),
      o <- Map.get(grid, {gx, gy}, []),
      do: o
    )
    |> Enum.uniq_by(& &1["id"])
    |> Enum.filter(fn o ->
      [[lx, hx], [ly, hy], _] = o["aabb"]
      o["collision"] and x + r >= lx and x - r <= hx and y + r >= ly and y - r <= hy
    end)
  end

  defp spatial_index do
    case :persistent_term.get({__MODULE__, :spatial}, nil) do
      nil ->
        grid =
          Enum.reduce(objects(), %{}, fn o, grid ->
            if o["collision"] do
              [[lx, hx], [ly, hy], _] = o["aabb"]

              Enum.reduce(
                for(
                  x <- floor(lx / 4)..floor(hx / 4),
                  y <- floor(ly / 4)..floor(hy / 4),
                  do: {x, y}
                ),
                grid,
                fn key, acc -> Map.update(acc, key, [o], &[o | &1]) end
              )
            else
              grid
            end
          end)

        :persistent_term.put({__MODULE__, :spatial}, grid)
        grid

      grid ->
        grid
    end
  end

  defp contains?(o, [x, y, z]) do
    Enum.all?(o["planes"], fn [a, b, c, d] -> a * x + b * y + c * z < d - 0.00001 end)
  end

  # Vertical extent of a brush along the line through `(x, y)`, or nil when the line misses it.
  defp interval(o, x, y) do
    Enum.reduce_while(o["planes"], {-1000.0, 1000.0}, fn [a, b, c, d], {lo, hi} ->
      remaining = d - a * x - b * y

      cond do
        abs(c) < 1.0e-8 and remaining < -0.00001 -> {:halt, nil}
        abs(c) < 1.0e-8 -> {:cont, {lo, hi}}
        c > 0 -> {:cont, {lo, min(hi, remaining / c)}}
        true -> {:cont, {max(lo, remaining / c), hi}}
      end
    end)
  end

  defp clip_ray(planes, origin, direction, far) do
    Enum.reduce_while(planes, {0.0, far}, fn [a, b, c, d], {near, far} ->
      normal = [a, b, c]
      den = Geometry.dot(normal, direction)
      remaining = d - Geometry.dot(normal, origin)

      cond do
        abs(den) < 1.0e-8 and remaining < 0 ->
          {:halt, nil}

        abs(den) < 1.0e-8 ->
          {:cont, {near, far}}

        den < 0 ->
          value = max(near, remaining / den)
          if value > far, do: {:halt, nil}, else: {:cont, {value, far}}

        true ->
          value = min(far, remaining / den)
          if near > value, do: {:halt, nil}, else: {:cont, {near, value}}
      end
    end)
  end
end
