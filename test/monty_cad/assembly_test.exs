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
