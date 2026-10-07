defmodule BlackShift.Game.Liquid do
  @moduledoc "Server-side liquid volumes: immersion, drag, buoyancy and currents at 20 Hz."
  alias BlackShift.World.Scene

  def at(x, y, z, height \\ 1.84) do
    Enum.find(Map.get(Scene.scene(), "liquids", []), fn v ->
      [x0, y0, x1, y1] = v["rect"]

      x >= x0 and x <= x1 and y >= y0 and y <= y1 and
        z < v["surface"] and z + height > v["bottom"]
    end)
  end

  def immersion(p) do
    case at(p.x, p.y, p.z) do
      nil -> 0.0
      v -> max(0.0, min(1.0, (v["surface"] - max(p.z, v["bottom"])) / 1.84))
    end
  end

  def velocity(p, jump, dry_velocity) do
    wet = immersion(p)

    if wet > 0.35 do
      # Equilibrium near chest depth. Drag limits both rising and falling speeds.
      input = Map.get(p, :input, %{})
      swim = if jump or Map.get(input, :swim, false), do: 2.8, else: 0.0
      dive = Map.get(input, :forward, 0.0) * :math.sin(Map.get(input, :pitch, 0.0)) * 1.8
      {max(-4.0, min(3.5, p.vz * 0.78 + (wet - 0.60) * 1.5 + swim + dive)), 0.0}
    else
      {dry_velocity, 1.05}
    end
  end

  def drift(p) do
    case at(p.x, p.y, p.z) do
      nil ->
        {0.0, 0.0}

      v ->
        [x, y] = Map.get(v, "current", [0.0, 0.0])
        wet = immersion(p)
        {x * wet / 20, y * wet / 20}
    end
  end
end
