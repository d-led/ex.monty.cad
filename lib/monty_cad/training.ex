defmodule MontyCad.Training do
  @moduledoc """
  A graph memory built from a CAD part — supervised training without an episode.

  The framework learns an object by touching it: a surface agent explores, and every
  patch it lands on becomes a node with the percept it made there. A CAD part
  already *is* the explored object — its surface is known exactly — so the
  exploration can be replaced by sampling: put a patch sensor on the surface,
  spacing the visits as far apart as the detail needs, and take the percept each
  visit makes.

  What comes out is what a training episode comes out with: locations in the
  part's own frame and the features the sensor modules measured there. The
  difference is that the *labels* are exact — quiddity says which face each node
  is on and which feature that face belongs to — which is what makes this
  supervised: a node's feature family is read, never concluded.

  ## Units

  The library is the one a *run* loads, so it is written in the framework's
  metres, not in the part's millimetres: locations, depths and curvatures are
  what a sensor module would have measured in a run, and a graph in millimetres
  matched against a world in metres disagrees by a thousand. The sampling dials
  (`:spacing`, `:distance`) stay in millimetres, because they are about the
  part's surface rather than about the framework. A caller that wants the part's
  own frame says `units: :millimetres`.

  ## What this is not

  It is not a replacement for a training episode's *action* policy. the framework's
  episodes also learn where to look next, and a CAD-built memory does not hold
  that. What it holds is the part, densely and evenly, which is the thing an
  episode spends its first minutes doing badly.

  ## Cost

  One patch is one frame — 4 096 rays — and a percept is the framework's own feature
  extraction on top. A plate at 2 mm spacing is a few hundred patches; a large
  part at 0.5 mm is thousands, so `:limit` caps the work and `:spacing` is the
  honest dial.
  """

  alias MontyCad.{Library, Percept}
  alias Quiddity.{Camera, Frame, Part, Recognition}

  @default_spacing 2.0
  @default_limit 2_000
  # The framework reads metres; a part is millimetres. Only the percept converts.
  @default_units :metres
  # A patch sensor stands a centimetre or two off the surface it reads. A
  # closer stand reads a smaller patch, so fewer visits straddle a face's edge
  # and are skipped for it.
  @default_distance 5.0
  # The crate's own patch is 66° wide. A run's patch is whatever its camera
  # makes of `zoom`, and Monty's MuJoCo agent builds
  # `fovy = 2·atan2(ratio·tan(base_fovh/2), zoom)` from a 90° base, so the
  # tutorial's `zoom: 10` reads 11.4° — a patch six times narrower than this
  # default. A memory taught through the wider patch stores curvature and depth
  # averaged over a swath no percept of the run contains, which is why a caller
  # that knows its sensor passes `:fov_x`.
  @default_fov_x 66.0 * :math.pi() / 180.0
  # How many visits a part gets across its largest extent: the dial that makes
  # two parts of different sizes comparable, and the same idea as the framework's
  # own `num_model_voxels_per_dim` (`spacing/1`).
  @samples_across 30

  @typedoc """
  One node: where the sensor was, what it perceived, and what quiddity says it
  is looking at.
  """
  @type visit_node :: %{
          location: [float()],
          features: %{optional(String.t()) => term()},
          face: non_neg_integer(),
          family: String.t() | nil
        }

  @doc """
  Visits the part and takes a percept at each one.

  Options:

    * `:spacing` — how far apart the visits are, in millimetres (default 2.0);
    * `:limit` — the most visits to make (default 2 000);
    * `:distance` — how far the sensor stands off the surface (default 5 mm,
      which keeps a patch's footprint smaller than a face on most parts);
    * `:fov_x` — the patch's horizontal field of view, in radians (default 66°).
      A feature memory must be taught through the same field of view the run's
      patch makes, or the node's features are an average over a swath the run
      never sees in one percept;
    * `:min_coverage` — the share of a patch that must land on the part for the
      visit to count (default 0.6);
    * `:features` — the sensor's feature list, defaulting to a patch's;
    * `:units` — `:metres` (default) for a library a run loads, or
      `:millimetres` for the part's own frame;
    * `:progress` — a one-argument function called after each percept, for a
      caller that wants to show a count rather than wait.

  A visit whose patch does not see the surface — a corner sharper than the
  patch's field of view, or a face the rays miss — is *skipped*, not invented:
  the node count is what the sensor could perceive, and `:skipped` in the answer
  says how many visits it was.
  """
  @spec nodes(Part.t(), keyword()) :: {:ok, map()} | {:error, Quiddity.Error.t()}
  def nodes(%Part{} = part, options \\ []) do
    with {:ok, recognition} <- Quiddity.features(part),
         {:ok, samples} <-
           Quiddity.samples(part,
             spacing: Keyword.get(options, :spacing, @default_spacing),
             limit: Keyword.get(options, :limit, @default_limit)
           ) do
      visits = Enum.zip([samples.points, samples.normals, samples.faces])

      node_options =
        options
        |> Keyword.put_new(:units, @default_units)
        |> Keyword.put(:recognition, recognition)

      nodes = Enum.map(visits, &visit(part, &1, node_options))

      kept = for {:ok, node} <- nodes, do: node

      {:ok,
       %{
         nodes: kept,
         visited: length(visits),
         skipped: length(visits) - length(kept),
         truncated: samples.meta["truncated"] == true,
         families: kept |> Enum.map(& &1.family) |> Enum.frequencies()
       }}
    end
  end

  @doc """
  The nodes a previous visit produced, as the library a run loads.

  `object_id` is what the graph is called — the name a recognition would answer
  — so a run matching this library says `"bracket"`, not `"new_object0"`.
  """
  @spec library([visit_node()], String.t(), keyword()) ::
          {:ok, Library.t()} | {:error, Quiddity.Error.t()}
  def library(nodes, object_id, options \\ []) do
    Library.new(
      object_id,
      Enum.map(nodes, & &1.location),
      Enum.map(nodes, & &1.features),
      options
    )
  end

  @doc """
  Samples the part and writes the library a run loads, in one call.

  Answers what was written and what it holds: the path, the node count, the
  feature names, and how many nodes each feature family contributed.
  """
  @spec write(Part.t(), String.t(), Path.t(), keyword()) ::
          {:ok, map()} | {:error, Quiddity.Error.t()}
  def write(%Part{} = part, object_id, path, options \\ []) do
    with {:ok, %{nodes: nodes} = visits} <- nodes(part, options),
         {:ok, library} <- library(nodes, object_id, options),
         :ok <- Library.write(library, path) do
      {:ok,
       %{
         path: path,
         object_id: object_id,
         nodes: Library.size(library),
         visited: visits.visited,
         skipped: visits.skipped,
         truncated: visits.truncated,
         families: visits.families,
         features: Library.feature_names(library),
         source_sha256: part.summary["sha256"]
       }}
    end
  end

  @doc """
  The spacing a part is sampled at, in the part's own millimetres.

  Never finer than `#{@default_spacing}`, and never more than #{@samples_across}
  visits across the part's largest extent — so a 60 mm part is 2 mm either way
  and a 300 mm part is 10 mm. The floor keeps a small part from being sampled
  beyond what its detail needs; the ceiling is what makes a memory of *several*
  parts comparable, because the memory is compared across its parts.

  A fixed number of millimetres is right for one part and wrong for a library.
  With a fixed 2 mm the same number of nodes covers twenty-five times the area
  on a part five times the size, so the library is a library of two densities —
  and the denser graph wins the candidate search, which is a radius, not a
  shape. Measured: a library of a plate and its 5× twin concluded the *small*
  plate at evidence 15.5, and the same pair at 1.5× concluded it at 12.0
  (`docs/cad.md` in the studio). Sampled at `spacing/1` instead, the sensed part
  is the one on top in every seed tried, at evidence up to 39.8.

  The framework has the same idea for the same reason: a graph memory is
  voxelised over `num_model_voxels_per_dim` of `max_graph_size`, a resolution
  relative to the graph rather than a number of metres.
  """
  @spec spacing(Part.t()) :: float()
  def spacing(%Part{} = part) do
    case Map.get(part.summary, "extent") do
      [_ | _] = extent -> max(@default_spacing, Enum.max(extent) / @samples_across)
      _no_extent -> @default_spacing
    end
  end

  @doc """
  A memory of several parts, written as the one file a run loads.

  `parts` is `[{object_id, path}]`, in the order they should appear in the file,
  and each is sampled at `spacing/1` — never at one number of millimetres for
  all of them, which is what `spacing/1` is about.

  Options are `nodes/2`'s and are passed to every part, except:

    * `:spacing` — forced for every part, for reproducing a memory written
      before the rule above existed;
    * `:limit`, `:distance`, `:min_coverage`, `:units` — as `nodes/2` reads them;
    * `:labels` — what an object *is*. `:part` (the default) writes one object a
      part; `:features` writes one object per feature the part is made of, so a
      run can learn a bore rather than a lump. A feature's object is
      `<part>/<feature id>` and the faces no feature claimed are `<part>/body`.

  Answers the path, each object's contribution, and the total node count. A part
  that cannot be opened or sampled is an error, not a file missing that part: a
  memory that quietly holds four of five parts answers a question nobody asked.
  """
  @spec write_library([{String.t(), Path.t()}], Path.t(), keyword()) ::
          {:ok, map()} | {:error, Quiddity.Error.t()}
  def write_library([_ | _] = parts, path, options \\ []) do
    with {:ok, written} <- write_parts(parts, options),
         :ok <- Library.write_records(Enum.flat_map(written, & &1.records), path) do
      objects = Enum.flat_map(written, & &1.objects)

      {:ok,
       %{
         path: path,
         nodes: objects |> Enum.map(& &1.nodes) |> Enum.sum(),
         objects: objects
       }}
    end
  end

  defp write_parts(parts, options) do
    parts
    |> Enum.reduce_while({:ok, []}, fn {object_id, part_path}, {:ok, written} ->
      case write_part(object_id, part_path, options) do
        {:ok, part} -> {:cont, {:ok, [part | written]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, written} -> {:ok, Enum.reverse(written)}
      error -> error
    end
  end

  defp write_part(object_id, part_path, options) do
    with {:ok, part} <- Quiddity.open(part_path),
         {:ok, recognition} <- Quiddity.features(part),
         spacing <- Keyword.get(options, :spacing) || spacing(part),
         part_options =
           options
           |> Keyword.put(:recognition, recognition)
           |> Keyword.put(:spacing, spacing),
         {:ok, %{nodes: nodes} = visits} <- nodes(part, part_options),
         {:ok, objects} <-
           objects_of(nodes, recognition, object_id, Keyword.get(options, :labels, :part)) do
      {:ok,
       %{
         object_id: object_id,
         nodes: objects |> Enum.map(& &1.nodes) |> Enum.sum(),
         spacing: spacing,
         visited: visits.visited,
         skipped: visits.skipped,
         truncated: visits.truncated,
         families: visits.families,
         records: Enum.flat_map(objects, & &1.records),
         objects: Enum.map(objects, &Map.put(&1, :spacing, spacing))
       }}
    end
  end

  # One object a part, or one an feature: the nodes grouped by the feature record
  # that owns the face each was taken on. A face no feature claimed is the body —
  # the stock a bore is cut into, which a compositional run learns as its own
  # object rather than as part of every feature.
  defp objects_of(nodes, _recognition, object_id, :part),
    do: library_object(nodes, object_id)

  defp objects_of(nodes, recognition, object_id, :features) do
    nodes
    |> Enum.group_by(fn node -> owner_of(recognition, node.face) end)
    |> Enum.sort_by(fn {feature, _nodes} -> to_string(feature) end)
    |> Enum.reduce_while({:ok, []}, fn {feature, group}, {:ok, objects} ->
      case library_object(group, object_name(object_id, feature)) do
        {:ok, [object]} -> {:cont, {:ok, [object | objects]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, objects} -> {:ok, Enum.reverse(objects)}
      error -> error
    end
  end

  # The faces the body owns are one object: `Recognition.owner/2` answers `:body`
  # for the stock and `:unaccounted` for a face nothing explained, and naming both
  # `body` without merging them wrote two records under one object id — the file
  # is keyed by object id, so the second would have replaced the first.
  defp owner_of(recognition, face) do
    case Recognition.owner(recognition, face) do
      feature when is_binary(feature) -> feature
      _body -> :body
    end
  end

  defp object_name(object_id, :body), do: object_id <> "/body"
  defp object_name(object_id, feature), do: object_id <> "/" <> feature

  defp library_object(nodes, object_id) do
    case library(nodes, object_id) do
      {:ok, library} ->
        {:ok,
         [
           %{
             object_id: object_id,
             nodes: Library.size(library),
             families: nodes |> Enum.map(& &1.family) |> Enum.frequencies(),
             records: Library.records(library)
           }
         ]}

      {:error, _reason} = error ->
        error
    end
  end

  defp visit(part, {point, normal, face}, options) do
    recognition = Keyword.fetch!(options, :recognition)

    with {:ok, camera} <- Camera.patch(point, normal, camera_options(options)),
         {:ok, frame} <- Quiddity.frame(part, camera),
         :ok <- sees_surface(frame, options),
         {:ok, message} <- Percept.message(frame, options) do
      {:ok,
       %{
         location: Enum.map(message.location, &(&1 * 1.0)),
         features: Percept.node_features(message),
         face: face,
         family: Recognition.family_of(recognition, face),
         coverage: Frame.coverage(frame)
       }}
    else
      {:error, %Quiddity.Error{}} -> :skipped
      :off_surface -> :skipped
    end
  end

  # The two knobs that decide what a patch sees, in the form the camera crate
  # takes them: how far it stands off the surface, and how wide its field of view
  # is. Both are the run's to name — a memory is a record of what that sensor
  # perceived, and a memory photographed from a different distance or through a
  # different lens is a memory of a different surface.
  defp camera_options(options) do
    [
      distance: Keyword.get(options, :distance, @default_distance),
      fov_x: Keyword.get(options, :fov_x, @default_fov_x)
    ]
  end

  # A visit on a face's edge sees mostly off the part: the centre pixel misses,
  # the surface fit has too little to fit, and the features describe nothing. A
  # surface agent never *is* on an edge — contact keeps it inside the face — so
  # the honest thing is to skip the visit rather than store a node whose pose is
  # undefined and whose location is the far plane.
  defp sees_surface(frame, options) do
    {_point, _normal, face} = Frame.centre(frame)
    enough = Keyword.get(options, :min_coverage, 0.6)

    if face != nil and Frame.coverage(frame) >= enough, do: :ok, else: :off_surface
  end
end
