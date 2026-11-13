defmodule MontyCad.Policy.FeatureWalk do
  @moduledoc """
  A motor policy that walks a part, from feature to feature.

  Monty's surface policies steer by what a patch reports: the normal, the
  curvature, the places it has already been. This one does not have to guess,
  because it holds the part — `:owner_only`, since a B-rep handle cannot leave
  the node that opened it. Each step it ray-casts from the sensor onto the exact
  surface, keeps the sensor a patch's standoff off it, and steps towards the
  next feature the part's own recognition named: a hole, a boss, a riser's face.
  It is done with one feature when the ray lands on that feature's own faces.

  What it never reads is `observations` or `percept`. That is the comparison it
  exists to make: a policy with the geometry knows where the next feature *is*,
  and a policy with only the patch has to find out. `needs` says so —
  `[:quiddity, :monty]` — and a cluster only calls it where both are carried.

  ## The two frames

  The agent moves in the world, in metres; the part is its own frame, in
  millimetres, and a part that is the world has the two aligned but not the same
  size. So every step converts the sensor's world pose into the part's
  millimetres to look, and answers its actions in metres — which is what the
  world moves by.

  ## What it walks to

  A *target* is a record of the recognition that says where it is
  (`parameters.location`), which is a hole's centre or a boss's; a riser has
  faces but no point, so it is not a destination. The nearest unvisited one is
  chosen each time a target is needed, and a feature the sensor is already over
  counts as visited — an episode that starts on a boss should not walk to it.
  """

  @behaviour MontyPlugin
  @behaviour Monty.Frameworks.Models.MotorPolicies.MotorPolicy

  alias Monty.Frameworks.Actions.{MoveForward, MoveTangentially}
  alias Monty.Frameworks.Models.MotorPolicies.MotorPolicyResult
  alias Monty.Frameworks.Models.MotorSystemState.AgentState
  alias Monty.Geometry.Rotation
  alias Quiddity.{Part, Recognition}

  # A patch sensor stands a few millimetres off the surface it reads: close
  # enough that the surface fills the frame, far enough that it is not in it.
  @default_standoff 5.0

  # How far one step goes, in millimetres. A patch is about five millimetres
  # across at this standoff, so consecutive percepts overlap and the walk does not
  # skip the thing it is walking to.
  @default_step 4.0

  # How near the wanted standoff counts as near enough, in millimetres.
  @reach 1.0

  # Monty measures the world in metres; a part is millimetres.
  @millimetres_per_metre 1000.0

  @enforce_keys [:part, :targets]
  defstruct [
    :part,
    :targets,
    agent_id: "agent_id_0",
    sensor_id: "patch",
    target: nil,
    visited: MapSet.new(),
    walked: 0,
    standoff: @default_standoff,
    step: @default_step
  ]

  @typedoc "A place the walk can go: a feature's id, its faces and its centre."
  @type target :: %{id: String.t(), family: String.t(), faces: [non_neg_integer()], at: [float()]}

  @type t :: %__MODULE__{
          part: Part.t(),
          targets: [target()],
          agent_id: atom() | String.t(),
          sensor_id: atom() | String.t(),
          target: target() | nil,
          visited: MapSet.t(),
          walked: non_neg_integer(),
          standoff: float(),
          step: float()
        }

  @doc """
  A walk over `part`, aiming at the features `recognition` names.

  Options: `:agent_id` and `:sensor_id` (which body this policy moves),
  `:standoff` and `:step` in millimetres, and — as the generator's contract says
  — nothing about the part's file, because the part is already open.
  """
  @spec new(keyword()) :: t()
  def new(options) do
    recognition = Keyword.fetch!(options, :recognition)

    %__MODULE__{
      part: Keyword.fetch!(options, :part),
      targets: places_of(recognition),
      agent_id: Keyword.get(options, :agent_id, "agent_id_0"),
      sensor_id: Keyword.get(options, :sensor_id, "patch"),
      standoff: Keyword.get(options, :standoff, @default_standoff),
      step: Keyword.get(options, :step, @default_step)
    }
  end

  @doc "What a cluster asks about it."
  @impl MontyPlugin
  @spec describe() :: MontyPlugin.description()
  def describe do
    %{
      "name" => "monty_cad.feature_walk",
      "kind" => :motor_policy,
      "version" => version(),
      "placement" => :owner_only,
      "needs" => [:quiddity, :monty]
    }
  end

  @doc """
  One step: keep the standoff, then walk one step towards the target.

  Height first. A sensor that is over a lower face than the one it walked off
  would read nothing, and one pressed into a higher face would read its own
  inside — so the ray's own distance decides, and the correction is a
  `MoveForward` of the difference. Only when the standoff is right does the
  policy move sideways, which is the walking.
  """
  @impl Monty.Frameworks.Models.MotorPolicies.MotorPolicy
  @spec call(t(), Monty.Context.t() | nil, map() | nil, map(), term(), term()) ::
          {MotorPolicyResult.t(), t()}
  def call(%__MODULE__{} = policy, _ctx, _observations, state, _percept, _goal) do
    sensor = sensor_pose(policy, state)
    here = millimetres(sensor.position)
    forward = Rotation.apply(sensor.rotation, [0.0, 0.0, -1.0])

    case hit(policy, here, forward) do
      {:ok, %{"face" => face, "distance" => depth}} ->
        policy |> arrived(face) |> walk(here, depth)

      # A ray that meets nothing is still somewhere the policy knows: a through
      # hole's aperture is empty, and a sensor walking over it is at the hole
      # rather than nowhere. There is no standoff to correct in that case — the
      # target is the only thing that says whether the step has arrived.
      {:miss, _nothing_that_way} ->
        walk(policy, here, nil)
    end
  rescue
    # A policy that fails a step stops the episode with its own words rather than
    # taking the model down with it (`docs/monty-differences.md` §2.9 is the
    # framework's own answer; this is the same idea for a plugin).
    error ->
      {%MotorPolicyResult{
         actions: [],
         status: :ready,
         telemetry: %{error: Exception.message(error), target: policy.target}
       }, policy}
  end

  @doc "A fresh episode forgets which features it has been to."
  @impl Monty.Frameworks.Models.MotorPolicies.MotorPolicy
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = policy), do: %{policy | target: nil, visited: MapSet.new(), walked: 0}

  @doc "What the walk did, for a run that wants to be read afterwards."
  @impl Monty.Frameworks.Models.MotorPolicies.MotorPolicy
  @spec state_dict(t()) :: map()
  def state_dict(%__MODULE__{} = policy) do
    %{
      target: policy.target && policy.target.id,
      visited: MapSet.to_list(policy.visited),
      walked: policy.walked,
      standoff: policy.standoff,
      step: policy.step
    }
  end

  @doc "The places this walk could go."
  @spec places(t()) :: [target()]
  def places(%__MODULE__{targets: targets}), do: targets

  # -- the walk ---------------------------------------------------------------

  # Two actions at most: the height correction, or one sideways step. They are
  # separate steps rather than one because the world applies them in order and a
  # turn taken at the wrong height reads the wrong surface.
  defp walk(policy, here, depth) do
    case target_point(policy) do
      nil -> {result([], %{walked: true, done: true}), policy}
      target -> step(policy, here, depth, target)
    end
  end

  defp step(policy, here, depth, target) do
    error = correction(policy, depth)

    if error == nil do
      walk_beside(policy, here, target)
    else
      action = %MoveForward{agent_id: policy.agent_id, distance: error / @millimetres_per_metre}
      {result([action], %{depth: depth, target: target.id, correcting: error}), policy}
    end
  end

  # How far the standoff is off the wanted one, in millimetres, or `nil` when
  # there is nothing to be a standoff from (a ray that met nothing).
  defp correction(policy, depth) do
    case depth && depth - policy.standoff do
      nil -> nil
      error when abs(error) > @reach -> error
      _close_enough -> nil
    end
  end

  defp walk_beside(policy, here, target) do
    aside = Enum.zip_with([here, target.at], fn [from, to] -> to - from end) |> flatten_z()
    distance = :math.sqrt(dot(aside, aside))

    if distance <= @reach do
      {result([], %{target: target.id, arrived: true}), mark(policy, target.id)}
    else
      action = %MoveTangentially{
        agent_id: policy.agent_id,
        distance: min(policy.step, distance) / @millimetres_per_metre,
        direction: unit(aside)
      }

      {result([action], %{target: target.id, distance: distance}),
       %{policy | walked: policy.walked + 1}}
    end
  end

  # The target this step is walking to: the one already chosen, or the nearest
  # unvisited one, chosen now.
  defp target_point(%__MODULE__{target: %{at: at}} = policy) when is_list(at), do: policy.target

  defp target_point(%__MODULE__{targets: targets, visited: visited}) do
    case Enum.find(targets, &(not MapSet.member?(visited, &1.id))) do
      nil -> nil
      target -> target
    end
  end

  # A face that belongs to the feature the walk is aiming at is the arrival: the
  # recognition maps faces to records, so this is a lookup and not a guess.
  defp arrived(%__MODULE__{target: nil} = policy, _face), do: policy

  defp arrived(%__MODULE__{target: target} = policy, face) do
    if face in target.faces, do: mark(policy, target.id), else: policy
  end

  defp mark(policy, id), do: %{policy | target: nil, visited: MapSet.put(policy.visited, id)}

  # Where the sensor is, in the world, in millimetres, and which way it looks.
  defp sensor_pose(policy, state) do
    state
    |> Map.fetch!(policy.agent_id)
    |> AgentState.sensor_pose(policy.sensor_id)
  end

  defp hit(%__MODULE__{part: part}, origin, forward) do
    case Quiddity.ray(part, origin, forward) do
      {:ok, %{"hits" => [nearest | _rest]}} -> {:ok, nearest}
      {:ok, %{"hits" => []}} -> {:miss, :nothing_that_way}
      {:error, error} -> {:miss, Exception.message(error)}
    end
  end

  # -- what there is to walk to ----------------------------------------------

  # A record the recognition names is a place when it says where it is: a hole's
  # centre, a boss's top. A riser is a family of faces without one, so it is a
  # surface to walk along rather than somewhere to arrive.
  defp places_of(recognition) do
    recognition
    |> Recognition.records()
    |> Enum.flat_map(fn record ->
      case {record["parameters"]["location"], record["faces"]} do
        {[_x, _y, _z] = at, faces} when is_list(faces) ->
          [%{id: record["id"], family: record["family"], faces: faces, at: at}]

        _no_place ->
          []
      end
    end)
  end

  defp result(actions, telemetry) do
    %MotorPolicyResult{actions: actions, status: :ready, telemetry: telemetry}
  end

  defp millimetres(position), do: Enum.map(position, &(&1 * @millimetres_per_metre))

  # Sideways only: the height is the correction's business, and a diagonal step
  # would hide which of the two the world applied.
  defp flatten_z([x, y, _z]), do: [x, y, 0.0]

  # A step towards nowhere is not a direction; anything is as good as another,
  # and x is what a policy that has lost its target would do next.
  defp unit(vector) do
    case :math.sqrt(dot(vector, vector)) do
      length when length == 0.0 -> [1.0, 0.0, 0.0]
      length -> Enum.map(vector, &(&1 / length))
    end
  end

  defp dot(left, right), do: Enum.zip_with([left, right], fn [a, b] -> a * b end) |> Enum.sum()

  defp version do
    case :application.get_key(:ex_monty_cad, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      :undefined -> "unknown"
    end
  end
end
