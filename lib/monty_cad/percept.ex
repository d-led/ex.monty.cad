defmodule MontyCad.Percept do
  @moduledoc """
  A CAD frame as the observation a sensor module reads.

  This is the one place the two worlds meet, and it is deliberately thin: the
  frame supplies exact points, and the framework's own
  `Monty.Frameworks.Models.SensorModules.ObservationProcessor` fits the surface,
  finds the principal curvatures and assembles the message. Nothing here
  re-implements a percept — a node trained on a CAD part has to be the percept a
  run would have made, or the graph being built is a graph of something else.

  ## The observation

  the framework's sensor modules never see a depth image: the transform chain turns one
  into `"semantic_3d"` — one row per pixel, `[x, y, z, semantic_id]` — and that
  is what they read. Here the points come from ray casting the exact B-rep, so
  `"semantic_3d"` is exact rather than an un-projection of a depth buffer, and a
  pixel that met nothing carries `0.0`, the framework's background.

  `"rgba"` is *shading*: a B-rep has no colour, so the image is lit by one light
  from the upper left of the camera. A `"hsv"` feature read from it says how the
  surface turns, not what it is painted; a file with no appearance has no colour
  to perceive, and inventing one would be worse than saying so.

  ## The features a node keeps

  `node_features/1` merges the morphological and non-morphological features, the
  same way `GraphLM.select_features_to_use/2` does. Those are the columns a graph
  memory stores per node: `hsv`, `pose_vectors`, `pose_fully_defined`,
  `principal_curvatures_log`, and whatever else the sensor was asked for.
  """

  alias Monty.Frameworks.Models.SensorModules.ObservationProcessor
  alias Quiddity.{Camera, Frame}

  @default_features [
    "pose_vectors",
    "pose_fully_defined",
    "on_object",
    "object_coverage",
    "min_depth",
    "mean_depth",
    "hsv",
    "principal_curvatures",
    "principal_curvatures_log"
  ]

  @typedoc "An observation: the map the sensor modules read."
  @type observation :: %{optional(String.t()) => term()}

  @doc """
  The observation a sensor module reads from this frame.

  Options: `:semantic_id` (what an on-surface pixel is called, default `1`) and
  `:units` — `:millimetres`, the part's own (the default), or `:metres`, the
  framework's.

  A part is millimetres and a run is metres, and one number decides the rest: the
  points carry the unit, and the depths and the curvatures the processor fits
  from them follow. A percept a run will match against therefore has to be asked
  for in metres; a percept compared with the part's own coordinates stays in
  millimetres.
  """
  @spec observation(Frame.t(), keyword()) :: observation()
  def observation(%Frame{} = frame, options \\ []) do
    semantic_id = Keyword.get(options, :semantic_id, 1)
    units = Keyword.get(options, :units, :millimetres)

    %{
      "semantic_3d" => Frame.semantic_3d(frame, semantic_id: semantic_id),
      "rgba" => rows(Frame.rgba(frame), frame.width),
      "depth" => rows(Frame.depths(frame), frame.width),
      "semantic" => frame |> labels() |> rows(frame.width),
      "cam_to_world" => Camera.cam_to_world(frame.camera)
    }
    |> in_units(units)
  end

  @doc """
  The percept: the framework's own processor over this frame.

  Answers `{:ok, %Monty.Cmp.Message{}}`, whose `location` is the centre pixel's
  point, whose `morphological_features` carry the surface normal and whether the
  pose is defined, and whose `non_morphological_features` carry the depths,
  colour and curvatures the sensor asked for.

  A frame that met nothing still makes a message — the framework's processor does that,
  with `on_object` `0.0` and `process_features_in_lm` false — because "the sensor
  is over empty space" is a fact a model is allowed to act on. A caller that
  wants only real percepts filters on `on_object`, the way `Training.nodes/2`
  does.
  """
  @spec message(Frame.t(), keyword()) :: {:ok, Monty.Cmp.Message.t()}
  def message(%Frame{} = frame, options \\ []) do
    processor =
      ObservationProcessor.new(
        features: Keyword.get(options, :features, @default_features),
        sensor_module_id: Keyword.get(options, :sensor_module_id, "patch"),
        pc1_is_pc2_threshold: Keyword.get(options, :pc1_is_pc2_threshold, 10.0),
        weight_curvature: Keyword.get(options, :weight_curvature, true),
        is_surface_sm: Keyword.get(options, :is_surface_sm, true)
      )

    ObservationProcessor.process(processor, observation(frame, options))
  end

  @doc """
  The features a graph node keeps from a message — morphological and the rest,
  merged, the way `GraphLM.select_features_to_use/2` merges them.

  Keys are strings and values are what the framework stores: a three-element list for a
  pose vector, a two-element list for curvatures, a float for a defined pose.
  """
  @spec node_features(Monty.Cmp.Message.t()) :: %{optional(String.t()) => term()}
  def node_features(%Monty.Cmp.Message{} = message) do
    message
    |> message_features()
    |> Enum.into(%{}, fn {name, value} -> {name, flatten(value)} end)
  end

  defp message_features(message) do
    Map.merge(message.morphological_features || %{}, message.non_morphological_features || %{})
  end

  # A pose vector is a struct in the framework's vocabulary; a graph stores
  # numbers, and the nine of them travel flat — `n0, n1, n2, c0, c1, c2, k0, k1,
  # k2`, which is the shape Monty's own export writes and the shape the reader
  # assumes: `GraphMemory.get_rotation_features_at_nodes/4` chunks a value by
  # three to get the three vectors. Keeping the rows nested put every value one
  # level deeper than that, and a run died in burst sampling aligning a matrix
  # against `[[matrix]]`.
  defp flatten(%Monty.Geometry.SurfacePoseVectors{value: rows}), do: List.flatten(rows)

  defp flatten(values) when is_list(values), do: Enum.map(values, &flatten/1)
  defp flatten(value), do: value

  defp labels(frame) do
    for face <- Frame.face_ids(frame), do: if(face == nil, do: 0, else: face + 1)
  end

  defp rows(values, width) do
    values
    |> Enum.chunk_every(width)
    |> Enum.map(&Enum.map(&1, fn value -> value end))
  end

  # Monty is metres; a part is millimetres. Only the points, the depths and the
  # camera's translation carry a length — a colour, a semantic id and a rotation
  # do not — and the processor fits its curvatures from these points, so scaling
  # them is what makes a curvature 1/m rather than 1/mm.
  @millimetres_per_metre 1000.0

  defp in_units(observation, :metres) do
    observation
    |> Map.update!("semantic_3d", fn rows -> Enum.map(rows, &point_in_metres/1) end)
    |> Map.update!("depth", fn rows ->
      Enum.map(rows, fn row -> Enum.map(row, &length_in_metres/1) end)
    end)
    |> Map.update!("cam_to_world", &translated_in_metres/1)
  end

  defp in_units(observation, :millimetres), do: observation

  # A point is `[x, y, z, semantic_id]`: the id is what a sensor model reads to
  # decide which pixels are on the object, and it is not a distance.
  defp point_in_metres([x, y, z, semantic_id]),
    do: [length_in_metres(x), length_in_metres(y), length_in_metres(z), semantic_id]

  defp translated_in_metres([first, second, third, last]),
    do: [row_in_metres(first), row_in_metres(second), row_in_metres(third), last]

  # A camera row is its basis and its origin: only the origin is a length.
  defp row_in_metres([right, up, forward, origin]),
    do: [right, up, forward, length_in_metres(origin)]

  defp length_in_metres(millimetres), do: millimetres / @millimetres_per_metre
end
