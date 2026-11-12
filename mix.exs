defmodule MontyCad.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/d-led/ex.monty.cad"

  def project do
    [
      app: :ex_monty_cad,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      docs: docs(),
      name: "ExMontyCad",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # The percept has to be Monty's own: `ObservationProcessor` fits the
      # surface, finds the curvatures and assembles the message. A node trained
      # from a CAD part must be the percept a run would have made, or the graph
      # being written is a graph of something else.
      {:ex_tbp_monty_core, "~> 0.1.2"},

      # The geometry: a part parsed once, ray cast exactly against the B-rep, so
      # a frame's points are on the surface rather than near it.
      {:ex_quiddity, "~> 0.1"},

      # A graph memory is JSON lines, gzipped: one record per node.
      {:jason, "~> 1.2"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A graph memory for Monty, built from a STEP part: sample the exact B-rep, " <>
      "take Monty's own percept at each visit, and write the labelled library a " <>
      "run loads."
  end

  defp package do
    [
      files: ~w(lib docs mix.exs README.md CHANGELOG.md LICENSE NOTICE
                .formatter.exs),
      licenses: ["MPL-2.0"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Dmitry Ledentsov"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "docs/bridge.md"],
      groups_for_modules: [
        "The join": [MontyCad, MontyCad.Percept, MontyCad.Training, MontyCad.Library]
      ]
    ]
  end
end
