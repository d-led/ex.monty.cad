# Changelog

## 0.1.0

The first release: a Monty graph memory built from a STEP part.

### Added

- **The percept.** `MontyCad.Percept` turns a `Quiddity.Frame` into the
  observation Monty's sensor modules read (`semantic_3d`, shaded `rgba`,
  `cam_to_world`) and calls Monty's own `ObservationProcessor` for the message:
  pose vectors, whether the pose is defined, principal curvatures, `on_object`,
  `object_coverage`.
- **Training from CAD.** `MontyCad.Training` samples the part's surface at a
  chosen spacing, takes a percept at each visit and answers the visits, with the
  face and the feature family quiddity's recognition gives for each.
- **The library.** `MontyCad.Library` writes the graph memory a Monty run loads —
  gzipped JSON lines, one record per node — and `MontyCad.Training.write/4` does
  all three steps in one call.
- **A task.** `mix monty_cad.train` is the same job from a shell, and prints the
  nodes, the features held and the nodes per feature family.
