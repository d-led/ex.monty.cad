# Changelog

## 0.6.2

The front page is a map, and the release notes moved off it.

### Changed

- `README.md` had a paragraph about where the documentation is generated from as
  its second paragraph — a fact about this repository, not about the package. It
  is now part of a table of where each other question is answered: the modules in
  the order a reader meets them, the bridge, the check, and the development page.
- "Releasing" moved to `docs/development.md`, with the layout, the one rule this
  package keeps (where the framework has an answer, the framework's answer is
  called), the tests, and CI.
- The API reference groups the modules a reader came for — `The join`,
  `A policy with the part`, `Writing a plugin` (with its three mix tasks), and
  `Where the files come from` — instead of `The join` and a loose list.

## 0.6.1

The percept a run can load, and a memory sampled per part.

### Fixed

- **Pose vectors are nine flat numbers.** Monty's export writes them that way; a
  percept that wrote them shaped made a run crash in burst sampling on a CAD
  memory.

### Added

- **`Training.write_library/3` and `Training.spacing/1`** — a memory of parts is
  sampled per part, so a library of parts is not a library of densities.

## 0.6.0

### Changed

- **`Policy.FeatureWalk`'s `visited` is a list of feature ids, not a `MapSet`.**
  The walk is a policy's value and it is handed to whoever keeps it; a `MapSet`
  in it made an empty walk a term no caller outside this package could pass to a
  function typed against the walk's own contract (`mix dialyzer`'s
  `call_without_opaque`). `state_dict/1` answers the same map it did.

## 0.5.0

- **`Policy.FeatureWalk`** — the walk from feature to feature over a part:
  keep the standoff, then take one step towards the feature the recognition
  names, then the next.
- **`Inputs`** — a part is a name in `$MONTY_DATA/parts` (the `.step`/`.stp`
  extension optional), and a memory's address is
  `$MONTY_LIBRARIES/<release>/<name>.jsonl.gz`.
- **`Percept`'s `:units`** — millimetres by default, which is what a part is
  measured in, and metres for a library a run loads.
- **`Library.records/1`** writes every feature column as a list, which is the
  shape the framework's graph memory reads.

## 0.4.0

- **`Scene`** — a part as the scene a world steps: what a sensor sees, the pose
  to start one in, the primary target, and the semantic ids as labels.

## 0.3.0

### Changed — breaking

- **The plugin contract is `MontyPlugin`, from `ex_monty_plugin`.**
  `MontyCad.Plugin` is gone: a description is one map, and two definitions of what
  belongs in it are two answers to one question — one asked of a policy written
  here and one asked of a policy written somewhere else. A module that said
  `@behaviour MontyCad.Plugin` now says `@behaviour MontyPlugin` (add the package
  as a dependency), and `MontyCad.Plugin.conforms?/1` is
  `MontyPlugin.conforms?/1`. `mix monty_cad.gen.policy` emits the new name, so a
  freshly generated plugin needs no edit.
- **`MontyCad.Plugin.Check` with it** — `problems/1` and `plugins/1` read the
  shared contract, so a plugin of another package is checked the same way. The
  callbacks a kind requires stay here: that is knowledge of the framework's behaviours, not
  of the contract.

### Added

- **`MontyCad.Plugin.Check`** and **`mix monty_cad.plugin.check`** — every module of
  an application that describes itself as a plugin, checked against the contract:
  the description conforms, and the callbacks its kind requires are exported. The
  compiler already refuses a missing callback; a description is a map, and a map
  drifts silently.

## 0.2.0

Code generators, and the contract they generate against.

### Added

- **`MontyCad.Plugin`** — what a plugin tells a cluster about itself
  (`name`, `kind`, `version`, `placement`, `needs`), and `conforms?/1`, which says
  what is wrong with a description rather than only that something is.
- **`mix monty_cad.gen.policy NAME`** — a motor policy: the callbacks
  `Monty.Frameworks.Models.MotorPolicies.MotorPolicy` requires, the `describe/0` a
  cluster asks for, and a test that holds both. `call/6` raises until the decision
  is written.
- **`mix monty_cad.gen.transform NAME`** — a sensor transform: the one callback
  `Monty.SensorModules.SensorModule.Transform` requires, and a test that asserts
  the module is a transform.
- **`MontyCad.Gen`** — the shared half: plugin names, the host application's
  namespace, and formatted output, so a generated file is never the first thing a
  formatter has to touch.

## 0.1.0

The first release: an Elixir Monty Studio graph memory built from a STEP part.

### Added

- **The percept.** `MontyCad.Percept` turns a `Quiddity.Frame` into the
  observation the framework's sensor modules read (`semantic_3d`, shaded `rgba`,
  `cam_to_world`) and calls the framework's own `ObservationProcessor` for the message:
  pose vectors, whether the pose is defined, principal curvatures, `on_object`,
  `object_coverage`.
- **Training from CAD.** `MontyCad.Training` samples the part's surface at a
  chosen spacing, takes a percept at each visit and answers the visits, with the
  face and the feature family quiddity's recognition gives for each.
- **The library.** `MontyCad.Library` writes the graph memory a run loads —
  gzipped JSON lines, one record per node — and `MontyCad.Training.write/4` does
  all three steps in one call.
- **A task.** `mix monty_cad.train` is the same job from a shell, and prints the
  nodes, the features held and the nodes per feature family.
