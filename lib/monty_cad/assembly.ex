defmodule MontyCad.Assembly do
  @moduledoc """
  Several parts as one object: the nodes of an assembly, placed in its frame.

  A memory of an assembly is a memory of one object whose geometry came from
  several files. Teaching it is teaching each part and then moving its nodes to
  where the assembly puts them, because a node is not a point: it carries a
  location *and* a feature map whose `pose_vectors` are three directions in the
  frame the sensor reported them in — the surface normal and the two curvature
  directions, nine numbers in that order. Moving a node's location without
  turning those directions, or turning one and not the other, writes a graph that
  says a face looks one way while sitting another.

  The placement is quiddity's own (`Quiddity.parts/1` answers each instance's
  three rows of a 3×4 transform) in the part's *millimetres*, while a node's
  location is in whatever units `MontyCad.Training.nodes/2` was asked for —
  metres by default. The translation is scaled; the rotation is not.
  """

  @type placement :: [[number()]]
  @type visit_node :: %{
          required(:location) => [number()],
          required(:features) => map(),
          optional(atom()) => term()
        }

  @doc """
  Moves each node by `placement`, rotating its location and every pose vector.

  `units` is the node's unit — `:metres`, which a library is written in, or
  `:millimetres` for the part's own frame. The placement is always millimetres,
  as the file reports it.
  """
  @spec place([visit_node()], placement(), :metres | :millimetres) :: [visit_node()]
  def place(nodes, placement, units \\ :metres) do
    {rotation, column} = rotation_and_translation(placement)
    translation = Enum.map(column, &scale(&1, units))

    Enum.map(nodes, fn node ->
      node
      |> Map.put(:location, add(translation, rotate(rotation, Map.fetch!(node, :location))))
      |> Map.update!(:features, &place_features(&1, rotation))
    end)
  end

  # The 3×4 rows a file writes, split into the rotation and the column that
  # places the part's origin.
  defp rotation_and_translation([[_, _, _, _] = a, [_, _, _, _] = b, [_, _, _, _] = c]) do
    {Enum.map([a, b, c], &Enum.take(&1, 3)), Enum.map([a, b, c], &List.last/1)}
  end

  defp place_features(features, rotation) when is_map(features) do
    case Map.fetch(features, "pose_vectors") do
      {:ok, [_, _, _, _, _, _, _, _, _] = flat} ->
        Map.put(features, "pose_vectors", rotate_vectors(flat, rotation))

      _not_three_vectors ->
        features
    end
  end

  defp place_features(features, _rotation), do: features

  # Three vectors of three, in the order the format writes them.
  defp rotate_vectors(flat, rotation) do
    flat
    |> Enum.chunk_every(3)
    |> Enum.flat_map(&rotate(rotation, &1))
  end

  defp rotate(rotation, [x, y, z]), do: Enum.map(rotation, &dot(&1, [x, y, z]))

  defp dot([a, b, c], [x, y, z]), do: a * x + b * y + c * z

  defp add([ax, ay, az], [bx, by, bz]), do: [ax + bx, ay + by, az + bz]

  defp scale(millimetres, :metres), do: millimetres / 1000.0
  defp scale(millimetres, :millimetres), do: millimetres * 1.0
end
