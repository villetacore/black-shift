defmodule BlackShift.MixProject do
  use Mix.Project

  def project do
    [
      app: :blackshift,
      version: "0.3.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: [],
      releases: [blackshift: [include_executables_for: [:windows, :unix]]]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      included_applications: [:mnesia],
      mod: {BlackShift.Application, []}
    ]
  end
end
