defmodule MontyCad.MixProject do
  use Mix.Project

  @version "0.6.1"
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
      # The percept has to be the framework's own: `ObservationProcessor` fits the
      # surface, finds the curvatures and assembles the message. A node trained
      # from a CAD part must be the percept a run would have made, or the graph
      # being written is a graph of something else.
      {:ex_tbp_monty_core, "~> 0.1.2"},

      # The plugin contract and its registry. A plugin's description is one map,
      # and two definitions of what belongs in it are two answers to one question;
      # this package's own copy is gone, so a generated policy declares
      # `@behaviour MontyPlugin`. From Hex, because a package that is published
      # cannot depend on a repository — and because the contract is exactly the
      # thing two packages must agree about, so agreement is a version.
      {:ex_monty_plugin, "~> 0.1.2"},

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
    "A graph memory for the Elixir Monty Studio, built from a STEP part: sample the exact B-rep, " <>
      "take the framework's own percept at each visit, and write the labelled library a " <>
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
