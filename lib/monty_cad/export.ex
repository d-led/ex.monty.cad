defmodule MontyCad.Export do
  @moduledoc """
  A part's features as meshes: the triangles of each feature's own faces.

  A physics world steps meshes, so an evaluation in one cannot use the exact
  B-rep a training run in the CAD world ray casts. What it can use is *the same
  surface*, tessellated: `Quiddity.mesh/2` answers which face every triangle came
  from, and the recognition says which feature each face belongs to, so a
  feature's mesh is the triangles whose face the recognition assigned to it. No
  re-meshing, so nothing for the evaluation to disagree about.

  The answer is plain data, in metres, and it says nothing about files: a world
  has its own object format, and writing it is that world's business.
  `MontyCad.Scene` is the exact-world side of the same part; this is the meshed
  side.

  ## One colour, on purpose

  Every mesh is one neutral grey. A colour per feature would put the answer into
  the pixels — a sensor reading `hsv` would recognise a bore by the colour
  somebody chose for bores — so there is one colour for all of them, and a run
  comparing features should not ask for `hsv` at all.
  """

  alias Quiddity.{Part, Recognition}

  @millimetres_per_metre 1000.0

  # A feature is a tessellation of exact faces, so a fine deflection is cheap and
  # a coarse one is a different shape. A hundredth of a millimetre is below what
  # a sensor's patch can resolve at its standoff.
  @default_deflection 0.01

  @body "body"

  @type mesh :: %{
          name: String.t(),
          family: String.t(),
          vertices: [[float()]],
          triangles: [[non_neg_integer()]],
          colour: {float(), float(), float()}
        }

  @doc """
  The part's features as meshes, and the body between them, in metres.

  Mesh names are the recognition's own — `"bosses/0"`, `"holes/0"` — and every
  face no feature claims goes into one mesh called `"body"`, whatever the reason
  it went unclaimed: `:body`, `:refused` or `:unexplained`. A name per reason
  would make the answer depend on why quiddity said no.
  """
  @spec feature_meshes(Part.t() | Path.t(), keyword()) :: {:ok, [mesh()]} | {:error, term()}
  def feature_meshes(part_or_path, options \\ [])

  def feature_meshes(path, options) when is_binary(path) do
    with {:ok, part} <- Quiddity.open(path), do: feature_meshes(part, options)
  end

  def feature_meshes(%Part{} = part, options) do
    deflection = Keyword.get(options, :deflection, @default_deflection)

    with {:ok, recognition} <- Quiddity.features(part),
         {:ok, mesh} <- Quiddity.mesh(part, deflection: deflection) do
      {:ok, meshes(recognition, mesh)}
    end
  end

  defp meshes(recognition, mesh) do
    mesh.triangles
    |> Enum.with_index()
    |> Enum.group_by(
      fn {_triangle, index} ->
        recognition
        |> Recognition.owner(Enum.at(mesh.face_of_triangle, index))
        |> named()
      end,
      fn {triangle, _index} -> triangle end
    )
    |> Enum.map(fn {name, triangles} -> one(name, triangles, mesh.points) end)
    |> Enum.sort_by(& &1.name)
  end

  defp named(owner) when is_binary(owner), do: owner
  defp named(_unclaimed), do: @body

  defp one(name, triangles, points) do
    indexes = triangles |> List.flatten() |> Enum.uniq() |> Enum.sort()
    place = indexes |> Enum.with_index() |> Map.new()

    %{
      name: name,
      family: family(name),
      vertices: Enum.map(indexes, fn index -> in_metres(Enum.at(points, index)) end),
      triangles:
        Enum.map(triangles, fn [a, b, c] ->
          [Map.fetch!(place, a), Map.fetch!(place, b), Map.fetch!(place, c)]
        end),
      colour: {0.72, 0.72, 0.75}
    }
  end

  defp family(@body), do: @body
  defp family(name) when is_binary(name), do: name |> String.split("/") |> hd()

  defp in_metres([x, y, z]) do
    [x / @millimetres_per_metre, y / @millimetres_per_metre, z / @millimetres_per_metre]
  end
end
