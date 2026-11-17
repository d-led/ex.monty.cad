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
    * `--labels` — `part` (the default) writes one object; `features` writes one
      object per feature the part is made of, so a run over the memory can
      recognise a bore rather than the lump a bore is cut into.

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
        strict: [
          object: :string,
          out: :string,
          spacing: :float,
          limit: :integer,
          labels: :string
        ]
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

    Mix.shell().info(write(part_path, object, out, options) |> report())
  end

  # One object a part, or one a feature. Both are the same sampling of the same
  # part; what differs is how the visits are split before they are written.
  defp write(part_path, object, out, options) do
    sampling = [spacing: options[:spacing] || 2.0, limit: options[:limit] || 2000]

    case options[:labels] do
      nil ->
        part = or_raise(Quiddity.open(part_path))
        or_raise(MontyCad.Training.write(part, object, out, sampling))

      "part" ->
        write(part_path, object, out, Keyword.delete(options, :labels))

      "features" ->
        or_raise(
          MontyCad.Training.write_library([{object, part_path}], out, [
            {:labels, :features} | sampling
          ])
        )

      other ->
        Mix.raise("labels is `part` or `features`, got: #{inspect(other)}")
    end
  end

  defp or_raise({:ok, value}), do: value
  defp or_raise({:error, error}), do: Mix.raise(Exception.message(error))

  # A feature memory is several objects in one file, and the line a person reads
  # is each object's own size: that is what a run meets first.
  defp report(%{objects: objects} = written) do
    lines =
      Enum.map_join(objects, "", fn object ->
        "  #{object.object_id}: #{object.nodes} nodes, " <> families_of(object.families) <> "\n"
      end)

    "Wrote #{written.path} — #{length(objects)} object(s), #{written.nodes} nodes in all.\n" <>
      lines
  end

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

  defp families_of(families) do
    families
    |> Enum.sort_by(fn {_family, count} -> -count end)
    |> Enum.map_join(", ", fn {family, count} -> "#{family || "body"} (#{count})" end)
  end

  defp usage do
    """
    usage: mix monty_cad.train PART.step --object NAME [--out FILE] [--spacing MM] [--limit N]
           [--labels part|features]
    """
  end
end
