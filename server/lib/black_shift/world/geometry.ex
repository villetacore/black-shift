defmodule BlackShift.World.Geometry do
  @moduledoc """
  Compiles authored map objects (convex brushes) into world-space geometry.

  Every brush is a convex polyhedron described by world vertices, outward-facing
  polygon faces, bounding planes `[a, b, c, d]` (a point is inside when
  `a*x + b*y + c*z < d` for every plane) and an axis-aligned bounding box.
  """

  def add(a, b), do: Enum.zip_with(a, b, &(&1 + &2))
  def sub(a, b), do: Enum.zip_with(a, b, &(&1 - &2))
  def scale(a, s), do: Enum.map(a, &(&1 * s))
  def dot(a, b), do: Enum.zip_with(a, b, &(&1 * &2)) |> Enum.sum()
  def cross([a, b, c], [d, e, f]), do: [b * f - c * e, c * d - a * f, a * e - b * d]
  def normalize(a), do: scale(a, 1 / max(1.0e-10, :math.sqrt(dot(a, a))))

  @doc "Adds `vertices`, `faces`, `planes` and `aabb` to an authored map object."
  def compile_brush(object) do
    {local, faces} = shape(object["shape"])
    angle = object["yaw"] * :math.pi() / 180

    vertices =
      Enum.map(local, fn point ->
        [x, y, z] = Enum.zip_with(point, object["size"], &(&1 * &2))

        add(
          [
            x * :math.cos(angle) - y * :math.sin(angle),
            x * :math.sin(angle) + y * :math.cos(angle),
            z
          ],
          object["position"]
        )
      end)

    center = scale(Enum.reduce(vertices, [0, 0, 0], &add/2), 1 / length(vertices))

    {faces, planes} =
      faces
      |> Enum.map(&orient_face(&1, vertices, center))
      |> Enum.unzip()

    bounds =
      for axis <- 0..2 do
        coordinates = Enum.map(vertices, &Enum.at(&1, axis))
        [Enum.min(coordinates), Enum.max(coordinates)]
      end

    Map.merge(object, %{
      "vertices" => vertices,
      "faces" => faces,
      "planes" => planes,
      "aabb" => bounds
    })
  end

  # Faces are wound so that their normal points away from the brush centre.
  defp orient_face(face, vertices, center) do
    [a, b, c | _] = Enum.map(face, &Enum.at(vertices, &1))
    normal = normalize(cross(sub(b, a), sub(c, a)))

    {face, normal} =
      if dot(normal, sub(a, center)) < 0,
        do: {Enum.reverse(face), scale(normal, -1)},
        else: {face, normal}

    {face, normal ++ [dot(normal, a)]}
  end

  # Unit shapes centred on the origin. A ramp rises along local +X.
  defp shape("ramp") do
    {[
       [-0.5, -0.5, -0.5],
       [0.5, -0.5, -0.5],
       [0.5, 0.5, -0.5],
       [-0.5, 0.5, -0.5],
       [0.5, -0.5, 0.5],
       [0.5, 0.5, 0.5]
     ], [[0, 3, 2, 1], [0, 1, 4], [3, 5, 2], [1, 2, 5, 4], [0, 4, 5, 3]]}
  end

  defp shape("cylinder") do
    vertices =
      for z <- [-0.5, 0.5],
          i <- 0..7,
          do: [0.5 * :math.cos(i * :math.pi() / 4), 0.5 * :math.sin(i * :math.pi() / 4), z]

    {vertices,
     [Enum.to_list(0..7), Enum.to_list(8..15)] ++
       Enum.map(0..7, fn i -> [i, rem(i + 1, 8), rem(i + 1, 8) + 8, i + 8] end)}
  end

  defp shape(_box) do
    {for(z <- [-0.5, 0.5], y <- [-0.5, 0.5], x <- [-0.5, 0.5], do: [x, y, z]),
     [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]}
  end
end
