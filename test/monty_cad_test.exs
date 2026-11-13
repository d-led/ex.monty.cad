defmodule MontyCadTest do
  @moduledoc """
  The bridge to the framework: the observations a frame becomes, the percept the framework's own
  processor fits, and the graph memory a run loads.

  The library format is the contract that matters — `Monty.Studio.Memory` reads it
  back — so one test writes a library and reads it with the format's own rules.
  """

  use ExUnit.Case, async: true

  alias MontyCad.{Library, Percept, Training}
  alias Quiddity.Camera

  @fixture "test/fixtures/golden_simple_through_hole.step"
  @boss_top [15.0, 0.0, 13.0]

  setup_all do
    {:ok, part} = Quiddity.open(@fixture)
    %{part: part}
  end

  defp patch(part, point \\ @boss_top, normal \\ [0.0, 0.0, 1.0]) do
    {:ok, camera} = Camera.patch(point, normal, distance: 5.0)
    Quiddity.frame(part, camera)
  end

  describe "the observation a frame becomes" do
    test "is shaped as the sensor modules read it", %{part: part} do
      {:ok, frame} = patch(part)
      observation = Percept.observation(frame)

      assert length(observation["semantic_3d"]) == frame.width * frame.height
      assert [x, y, z, id] = hd(observation["semantic_3d"])
      assert is_float(x) and is_float(y) and is_float(z)
      assert id in [0.0, 1.0]

      # An image is rows of pixels, not a flat list.
      assert length(observation["rgba"]) == frame.height
      assert length(hd(observation["rgba"])) == frame.width
      assert length(hd(hd(observation["rgba"]))) == 4

      # Four rows of four: a basis, and the homogeneous row that ends it.
      assert [[_, _, _, _], _second, _third, bottom] = observation["cam_to_world"]
      assert bottom == [0.0, 0.0, 0.0, 1.0]
    end

    test "a background pixel carries the framework's background, not a face number", %{part: part} do
      {:ok, camera} = Camera.looking_at([0.0, 0.0, 200.0], [0.0, 0.0, 400.0])
      {:ok, frame} = Quiddity.frame(part, camera)

      assert Enum.all?(Percept.observation(frame)["semantic_3d"], &(List.last(&1) == 0.0))
    end
  end

  describe "the percept" do
    test "is the framework's own processor's answer, and it is a node's worth of features", %{
      part: part
    } do
      {:ok, frame} = patch(part)
      {:ok, message} = Percept.message(frame)
      features = Percept.node_features(message)

      # The location is the middle pixel, which is within a pixel of the spot the
      # sensor was put on — a pixel is a patch of surface, not a point.
      assert_in_delta 0.0,
                      distance(message.location, @boss_top),
                      Camera.pixel_size(frame.camera, 5.0)

      assert features["on_object"] == 1.0
      assert features["object_coverage"] == 1.0
      # Nine numbers, flat, in the order Monty's own export writes them
      # (`n0,n1,n2, c0,c1,c2, k0,k1,k2`): a graph column holds numbers, and the
      # framework's reader chunks one by three to get the three vectors. Nested
      # rows here made every value a level deeper than the reader assumed, and a
      # run died in burst sampling with `[[matrix]]`.
      assert [n0, n1, n2, c0, c1, c2, k0, k1, k2] = features["pose_vectors"]
      assert_in_delta 1.0, length_of([n0, n1, n2]), 1.0e-9
      assert_in_delta 1.0, length_of([c0, c1, c2]), 1.0e-9
      assert_in_delta 1.0, length_of([k0, k1, k2]), 1.0e-9

      assert [normal, curvature_1, curvature_2] =
               Enum.chunk_every(features["pose_vectors"], 3)

      assert_in_delta 1.0, length_of(normal), 1.0e-9
      assert_in_delta 1.0, length_of(curvature_1), 1.0e-9
      assert_in_delta 1.0, length_of(curvature_2), 1.0e-9
      # A flat patch reads flat.
      assert_in_delta 0.0, features["principal_curvatures_log"] |> Enum.at(0), 0.1
      assert is_integer(message.semantic_id) or is_nil(message.semantic_id)
      assert message.sender_id == "patch"
    end

    test "a frame that met nothing still makes a percept, and it says so", %{part: part} do
      {:ok, camera} = Camera.looking_at([0.0, 0.0, 200.0], [0.0, 0.0, 400.0])
      {:ok, frame} = Quiddity.frame(part, camera)

      assert {:ok, message} = Percept.message(frame)
      assert Percept.node_features(message)["on_object"] == 0.0
      refute message.process_features_in_lm
    end
  end

  describe "training from a part" do
    test "visits land on the surface, and each node says which feature it is on", %{part: part} do
      {:ok, %{nodes: nodes} = visits} = Training.nodes(part, spacing: 14.0, limit: 24)

      assert visits.visited == 24
      assert length(nodes) <= visits.visited
      assert visits.skipped == visits.visited - length(nodes)
      assert nodes != []

      for node <- nodes do
        # A library is in the framework's metres and a part is in millimetres, so
        # the lookup converts back: that conversion is the whole of the
        # difference the units decision makes.
        assert {:ok, %{"nearest" => [%{"distance" => away} | _rest]}} =
                 Quiddity.nearest(part, Enum.map(node.location, &(&1 * 1000.0)))

        assert_in_delta 0.0, away, 1.0e-3

        assert is_integer(node.face)
        assert node.features["pose_vectors"] != nil
        assert node.family in [nil, "holes", "bosses", "risers"]
      end
    end

    test "a library from a part is in the run's metres, not the part's millimetres", %{part: part} do
      {:ok, %{nodes: nodes}} = Training.nodes(part, spacing: 14.0, limit: 8)
      {low_mm, high_mm} = Quiddity.Part.bounds(part)
      low = Enum.map(low_mm, &(&1 / 1000.0))
      high = Enum.map(high_mm, &(&1 / 1000.0))

      for node <- nodes,
          {coordinate, {low, high}} <- Enum.zip(node.location, Enum.zip(low, high)) do
        assert coordinate >= low and coordinate <= high,
               "expected #{inspect(node.location)} to be a point of the part in metres"
      end
    end

    test "a coarser spacing visits less often", %{part: part} do
      {:ok, dense} = Training.nodes(part, spacing: 12.0, limit: 500)
      {:ok, sparse} = Training.nodes(part, spacing: 40.0, limit: 500)

      assert dense.visited > sparse.visited
      assert length(dense.nodes) > length(sparse.nodes)
    end

    test "a visit whose patch misses the surface is skipped, not stored", %{part: part} do
      # A coverage nothing can satisfy: every visit fails the rule, and the
      # answer says they were visits rather than nodes.
      {:ok, %{nodes: nodes, visited: visited, skipped: skipped}} =
        Training.nodes(part, spacing: 10.0, limit: 5, min_coverage: 1.01)

      assert nodes == []
      assert visited == 5
      assert skipped == 5
    end

    test "an edge visit is skipped rather than stored with no pose", %{part: part} do
      {:ok, %{nodes: nodes, skipped: skipped}} = Training.nodes(part, spacing: 3.0, limit: 400)

      assert skipped > 0
      assert Enum.all?(nodes, &(&1.coverage >= 0.6))
    end
  end

  describe "the library a run loads" do
    test "holds one column per feature, as long as its node list", %{part: part} do
      {:ok, %{nodes: nodes}} = Training.nodes(part, spacing: 14.0, limit: 12)
      {:ok, library} = Training.library(nodes, "through_hole_plate")

      assert Library.size(library) == length(nodes)
      assert "pose_vectors" in Library.feature_names(library)

      for {_name, column} <- library.features do
        assert length(column) == length(nodes)
      end
    end

    test "refuses a library whose columns and nodes disagree" do
      assert {:error, %Quiddity.Error{code: "bad_request", message: message}} =
               Library.new("part", [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]], [
                 %{"hsv" => [0.0, 0.0, 0.0]}
               ])

      assert message =~ "2 locations but 1 nodes' features"
    end

    test "refuses a location that is not three numbers" do
      assert {:error, %Quiddity.Error{code: "bad_request"}} =
               Library.new("part", [[0.0, 1.0]], [%{"hsv" => [0.0, 0.0, 0.0]}])
    end

    @tag :tmp_dir
    test "writes the format the studio reads back", %{part: part, tmp_dir: dir} do
      path = Path.join(dir, "through_hole_plate.jsonl.gz")
      {:ok, written} = Training.write(part, "through_hole_plate", path, spacing: 14.0, limit: 12)

      assert written.nodes > 0
      assert written.source_sha256 == part.summary["sha256"]
      assert File.exists?(path)

      # Read it the way `Monty.Studio.Memory` does: gunzip, one JSON record a
      # line, positions and feature columns of the same length.
      [record] =
        path
        |> File.read!()
        |> :zlib.gunzip()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert record["object_id"] == "through_hole_plate"
      assert record["input_channel"] == "patch"
      assert record["lm_index"] == 0
      assert length(record["positions"]) == written.nodes

      positions = record["positions"]
      features = record["features"]

      assert Enum.all?(positions, &(length(&1) == 3))
      assert Enum.all?(features, fn {_name, column} -> length(column) == length(positions) end)

      # The names a memory matches on are present, and each node's pose is nine
      # numbers — the flat form Monty's own export writes, and the one the
      # framework's reader chunks by three to get the three vectors.
      for name <- ["pose_vectors", "pose_fully_defined", "principal_curvatures_log"] do
        assert Map.has_key?(features, name)
      end

      assert Enum.all?(features["pose_vectors"], &(length(&1) == 9))
      assert Enum.all?(features["pose_vectors"], &(length(Enum.chunk_every(&1, 3)) == 3))
    end
  end

  describe "a memory of several parts" do
    test "samples a part by its own size, with a floor at what the detail needs", %{part: part} do
      # The fixture is 60 mm across, and thirty visits across 60 mm is the 2 mm
      # a single part has always been written with: the rule and the old dial
      # agree there, which is why every single-part measurement still stands.
      assert Training.spacing(part) == 2.0

      # Smaller still is sampled no finer: a floor, because a small part's
      # detail does not need more visits and every visit is a fitted patch.
      assert Training.spacing(with_extent(part, 40.0)) == 2.0

      # Five times the size is five times the spacing, so the memory holds about
      # as many nodes as the small one's — two parts are comparable, rather than
      # one of them being the denser graph.
      assert Training.spacing(with_extent(part, 300.0)) == 10.0
    end

    @tag :tmp_dir
    test "writes one record per part into the one file a run loads", %{tmp_dir: dir} do
      path = Path.join(dir, "memory.jsonl.gz")

      assert {:ok, written} =
               Training.write_library(
                 [{"plate", @fixture}, {"plate_again", @fixture}],
                 path,
                 spacing: 14.0,
                 limit: 12
               )

      assert written.path == path
      assert Enum.map(written.objects, & &1.object_id) == ["plate", "plate_again"]
      assert written.nodes == written.objects |> Enum.map(& &1.nodes) |> Enum.sum()

      # A forced spacing is what every part gets, which is how a memory written
      # before the rule can be reproduced.
      assert Enum.all?(written.objects, &(&1.spacing == 14.0))

      records =
        path
        |> File.read!()
        |> :zlib.gunzip()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert Enum.map(records, & &1["object_id"]) == ["plate", "plate_again"]
      assert Enum.all?(records, &(&1["input_channel"] == "patch"))
    end

    @tag :tmp_dir
    test "each part is sampled by the rule when no spacing is named", %{tmp_dir: dir} do
      path = Path.join(dir, "memory.jsonl.gz")

      assert {:ok, written} = Training.write_library([{"plate", @fixture}], path, limit: 60)

      assert [%{object_id: "plate", spacing: 2.0}] = written.objects
    end

    test "a part that cannot be opened is an error, not a shorter memory" do
      assert {:error, %Quiddity.Error{}} =
               Training.write_library([{"missing", "/nope/missing.step"}], "/tmp/never.jsonl.gz")
    end
  end

  defp with_extent(part, largest) do
    %{part | summary: Map.put(part.summary, "extent", [largest, largest / 1.2, largest / 3])}
  end

  defp distance([ax, ay, az], [bx, by, bz]) do
    :math.sqrt((ax - bx) ** 2 + (ay - by) ** 2 + (az - bz) ** 2)
  end

  defp length_of([x, y, z]), do: :math.sqrt(x * x + y * y + z * z)
end
