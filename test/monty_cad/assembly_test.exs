defmodule MontyCad.AssemblyTest do
  use ExUnit.Case, async: true

  alias MontyCad.Assembly

  # A node as a visit leaves it: a location in metres and three directions.
  defp visited do
    %{
      location: [1.0, 0.0, 0.0],
      features: %{
        "pose_vectors" => [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
        "principal_curvatures_log" => [0.5, 0.2],
        "hsv" => [0.1, 0.0, 0.9]
      },
      face: 3,
      family: "surface"
    }
  end

  # Ninety degrees about z, then the part's origin 10 mm along x.
  @quarter_turn [[0, -1, 0, 10], [1, 0, 0, 0], [0, 0, 1, 0]]

  describe "several meshes as one object" do
    defp triangle(left) do
      %{
        name: "part",
        family: "part",
        vertices: [[left, 0.0, 0.0], [left + 0.01, 0.0, 0.0], [left, 0.01, 0.0]],
        triangles: [[0, 1, 2]],
        colour: [0.7, 0.7, 0.7]
      }
    end

    test "puts every instance's triangles where its placement puts them" do
      right = [[1, 0, 0, 10], [0, 1, 0, 0], [0, 0, 1, 0]]

      merged =
        Assembly.meshes([
          {triangle(0.0), [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]},
          {triangle(0.0), right}
        ])

      assert length(merged.vertices) == 6
      assert merged.triangles == [[0, 1, 2], [3, 4, 5]]
      assert Enum.min(Enum.map(merged.vertices, &hd/1)) == 0.0
      assert_in_delta Enum.max(Enum.map(merged.vertices, &hd/1)), 0.02, 1.0e-9
      assert merged.name == "part"
    end
  end

  describe "a part placed in an assembly frame" do
    test "its nodes move to where the placement puts them" do
      [placed] = Assembly.place([visited()], @quarter_turn)

      assert placed.location == [0.01, 1.0, 0.0]
      assert placed.face == 3
      assert placed.family == "surface"
    end

    test "every direction it carries turns with it, so the face looks the way it sits" do
      [placed] = Assembly.place([visited()], @quarter_turn)

      assert placed.features["pose_vectors"] ==
               [0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
    end

    test "a value that is not a direction is left as the sensor reported it" do
      [placed] = Assembly.place([visited()], @quarter_turn)

      assert placed.features["principal_curvatures_log"] == [0.5, 0.2]
      assert placed.features["hsv"] == [0.1, 0.0, 0.9]
    end

    test "the placement's translation is millimetres and the node's unit decides the scale" do
      [in_millimetres] = Assembly.place([visited()], @quarter_turn, :millimetres)

      assert in_millimetres.location == [10.0, 1.0, 0.0]
    end

    test "a translation alone leaves every direction alone" do
      only_moved = [[1, 0, 0, 5], [0, 1, 0, 0], [0, 0, 1, 0]]

      [placed] = Assembly.place([visited()], only_moved)

      assert placed.location == [1.005, 0.0, 0.0]
      assert placed.features["pose_vectors"] == visited().features["pose_vectors"]
    end
  end
end
