defmodule MontyCad.SolidCraftPartTest do
  @moduledoc """
  A part a CAD program drew, read as the world a run steps through.

  `test/fixtures/solidcraft_sample_plate.step` is an export of SolidCraft's own
  sample plate — MIT OR Apache-2.0, SolidCraft contributors, credited in
  `NOTICE`. What it is here for is that the geometry under the port is not
  geometry a test wrote: it is what a CAD modeller produced, and the features it
  is made of are what a run is scored against.
  """

  use ExUnit.Case, async: true

  alias Monty.Geometry.Rotation
  alias MontyCad.Scene
  alias Quiddity.Recognition

  @fixture "test/fixtures/solidcraft_sample_plate.step"

  setup_all do
    {:ok, part} = Quiddity.open(@fixture)
    {:ok, recognition} = Quiddity.features(part)

    %{recognition: recognition}
  end

  defp holes(recognition), do: Recognition.by_family(recognition, "holes")

  test "the part is made of a plate and bores through it", %{recognition: recognition} do
    families = recognition |> Recognition.families() |> Enum.map(&elem(&1, 0))

    assert "plates" in families
    assert "holes" in families
  end

  test "every bore is a through hole, at its own diameter", %{recognition: recognition} do
    assert recognition
           |> holes()
           |> Enum.map(&{&1["parameters"]["diameter"], &1["parameters"]["bottom"]})
           |> Enum.sort() == [{8.0, "through"}, {8.0, "through"}, {12.0, "through"}]
  end

  # A supervised episode learns stock as well as it learns a bore, which needs a
  # name per feature rather than one name for the lump.
  test "a scene names every face after the feature that owns it" do
    {:ok, scene} = Scene.open(@fixture, labelled: true)

    names = scene |> Scene.semantic_id_to_label() |> Map.values()

    assert "plates/0" in names
    assert "holes/0" in names
    assert "holes/1" in names
  end

  # The part as a surface: a sensor stood over its footprint meets stock at
  # almost every point. It is also the first thing about this part worth knowing —
  # its centre is one of its bores, so a pose read from the bounding box alone
  # looks straight down the hole and meets nothing.
  test "the part is a surface a sensor can see from above" do
    {:ok, scene} = Scene.open(@fixture, labelled: true)
    %{position: [x, y, z]} = Scene.start_pose(scene)

    sightings =
      for dx <- -30..30//10, dy <- -20..20//10 do
        pose = %{
          position: [x + dx / 1000, y + dy / 1000, z],
          rotation: Rotation.identity()
        }

        Scene.observe(scene, pose)
      end

    assert Enum.count(sightings, & &1.on_object) >= 25
  end

  test "and its centre is a bore, so a sensor looking down the middle sees nothing" do
    {:ok, scene} = Scene.open(@fixture, labelled: true)

    assert %{on_object: false, depth: nil} =
             scene |> Scene.start_pose() |> then(&Scene.observe(scene, &1))
  end
end
