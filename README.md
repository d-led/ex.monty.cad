# ex_monty_cad

The framework learns an object by sensing it, and its pretrained memories come from
episodes. A CAD part has already been explored: its surface is exact, and the
recognition names every face, so a node's label is a fact rather than a
conclusion. This package is the join between the two — the part on one side,
the framework's own percept and its library format on the other.

```elixir
{:ok, part} = Quiddity.open("bracket.step")

# What a sensor module perceives here:
{:ok, camera} = Quiddity.Camera.patch([15.0, 0.0, 13.0], [0.0, 0.0, 1.0], distance: 5.0)
{:ok, frame} = Quiddity.frame(part, camera)
{:ok, message} = MontyCad.Percept.message(frame)

MontyCad.Percept.node_features(message)
#=> %{"pose_vectors" => [...], "principal_curvatures_log" => [0.0, 0.0], ...}

# The library a run loads:
{:ok, written} = MontyCad.Training.write(part, "bracket", "bracket.jsonl.gz", spacing: 2.0)
written.nodes
#=> 186
```

The percept is the framework's own code — `Monty.Frameworks.Models.SensorModules.ObservationProcessor`
over the frame — not a re-implementation, so a node trained from a part is the
percept a run would have made. `docs/bridge.md` says exactly what is faithful and
what is not.

## The three modules

| Module              | What it answers                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MontyCad.Percept`  | A `Quiddity.Frame` as the observation a sensor module reads: `semantic_3d`, shaded `rgba`, `cam_to_world`, and the message Monty builds from them |
| `MontyCad.Training` | Visits over the part's surface, one percept each, with exact labels from the recognition                                                          |
| `MontyCad.Library`  | The file: gzipped JSON lines, one record per node, in the shape `GraphLM` reads                                                                   |

`MontyCad.Percept.node_features/1` merges the morphological and non-morphological
features the way `GraphLM.select_features_to_use/2` does — those are the columns
a record stores.

## From a shell

    mix monty_cad.train bracket.step --object bracket --out bracket.jsonl.gz

`--spacing` sets the millimetres between visits, `--limit` the most visits to
make. The answer names the file, the nodes, the features held, and how many nodes
each feature family contributed.

`--labels features` writes the same part as a memory of *its features* — one
object a bore, a boss, a plate, with the stock no feature claims as
`bracket/body` — which is the memory a compositional run learns from:

    mix monty_cad.train bracket.step --object bracket --labels features --out features.jsonl.gz

The same split is available in the library as
`MontyCad.Training.write_library/3`'s `labels: :features`. The bodies are one
object however many faces they own, because a memory file is keyed by object id.

## A part as the world an episode steps

`MontyCad.Scene` answers what a sensor sees of a part. Given a recognition it also
labels what it sees with the part's own features — one id per record, and the body
for every face no feature claims — so a supervised episode learns a bore rather
than a plate:

```elixir
{:ok, part} = Quiddity.open("bracket.step")
{:ok, recognition} = Quiddity.features(part)
scene = MontyCad.Scene.new(part, label: "bracket", recognition: recognition)

MontyCad.Scene.semantic_id_to_label(scene)
#=> %{1 => "bosses/0", 2 => "holes/0", 3 => "risers/0", 4 => "bracket body"}

MontyCad.Scene.primary_target(scene)["object_name"]
#=> the feature the start pose looks at
```

Every id is an answer the recognition gave: a face it could not explain carries
the body's id, so nothing is labelled as a feature the geometry did not support.

## Install

```elixir
def deps do
  [
    {:ex_monty_cad, "~> 0.6.3"}
  ]
end
```

This package is Elixir only, but `ex_quiddity` builds a Rust engine when it is
compiled, so **building wants a Rust toolchain and running wants none**.

## Where to find what

| Question                                                     | Where                                                                                 |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| The join, module by module                                   | [`MontyCad`](https://hexdocs.pm/ex_monty_cad/MontyCad.html)                            |
| A frame as the observation a sensor module reads              | [`MontyCad.Percept`](https://hexdocs.pm/ex_monty_cad/MontyCad.Percept.html)            |
| Visits over a part, one percept each                          | [`MontyCad.Training`](https://hexdocs.pm/ex_monty_cad/MontyCad.Training.html)           |
| The library file a run loads                                  | [`MontyCad.Library`](https://hexdocs.pm/ex_monty_cad/MontyCad.Library.html)             |
| Where a part and a library are found                          | [`MontyCad.Inputs`](https://hexdocs.pm/ex_monty_cad/MontyCad.Inputs.html)               |
| A part as the world an episode steps                          | [`MontyCad.Scene`](https://hexdocs.pm/ex_monty_cad/MontyCad.Scene.html)                 |
| What is faithful to the framework and what is not             | [`bridge`](https://hexdocs.pm/ex_monty_cad/bridge.html)                                |
| Working on the package: the framework it targets, tests, releasing | [`development`](https://hexdocs.pm/ex_monty_cad/development.html)                |

The API by module — and the same content as [`llms.txt`](https://d-led.github.io/ex.monty.cad/llms.txt)
for a model with no browser — is generated by `mix docs` and published at
[d-led.github.io/ex.monty.cad](https://d-led.github.io/ex.monty.cad/) from `main`;
the released version is on [HexDocs](https://hexdocs.pm/ex_monty_cad).

## Limits, said out loud

- A CAD frame is perfect: no sensor noise, no occlusion from a real probe. A
  library trained from one is a library trained from a drawing; `docs/bridge.md`
  says what that costs.
- A library holds the part, densely and evenly. It does not hold an exploration
  policy — that is what a training episode is, and this package does not replace
  one.
- The labels are exact because the recognition named the faces, not because
  anything was inferred. Where quiddity could not prove a feature,
  `Quiddity.Recognition.unexplained_faces/1` is where that is visible.
- A node whose patch saw too little surface is skipped and counted, not stored:
  an empty percept is not a node.

## Citation

The percept this package speaks — features, pose vectors, a library of
locations — is Monty's, so the papers that describe Monty are the ones to cite.
The package is citable too: [`CITATION.cff`](CITATION.cff) is what GitHub's
*Cite this repository* button reads, and Zenodo mints a DOI for each release.

```bibtex
@article{clay2024thousandbrains,
  title   = {The Thousand Brains Project: A New Paradigm for Sensorimotor Intelligence},
  author  = {Clay, Viviane and Leadholm, Niels and Hawkins, Jeff},
  journal = {arXiv preprint arXiv:2412.18354},
  year    = {2024},
  url     = {https://arxiv.org/abs/2412.18354}
}

@article{hawkins2019framework,
  title   = {A Framework for Intelligence and Cortical Function Based on Grid Cells in the Neocortex},
  author  = {Hawkins, Jeff and Lewis, Marcus and Klukas, Mirko and Purdy, Scott and Ahmad, Subutai},
  journal = {Frontiers in Neural Circuits},
  volume  = {12},
  pages   = {121},
  year    = {2019},
  doi     = {10.3389/fncir.2018.00121}
}
```

## Licence

MPL-2.0 (`LICENSE`). The dependencies keep their own: `ex_quiddity` is MPL-2.0,
`ex_tbp_monty_core` is MIT (the Thousand Brains Project's implementation, reimplemented on
the BEAM), and the engine under `ex_quiddity` — quiddity and haecceity — is
Apache-2.0. `NOTICE` says what came from where.
