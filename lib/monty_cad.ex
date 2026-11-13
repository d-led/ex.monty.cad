defmodule MontyCad do
  @moduledoc """
  A graph memory for the Elixir Monty Studio, built from a STEP part.

  [the framework](https://thousandbrains.org) learns an object by sensing it: a patch of
  surface here, another there. Its pretrained memories come from episodes — an
  agent explores an object and stores what it perceived — which works, and is
  slow, uneven (the agent explores what it happened to touch), and cannot say
  *why* a region is called what it is called.

  A CAD part has been explored already. This package samples its exact B-rep at a
  chosen spacing, takes the percept the framework's own sensor modules would take at each
  visit, and writes the labelled graph memory a run loads.

  ## The three steps, and where each lives

  * `MontyCad.Percept` — a `Quiddity.Frame` becomes the observation a sensor
    module reads, and the framework's own `ObservationProcessor` answers the message.
    Nothing here re-implements a percept.
  * `MontyCad.Training` — visits over the surface, one percept each, with the
    labels quiddity's recognition gives: an exact face and feature per node,
    concluded from nothing.
  * `MontyCad.Library` — the file a run loads: gzipped JSON lines, one record per
    node, in the shape `GraphLM` reads.

  ```elixir
  {:ok, part} = Quiddity.open("bracket.step")

  {:ok, written} = MontyCad.Training.write(part, "bracket", "bracket.jsonl.gz",
    spacing: 2.0
  )

  written.nodes
  #=> 186
  ```

  The same job from a shell:

      mix monty_cad.train bracket.step --object bracket --out bracket.jsonl.gz

  ## What is faithful, and what is not

  `docs/bridge.md` states both, and the shortest version is: the percept is
  the framework's own code, the labels are exact, and the geometry is a drawing rather
  than a measurement — a CAD frame has no sensor noise, no occlusion from a real
  probe, and no colour.
  """

  @doc "Whether the two dependencies answered — a message module and a part."
  @spec ready?() :: boolean()
  def ready? do
    Code.ensure_loaded?(Monty.Frameworks.Models.SensorModules.ObservationProcessor) and
      Quiddity.loaded?()
  end
end
