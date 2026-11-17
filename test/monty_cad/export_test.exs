defmodule MontyCad.ExportTest do
  @moduledoc """
  A part's features as meshes.

  The cases are about the join the evaluation depends on: each mesh holds the
  triangles of one feature's own faces, in metres, and the body holds the rest.
  """

  use ExUnit.Case, async: true

  alias MontyCad.Export

  @fixture "test/fixtures/golden_simple_through_hole.step"

  setup_all do
    {:ok, meshes} = Export.feature_meshes(@fixture)
    %{meshes: meshes}
  end

  test "one mesh per feature the recognition named, and one for the body", %{meshes: meshes} do
    assert Enum.map(meshes, & &1.name) == ["body", "bosses/0", "holes/0", "risers/0"]
  end

  test "a feature's family is its record's own word", %{meshes: meshes} do
    boss = Enum.find(meshes, &(&1.name == "bosses/0"))

    assert boss.family == "bosses"
    assert Enum.find(meshes, &(&1.name == "body")).family == "body"
  end

  test "the vertices are in metres, and every triangle indexes them", %{meshes: meshes} do
    for mesh <- meshes, vertex <- mesh.vertices do
      assert Enum.all?(vertex, &(abs(&1) < 1.0)), "expected metres, got #{inspect(vertex)}"
    end

    for mesh <- meshes, triangle <- mesh.triangles, index <- triangle do
      assert index < length(mesh.vertices)
    end
  end

  test "a feature is a part of the part, not another mesh of it", %{meshes: meshes} do
    total =
      meshes
      |> Enum.map(&length(&1.triangles))
      |> Enum.sum()

    {:ok, part} = Quiddity.open(@fixture)
    {:ok, whole} = Quiddity.mesh(part, deflection: 0.01)

    # Every triangle of the part is in exactly one mesh: the features and the
    # body partition the surface rather than covering it twice.
    assert total == length(whole.triangles)
  end
end
