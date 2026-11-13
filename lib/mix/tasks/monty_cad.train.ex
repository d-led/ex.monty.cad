defmodule Mix.Tasks.MontyCad.Train do
  @shortdoc "Writes the graph memory a run loads, from a STEP part"

  @moduledoc """
  Samples a part's surface, takes the framework's percept at each visit, and writes the
  library.

      mix monty_cad.train bracket.step --object bracket --out bracket.jsonl.gz

  Options:

    * `--object` — the name the graph is matched as. Required; the file is not
      allowed to guess it, because a memory matched under the wrong name is a
      memory that never wins.
    * `--out` — where to write. Defaults to `<object>.jsonl.gz`.
    * `--spacing` — millimetres between visits (default 2.0). Smaller is denser
      and slower; a 40 mm spacing on a small plate is a dozen nodes.
    * `--limit` — the most visits to make (default 2000).

  The answer names the file, the node count, the features held per node and how
  many nodes each feature family contributed. Nodes whose patch saw no surface
  are counted, not stored: an empty percept is not a node.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {options, paths, invalid} =
      OptionParser.parse(argv,
        strict: [object: :string, out: :string, spacing: :float, limit: :integer]
      )

    part_path = List.first(paths)
    object = options[:object]
    out = options[:out] || (object && "#{object}.jsonl.gz")

    if part_path == nil or invalid != [] do
      Mix.raise(usage())
    end

    if object == nil or out == nil do
      Mix.raise("--object is required: it is the name the graph is matched as")
    end

    part = or_raise(Quiddity.open(part_path))

    written =
      or_raise(
        MontyCad.Training.write(part, object, out,
          spacing: options[:spacing] || 2.0,
          limit: options[:limit] || 2000
        )
      )

    Mix.shell().info(report(written))
  end

  defp or_raise({:ok, value}), do: value
  defp or_raise({:error, error}), do: Mix.raise(Exception.message(error))

  defp report(written) do
    families =
      written.families
      |> Enum.sort_by(fn {_family, count} -> -count end)
      |> Enum.map_join(", ", fn {family, count} -> "#{family || "body"} (#{count})" end)

    """
    Wrote #{written.path} — `#{written.object_id}`, #{written.nodes} nodes from #{written.visited} visits.
    Features held per node: #{Enum.join(written.features, ", ")}.
    Nodes by feature: #{families}.
    """
  end

  defp usage do
    """
    usage: mix monty_cad.train PART.step --object NAME [--out FILE] [--spacing MM] [--limit N]
    """
  end
end
