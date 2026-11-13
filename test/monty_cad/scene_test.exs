defmodule MontyCad.SceneTest do
  @moduledoc """
  A part as a world's scene.

  The contract under test is the one a world answers through
  (`Monty.Simulators.Synthetic.Environment` asks a scene `render/3`), so the
  cases are about what a sensor sees of a part: a distance in metres along the
  sensor's own axis, a colour where it met something, and nothing where it did
  not.
  """

  use ExUnit.Case, async: true

  alias Monty.Geometry.Rotation
  alias Monty.Simulators.Synthetic.Environment
  alias MontyCad.Scene

  @fixture "test/fixtures/golden_simple_through_hole.step"

  # The fixture is a plate with a boss; the boss's top face is at z = 13 mm and
  # its centre is [15.0, 0.0, 13.0] mm. A sensor 60 mm above the part, looking
  # down its own −z, is therefore 47 mm off that face.
  @boss_centre_mm [15.0, 0.0, 13.0]
  @boss_top_depth_m 0.047

  setup_all do
    {:ok, scene} = Scene.open(@fixture)
    %{scene: scene}
  end

  defp over_the_boss(z \\ 0.06) do
    [x, y, _z] = Enum.map(@boss_centre_mm, &(&1 / 1000.0))
    %{position: [x, y, z], rotation: Rotation.identity()}
  end

  describe "what a sensor sees" do
    test "a depth is the distance along the sensor's axis, in metres", %{scene: scene} do
      assert_in_delta Scene.observe(scene, over_the_boss()).depth, @boss_top_depth_m, 1.0e-9
    end

    test "the middle pixel is on the part when the sensor is over it", %{scene: scene} do
      assert %{on_object: true} = Scene.observe(scene, over_the_boss())
    end

    test "a sensor looking away from the part sees nothing at all", %{scene: scene} do
      image =
        Scene.render(scene, %{over_the_boss() | position: [0.015, 0.0, -0.06]}, resolution: 8)

      assert image.centre.on_object == false
      assert Enum.all?(List.flatten(image.depth), &(&1 == 0.0))
      assert Enum.all?(List.flatten(image.semantic), &(&1 == 0.0))
    end

    test "a pixel that met nothing has no colour", %{scene: scene} do
      image = Scene.render(scene, over_the_boss(), resolution: 16)

      assert image.centre.rgba != [0.0, 0.0, 0.0, 1.0]
      assert hd(hd(image.rgba)) == [0.0, 0.0, 0.0, 1.0]
    end

    test "the mask agrees with the depths: the part and nothing else", %{scene: scene} do
      image = Scene.render(scene, over_the_boss(), resolution: 16)

      on_part =
        for {row_depth, row_mask} <- Enum.zip(image.depth, image.semantic),
            {depth, mask} <- Enum.zip(row_depth, row_mask),
            depth > 0.0,
            do: mask

      assert on_part != []
      assert Enum.all?(on_part, &(&1 == 1.0))
    end
  end

  describe "what the scene says it shows" do
    test "the part, named, as the target a supervised episode scores against", %{scene: scene} do
      target = Scene.primary_target(scene)

      {low_mm, high_mm} = Quiddity.Part.bounds(scene.part)
      low = Enum.map(low_mm, &(&1 / 1000.0))
      high = Enum.map(high_mm, &(&1 / 1000.0))

      assert target["object_name"] == "golden_simple_through_hole.step"
      assert target["semantic_id"] == 1

      assert Enum.zip(target["position"], Enum.zip(low, high))
             |> Enum.all?(fn {coordinate, {low, high}} ->
               coordinate >= low and coordinate <= high
             end),
             "expected the target to be somewhere on the part, in metres"
    end

    test "the id its pixels carry, so a log can name the part", %{scene: scene} do
      assert Scene.semantic_id_to_label(scene) == %{1 => "golden_simple_through_hole.step"}
    end
  end

  describe "a part as a world's scene" do
    test "the port's world steps it and answers the part it saw", %{scene: scene} do
      # An odd count, so that a pixel sits on the sensor's axis: Monty's grid puts
      # the ends of the image at the ends of `linspace(-1, 1, n)`, so an even
      # count has no centre pixel at all.
      environment =
        Environment.new(["patch"], scene,
          views: %{"patch" => [resolution: 9]},
          agent: over_the_boss(),
          sensors: %{"patch" => %{position: [0.0, 0.0, 0.0], rotation: Rotation.identity()}}
        )

      {observations, _proprioceptive_state, _environment} = Environment.step(environment, [])

      patch = observations[Environment.agent_id()]["patch"]

      assert patch["depth"] |> List.flatten() |> Enum.any?(&(&1 == 0.0))

      centre = div(9, 2)

      assert_in_delta patch["depth"] |> Enum.at(centre) |> Enum.at(centre),
                      @boss_top_depth_m,
                      1.0e-9

      assert patch["semantic"] |> Enum.at(centre) |> Enum.at(centre) == 1.0
    end
  end
end
