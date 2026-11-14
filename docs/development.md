# Working on the package

What a caller needs is in [`README`](readme.html), and what is faithful to the
framework is in [`bridge`](bridge.html). This page is for changing the package:
what it targets, where the pieces are, and how a version is published.

| Path                                | What it is                                                          |
| ----------------------------------- | ------------------------------------------------------------------- |
| `lib/monty_cad.ex`                  | the join's own answers: what a run gets from a part                 |
| `lib/monty_cad/percept.ex`          | a `Quiddity.Frame` as the observation a sensor module reads         |
| `lib/monty_cad/training.ex`         | visits over a part's surface, one percept each                      |
| `lib/monty_cad/library.ex`          | the file: gzipped JSON lines in the shape `GraphLM` reads           |
| `lib/monty_cad/policy/feature_walk.ex` | the motor policy that walks a part with the recognition in hand  |
| `lib/monty_cad/gen.ex`, `gen/*.ex`  | what the two generators write, and the module and test they produce  |
| `lib/monty_cad/plugin/check.ex`     | the plugin check CI runs                                            |
| `lib/mix/tasks/*.ex`                | `monty_cad.train`, `monty_cad.gen.policy`, `monty_cad.gen.transform`, `monty_cad.plugin.check` |
| `docs/bridge.md`                    | what is the framework's own code, what is ours, and what is neither |

## The framework it targets

The percept is **the framework's own code** — `Monty.Frameworks.Models.SensorModules.ObservationProcessor`
over a `Quiddity.Frame` — not a re-implementation, so a node trained from a part
is the percept a run would have made. That is the one rule this package keeps:
where the framework has an answer, the framework's answer is called. `bridge`
lists the places it does not, and why.

A change to `ex_tbp_monty_core`'s feature selection or `GraphLM`'s record shape
is therefore a change here: `MontyCad.Percept.node_features/1` merges features
the way `GraphLM.select_features_to_use/2` does, and the library writes the
columns those names imply.

## Tests

`mix test` covers the join, the generators (they write a module and a test that
compiles and passes), the plugin check, the feature-walk policy, and the training
task end to end against the fixtures. `scripts/quality.sh` is what CI runs.

## CI and publishing

`.github/workflows/release.yml` publishes a tag to Hex and needs the
`HEX_API_KEY` secret on this repository.

Nothing is published from a branch: `ci` proves a commit, a tag says it is a
version. The version lives in `VERSION` and is written into `mix.exs` (and the
dependency line in the README) by the script that moves it:

```bash
elixir scripts/release.exs bump patch     # 0.6.1 -> 0.6.2, in every file
git add -A && git commit -m "release: 0.6.2" && git push
./scripts/tag_and_push_version.sh          # refuses a dirty tree or red CI
```

Then watch the run: the package and the documentation are staged for approval on
Hex separately, so `mix hex.publish` succeeding is not the same as being
installable.
