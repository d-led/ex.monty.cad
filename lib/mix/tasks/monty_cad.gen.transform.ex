defmodule Mix.Tasks.MontyCad.Gen.Transform do
  @shortdoc "Generates a sensor transform and the test that holds its contract"

  @moduledoc """
  Writes a sensor transform into the current project.

      mix monty_cad.gen.transform surface_smoother

  Two files: `lib/<app>/plugins/surface_smoother.ex` — the one callback
  `Monty.SensorModules.SensorModule.Transform` requires, answering the payload it
  changed and itself as it now stands — and a test that asserts the module is a
  transform.

  `call/3` raises until the stage does something. Two answers are honest without
  a decision: the payload untouched, for a stage whose feature this run does not
  use, and a percept made from the observation, which
  `MontyCad.Percept.message/1` already does for a CAD frame.
  """

  use Mix.Task

  alias MontyCad.Gen
  alias MontyCad.Gen.Transform

  @impl Mix.Task
  def run([name | _]) do
    Mix.Task.run("app.start")

    module = or_raise(Gen.module_name(name))

    Gen.write!(Transform.files(module))
    |> Enum.each(&Mix.shell().info("wrote #{&1}"))
  end

  def run(_arguments) do
    Mix.raise("usage: mix monty_cad.gen.transform NAME   (for example: surface_smoother)")
  end

  defp or_raise({:ok, module}), do: module
  defp or_raise({:error, message}), do: Mix.raise(message)
end
