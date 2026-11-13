defmodule MontyCad.Policy.FeatureWalkTest do
  @moduledoc """
  The walk, stepped against the part.

  No world and no model: the policy is asked for its actions and the port's
  kinematics applies them, so a case can say "it walked from where it was to the
  hole, and then to the boss" without a run around it.
  """

  use ExUnit.Case, async: true

  alias Monty.Frameworks.Actions.MoveTangentially
  alias Monty.Frameworks.Models.MotorSystemState.{AgentState, SensorState}
  alias Monty.Geometry.Rotation
  alias Monty.Simulators.Synthetic.Kinematics
  alias MontyCad.Policy.FeatureWalk
  alias MontyCad.Scene

  @agent "agent_id_0"
  @sensor "patch"
  @fixture "test/fixtures/golden_simple_through_hole.step"

  setup_all do
    {:ok, part} = Quiddity.open(@fixture)
    {:ok, recognition} = Quiddity.features(part)
    {:ok, scene} = Scene.open(@fixture)
    %{part: part, recognition: recognition, scene: scene}
  end

  test "describes itself as a policy only a node with the geometry can serve" do
    assert :ok = MontyPlugin.conforms?(FeatureWalk.describe())
    assert %{"kind" => :motor_policy, "placement" => :owner_only} = FeatureWalk.describe()
    assert FeatureWalk.describe()["needs"] == [:quiddity, :monty]
  end

  test "knows the places it could go, and only the ones a part can point at", %{
    part: part,
    recognition: recognition
  } do
    policy = FeatureWalk.new(part: part, recognition: recognition)

    places = FeatureWalk.places(policy)

    assert Enum.map(places, & &1.id) |> Enum.sort() == ["bosses/0", "holes/0"]
    assert Enum.all?(places, fn place -> length(place.at) == 3 and place.faces != [] end)
  end

  test "walks to every feature the part names, one step at a time", %{
    part: part,
    recognition: recognition,
    scene: scene
  } do
    policy = FeatureWalk.new(part: part, recognition: recognition)
    {policy, _world, _decisions} = walk(part, policy, scene, 400)

    assert policy.visited == MapSet.new(["bosses/0", "holes/0"])
    assert policy.target == nil
    assert policy.walked > 0
  end

  # The order of the two decisions is the policy's whole shape: correct the
  # height, and only then walk. A sideways step taken from the wrong height
  # reads a surface that is not under the sensor, and the percept would be of
  # something the agent is not on.
  test "never walks sideways from the wrong height", %{
    part: part,
    recognition: recognition,
    scene: scene
  } do
    policy = FeatureWalk.new(part: part, recognition: recognition)
    {_policy, _world, decisions} = walk(part, policy, scene, 400)

    sideways =
      Enum.filter(decisions, fn %{actions: actions} ->
        Enum.any?(actions, &match?(%MoveTangentially{}, &1))
      end)

    on_surface = Enum.map(Enum.reject(sideways, &(&1.depth == nil)), & &1.depth)

    assert on_surface != []

    for depth <- on_surface do
      assert_in_delta depth, policy.standoff, 1.0
    end

    # And a hole's aperture is empty: over one the ray says nothing, and the
    # policy walks on rather than stopping there — that is how it crosses a hole
    # to reach what is on the other side.
    assert Enum.any?(sideways, &(&1.depth == nil))
  end

  test "a fresh episode forgets where it has been", %{part: part, recognition: recognition} do
    policy = FeatureWalk.new(part: part, recognition: recognition)
    visited = %{policy | visited: MapSet.new(["bosses/0"]), target: %{id: "bosses/0"}, walked: 12}

    fresh = FeatureWalk.reset(visited)

    assert fresh.visited == MapSet.new()
    assert fresh.target == nil
    assert fresh.walked == 0
    assert FeatureWalk.state_dict(fresh).visited == []
  end

  # The policy and the world take turns: one decision, then the kinematics
  # applies it, which is the same order a run uses. Each decision is kept beside
  # the depth the *test* measured under the sensor before it, so a case can hold
  # the policy to the part rather than to its own account.
  defp walk(part, policy, scene, steps) do
    start = Scene.start_pose(scene)

    world =
      Kinematics.new([@sensor],
        agent: start,
        sensors: %{@sensor => %{position: [0.0, 0.0, 0.0], rotation: start.rotation}}
      )

    {policy, world, decisions} =
      Enum.reduce(1..steps, {policy, world, []}, fn _step, {policy, world, decisions} ->
        depth = depth_under(part, world)

        {%{actions: actions}, policy} =
          FeatureWalk.call(policy, nil, nil, state_of(world), nil, nil)

        {policy, Kinematics.step(world, actions), [%{depth: depth, actions: actions} | decisions]}
      end)

    {policy, world, Enum.reverse(decisions)}
  end

  # What a ray from the sensor meets: the part's own answer, in millimetres.
  defp depth_under(part, world) do
    sensor = sensor_pose(world)
    forward = Rotation.apply(sensor.rotation, [0.0, 0.0, -1.0])

    case Quiddity.ray(part, millimetres(sensor.position), forward) do
      {:ok, %{"hits" => [%{"distance" => depth} | _rest]}} -> depth
      _nothing_that_way -> nil
    end
  end

  defp state_of(world) do
    %{
      @agent => %AgentState{
        position: world.agent.position,
        rotation: world.agent.rotation,
        sensors:
          Map.new(world.sensors, fn {id, pose} ->
            {id, %SensorState{position: pose.position, rotation: pose.rotation}}
          end)
      }
    }
  end

  defp sensor_pose(world) do
    state_of(world) |> Map.fetch!(@agent) |> AgentState.sensor_pose(@sensor)
  end

  defp millimetres(position), do: Enum.map(position, &(&1 * 1000.0))
end
