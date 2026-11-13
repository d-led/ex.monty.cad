defmodule Mix.Tasks.MontyCad.Plugin.Check do
  @shortdoc "Checks that every plugin in this application is what it says it is"

  @moduledoc """
  Every module of this application that describes itself as a plugin, checked
  against `MontyPlugin`: the description conforms, and the callbacks its kind
  requires are exported.

      mix monty_cad.plugin.check

  Run it in CI. A description edited in one place — a kind changed, `needs`
  dropped, a callback renamed — is otherwise discovered by a run that asks for the
  plugin and gets an error from a place that says nothing about the plugin.
  """

  use Mix.Task

  alias MontyCad.Plugin.Check

  @impl Mix.Task
  def run(_arguments) do
    Mix.Task.run("app.start")

    app = Mix.Project.config()[:app]
    plugins = Check.plugins(app)
    problems = Enum.flat_map(plugins, &Check.problems/1)

    case problems do
      [] ->
        Mix.shell().info("#{length(plugins)} plugin(s), each what it says it is")

      problems ->
        Enum.each(problems, &Mix.shell().error(&1))
        Mix.raise("#{length(problems)} problem(s) with #{length(plugins)} plugin(s)")
    end
  end
end
