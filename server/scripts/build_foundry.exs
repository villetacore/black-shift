# Reproducible authored expansion; the classic map stays available for comparison.
defmodule FoundryBuilder do
  def brush(id, shape, position, size, material, yaw \\ 0, model \\ nil) do
    %{
      "id" => id,
      "shape" => shape,
      "position" => position,
      "size" => size,
      "material" => material,
      "yaw" => yaw,
      "uv_scale" => 0.5,
      "collision" => true
    }
    |> then(fn o -> if model, do: Map.put(o, "model", model), else: o end)
  end

  def build do
    root = Path.expand("../priv/maps", __DIR__)
    map = File.read!(Path.join(root, "foundry-classic.json")) |> :json.decode()
    objects = Enum.map(map["objects"], fn object ->
      if object["id"] == "loading-cover" do
        Map.merge(object, %{"position" => [57, 34, 0.65], "size" => [2, 1.2, 1.3], "model" => "crate"})
      else
        object
      end
    end)

    new = [
      brush("yard-gallery", "box", [37, 22, 2.85], [14, 4, 0.3], 12),
      brush("gallery-west-ramp", "ramp", [27, 22, 1.5], [6, 2.5, 3], 3),
      brush("gallery-east-ramp", "ramp", [47, 22, 1.5], [6, 2.5, 3], 3, 180),
      brush("gallery-north-rail", "box", [37, 20, 3.5], [12, 0.15, 1], 2),
      brush("gallery-south-rail", "box", [37, 24, 3.5], [12, 0.15, 1], 2),
      brush("gallery-pillar-west", "box", [31, 20.4, 1.35], [0.5, 0.5, 2.7], 1),
      brush("gallery-pillar-east", "box", [43, 23.6, 1.35], [0.5, 0.5, 2.7], 1),
      brush("pump-raised-floor", "box", [39, 6.5, 0.6], [6, 4, 1.2], 9),
      brush("pump-west-ramp", "ramp", [34, 6.5, 0.6], [4, 3, 1.2], 0),
      brush("pump-east-ramp", "ramp", [44, 6.5, 0.6], [4, 3, 1.2], 0, 180),
      brush("yard-dogleg", "box", [38, 16.5, 1.5], [5.5, 0.5, 3], 1, 25),
      brush("yard-low-block", "box", [39, 27.5, 0.45], [3, 1, 0.9], 1, -20),
      brush("loading-upper-floor", "box", [55, 38, 0.6], [7, 5, 1.2], 9),
      brush("loading-ramp", "ramp", [49.5, 38, 0.6], [4, 3, 1.2], 3),
      brush("loading-upper-cover", "box", [57, 39.5, 1.85], [2, 0.7, 1.3], 3, 0, "crate"),
      brush("loading-stair-1", "box", [53, 33.6, 0.15], [3, 0.8, 0.3], 1),
      brush("loading-stair-2", "box", [53, 34.4, 0.3], [3, 0.8, 0.6], 1),
      brush("loading-stair-3", "box", [53, 35.2, 0.45], [3, 0.8, 0.9], 1),
      brush("generator-angle-cover", "box", [52.5, 25, 0.7], [2, 0.8, 1.4], 3, -30, "crate"),
      brush("west-upper-vent", "box", [26, 9.5, 2.8], [1, 0.9, 1], 12, 0, "vent"),
      brush("yard-upper-vent", "box", [38, 23, 3.5], [1.6, 1.1, 1], 12, 0, "vent"),
      brush("pump-electrical", "box", [46, 9.8, 1], [1, 0.65, 2], 5, 0, "cabinet"),
      brush("service-electrical", "box", [23, 42, 1], [1.2, 0.6, 2], 5, 0, "cabinet"),
      brush("yard-barrel-a", "cylinder", [35, 18, 0.6], [0.9, 0.9, 1.2], 14, 0, "barrel"),
      brush("yard-barrel-b", "cylinder", [35.9, 18.4, 0.6], [0.9, 0.9, 1.2], 14, 0, "barrel"),
      brush("loading-barrel", "cylinder", [54, 39.5, 1.8], [0.9, 0.9, 1.2], 14, 0, "barrel"),
      brush("service-barrel", "cylinder", [38, 41.5, 0.6], [0.9, 0.9, 1.2], 14, 0, "barrel")
    ]

    objectives =
      Enum.map(map["objectives"], fn point ->
        case point["name"] do
          "PUMP HOUSE" -> Map.put(point, "z", 1.2)
          "WORKSHOP RELAY" -> Map.merge(point, %{"x" => 25.5, "y" => 11.5, "z" => 2.3})
          _ -> Map.put(point, "z", 0.0)
        end
      end)

    supplies =
      Enum.map(map["supplies"], fn point ->
        point = if point["x"] == 43.5, do: Map.put(point, "y", 9.5), else: point
        Map.put(point, "z", if(point["x"] == 55.5, do: 1.2, else: 0.0))
      end)

    result =
      Map.merge(map, %{
        "name" => "Foundry Heights",
        "objects" => objects ++ new,
        "objectives" => objectives,
        "supplies" => supplies
      })

    expansion = File.read!(Path.join(root, "industrial-expansion.json")) |> :json.decode()
    result = result |> Map.update!("objects", &(&1 ++ expansion["objects"])) |> Map.put("liquids", expansion["liquids"])
    File.write!(Path.join(root, "foundry.json"), :json.encode(result))
    IO.puts("Foundry Heights: #{length(result["objects"])} brushes, layered relays and props")
  end
end

FoundryBuilder.build()

