# Changelog

## Unreleased

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
