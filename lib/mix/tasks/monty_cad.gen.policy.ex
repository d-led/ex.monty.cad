defmodule Mix.Tasks.MontyCad.Gen.Policy do
  @shortdoc "Generates a motor policy and the test that holds its contract"

  @moduledoc """
  Writes a motor policy into the current project.

      mix monty_cad.gen.policy follow_chamfers

  Two files: `lib/<app>/plugins/follow_chamfers.ex` — the callbacks
  `Monty.Frameworks.Models.MotorPolicies.MotorPolicy` requires, and the
  `describe/0` a cluster asks for — and a test that asserts both. `call/6` raises
  until the decision is written, on purpose: a generated body that looks like an
  answer is a decision nobody made.

  The policy is `:owner_only`, because a policy over a CAD part reads a B-rep
  handle and that cannot leave the node that opened it. A policy over something
  else changes the description and says why.
  """

  use Mix.Task

  alias MontyCad.Gen
  alias MontyCad.Gen.Policy

  @impl Mix.Task
  def run([name | _]) do
    Mix.Task.run("app.start")

    module = or_raise(Gen.module_name(name))

    Gen.write!(Policy.files(module))
    |> Enum.each(&Mix.shell().info("wrote #{&1}"))
  end

  def run(_arguments) do
    Mix.raise("usage: mix monty_cad.gen.policy NAME   (for example: follow_chamfers)")
  end

  defp or_raise({:ok, module}), do: module
  defp or_raise({:error, message}), do: Mix.raise(message)
end
