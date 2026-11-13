defmodule MontyCad.Library do
  @moduledoc """
  A graph memory in the form a run loads.

  the framework's pretrained memory is one file of JSON lines, gzipped, one record per
  object and input channel:

      {"object_id": "bracket", "input_channel": "patch",
       "positions": [[x, y, z], …], "features": {"hsv": [[h, s, v], …], …}}

  That is the whole format — `Monty.Studio.Memory` in the studio reads it back
  into a `GraphMemory` and matches with it. So a part learned from CAD writes the
  same file a training episode writes, and a run does not know the difference.

  Records are written with `lm_index` `0`: a library built from one part is one
  learning module's memory, and a heterarchy's is several libraries.
  """

  defstruct [:object_id, :channel, positions: [], features: %{}]

  @type t :: %__MODULE__{
          object_id: String.t(),
          channel: String.t(),
          positions: [[float()]],
          features: %{optional(String.t()) => [term()]}
        }

  @doc """
  A library from nodes: their locations and their features, one column a feature.

  `features` is what `MontyCad.Percept.node_features/1` answered per node, so
  this is a transpose with the shape of the file to write: every feature becomes
  a column of the same length as `positions`.
  """
  @spec new(String.t(), [[float()]], [%{optional(String.t()) => term()}], keyword()) ::
          {:ok, t()} | {:error, Quiddity.Error.t()}
  def new(object_id, positions, features, options \\ []) when is_binary(object_id) do
    with :ok <- uniform(positions, 3, "a location is three numbers"),
         :ok <- same_length(positions, features),
         :ok <- any_feature(features) do
      names = features |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.sort()

      {:ok,
       %__MODULE__{
         object_id: object_id,
         channel: Keyword.get(options, :channel, "patch"),
         positions: positions,
         features: Map.new(names, fn name -> {name, Enum.map(features, &Map.get(&1, name))} end)
       }}
    end
  end

  @doc "How many nodes the library holds."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{positions: positions}), do: length(positions)

  @doc "The feature names the library holds."
  @spec feature_names(t()) :: [String.t()]
  def feature_names(%__MODULE__{features: features}), do: features |> Map.keys() |> Enum.sort()

  @doc """
  The library as the records the file holds — one, for one object and channel.

  Each feature is a column of **lists**, one per node, which is the shape the
  framework's own export writes: a scalar feature is `[[1.0], [0.0], …]` there,
  not `[1.0, 0.0, …]`, because a node's features are read as a vector and the
  reader takes each column's width from its first value.
  """
  @spec records(t(), keyword()) :: [map()]
  def records(%__MODULE__{} = library, options \\ []) do
    [
      %{
        "object_id" => library.object_id,
        "input_channel" => library.channel,
        "positions" => library.positions,
        "features" =>
          Map.new(library.features, fn {name, column} ->
            {name, Enum.map(column, &List.wrap/1)}
          end),
        "lm_index" => Keyword.get(options, :lm_index, 0)
      }
    ]
  end

  @doc """
  Writes the library, gzipped, at `path` — the shape `Monty.Studio.Memory` reads.

  A file the format's reader can rebuild is the whole contract, so a write that
  fails is an error rather than a partial file that looks like a memory.
  """
  @spec write(t(), Path.t(), keyword()) :: :ok | {:error, Quiddity.Error.t()}
  def write(%__MODULE__{} = library, path, options \\ []) do
    write_records(records(library, options), path)
  end

  @doc """
  Writes several records as the one gzipped file of JSON lines a run loads.

  A memory is one line per object (`LM`'s own pretrained files are ten lines for
  ten objects), so a memory of several parts is this: each part's record, in one
  file. Writing them together rather than one file per part is what makes the
  run's answer a choice between them.
  """
  @spec write_records([map()], Path.t()) :: :ok | {:error, Quiddity.Error.t()}
  def write_records([_ | _] = records, path) do
    body = Enum.map_join(records, "\n", &Jason.encode!/1)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      case File.write(path, :zlib.gzip(body <> "\n")) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error,
           %Quiddity.Error{code: "unwritable", message: "#{path}: #{:file.format_error(reason)}"}}
      end
    end
  end

  defp uniform(rows, width, message) do
    if Enum.all?(rows, &(is_list(&1) and length(&1) == width)) do
      :ok
    else
      {:error, %Quiddity.Error{code: "bad_request", message: message}}
    end
  end

  defp same_length(positions, features) do
    if length(positions) == length(features) do
      :ok
    else
      {:error,
       %Quiddity.Error{
         code: "bad_request",
         message: "#{length(positions)} locations but #{length(features)} nodes' features"
       }}
    end
  end

  defp any_feature(features) do
    if Enum.any?(features, &(map_size(&1) > 0)) do
      :ok
    else
      {:error,
       %Quiddity.Error{
         code: "bad_request",
         message: "a node with no features cannot be matched, so nothing is written"
       }}
    end
  end
end
