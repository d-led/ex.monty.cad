defmodule MontyCad.Scene do
  @moduledoc """
  A CAD part as the thing a sensor sees.

  The contract is `Monty.Simulators.Synthetic.Scene`'s — `render/3` answers a
  depth image, a shaded colour image, a semantic mask and the middle pixel — and
  what is behind it is exact geometry: the image is one ray-cast pass over the
  B-rep (`Quiddity.frame/2`), so a depth is where the surface *is* rather than a
  renderer's approximation of it.

  The port's worlds are built from a scene: `Monty.Simulators.Synthetic.Environment`
  steps the kinematics and asks the scene what a sensor sees. A part can
  therefore be the world an episode runs in without a second implementation of
  the world — the agent, the actions and the proprioceptive state are the ported
  ones, and only the picture comes from CAD.

  ## Units

  A part is millimetres — quiddity's unit, and the one a STEP file states — and
  the framework is metres. The conversion is here and nowhere else: `render/3`
  takes a pose in metres and answers depths in metres, so a policy that moves a
  centimetre moves a centimetre of part.

  ## The camera

  Monty's agents see a 90° horizontal field of view, and a sensor looks along its
  own **−z** with depth measured along that axis rather than along the ray. Both
  are the framework's: `DepthTo3DLocations` unprojects with
  `fx = tan(hfov / 2) / zoom`, and that is what a policy steers by.

  A quiddity camera samples pixel *centres* while Monty's transform unprojects
  the *edges* of its grid, so an off-axis pixel is off by up to half a pixel.
  MuJoCo's renderer, which is what the framework's own runs use, has exactly the
  same difference; the port's stand-in scene does not, because it casts its rays
  on the transform's grid.

  ## Colour

  A B-rep has no appearance, so `"rgba"` is *shading*: one light from the upper
  left of the camera. An `"hsv"` feature read from it says how the surface turns,
  not what it is painted, and a part with no colour to perceive is not given an
  invented one.

  A pixel that met nothing answers depth `0.0`, which is what a depth image has
  where the camera saw nothing; an experiment's `MissingToMaxDepth` transform is
  what turns that into the furthest the sensor can see.
  """

  alias Monty.Frameworks.Utils.SpatialArithmetics
  alias Monty.Geometry.Rotation
  alias Quiddity.{Frame, Part}

  @hfov 90.0

  # How far above the part a sensor starts: the reach a surface agent's transform
  # clips at (`DepthTo3DLocations`), so a sensor that starts here sees the part
  # rather than a patch of nothing.
  @default_standoff 0.05

  # A part is millimetres; the framework is metres.
  @millimetres_per_metre 1000.0

  # What the camera sees where it sees nothing: no colour at all.
  @no_colour [0.0, 0.0, 0.0, 1.0]

  # The semantic id the part's pixels carry. One part is one object; the
  # background is 0, as every world in this port answers it.
  @semantic_id 1

  @enforce_keys [:part]
  defstruct [:part, :label]

  @type t :: %__MODULE__{part: Part.t(), label: String.t() | nil}

  @typedoc "What one pixel saw."
  @type observation :: %{
          on_object: boolean(),
          depth: float() | nil,
          rgba: [float()] | nil
        }

  @doc """
  The part at `path` as a scene.

  `:label` is what the part is called — a run's record names what it stepped.
  """
  @spec open(Path.t(), keyword()) :: {:ok, t()} | {:error, Quiddity.Error.t()}
  def open(path, options \\ []) do
    with {:ok, part} <- Quiddity.open(path) do
      {:ok, new(part, Keyword.put_new(options, :label, Path.basename(path)))}
    end
  end

  @doc "A scene of a part already opened."
  @spec new(Part.t(), keyword()) :: t()
  def new(%Part{} = part, options \\ []) do
    %__MODULE__{part: part, label: Keyword.get(options, :label)}
  end

  @doc """
  What a sensor at `pose` sees.

  The options are the ones the port's own scene takes, because they come from
  the experiment's sensor rather than from here: `:resolution` (`{height, width}`
  pixels, a bare integer for a square patch), `:zoom`, and `:hfov` in degrees.
  """
  @spec render(t(), %{position: Rotation.vector(), rotation: Rotation.t()}, keyword()) :: %{
          depth: [[float()]],
          rgba: [[[float()]]],
          semantic: [[float()]],
          centre: observation()
        }
  def render(%__MODULE__{} = scene, %{position: position, rotation: rotation}, options \\ []) do
    {height, width} = resolution(Keyword.get(options, :resolution, 1))
    eye = SpatialArithmetics.scale(position, @millimetres_per_metre)
    forward = Rotation.apply(rotation, [0.0, 0.0, -1.0])

    frame =
      scene.part
      |> Quiddity.frame(camera(eye, rotation, {height, width}, options))
      |> frame!()

    rows = frame |> pixels(eye, forward) |> Enum.chunk_every(width)

    %{
      depth: Enum.map(rows, &Enum.map(&1, fn pixel -> pixel.depth || 0.0 end)),
      rgba: Enum.map(rows, &Enum.map(&1, fn pixel -> pixel.rgba || @no_colour end)),
      semantic:
        Enum.map(rows, fn row ->
          Enum.map(row, fn pixel -> if pixel.on_object, do: 1.0, else: 0.0 end)
        end),
      centre: rows |> Enum.at(div(height, 2)) |> Enum.at(div(width, 2))
    }
  end

  @doc "The middle pixel of a view, as a camera would answer it."
  @spec observe(t(), %{position: Rotation.vector(), rotation: Rotation.t()}) :: observation()
  def observe(%__MODULE__{} = scene, pose), do: render(scene, pose).centre

  @doc """
  The object this episode is about: the part, named.

  A part is not sampled — the run is looking at the one it named — so the answer
  is the part rather than a choice, which is what makes a supervised episode
  possible here: Monty's `PrimaryTarget`, with the pose the part is at (the
  identity, since a STEP file is the world when a part is the world) and the
  rotation an experiment's supervision reads.
  """
  @spec primary_target(t()) :: map()
  def primary_target(%__MODULE__{} = scene) do
    %{
      "object_name" => scene.label,
      "semantic_id" => @semantic_id,
      "position" => Enum.map(Part.centre(scene.part), &(&1 / @millimetres_per_metre)),
      "rotation" => [1.0, 0.0, 0.0, 0.0],
      "euler_rotation" => [0.0, 0.0, 0.0],
      "quat_rotation" => [1.0, 0.0, 0.0, 0.0],
      "scale" => [1.0, 1.0, 1.0]
    }
  end

  @doc "What the id its pixels carry is called, so a log can name the part."
  @spec semantic_id_to_label(t()) :: %{optional(integer()) => String.t()}
  def semantic_id_to_label(%__MODULE__{label: nil}), do: %{}
  def semantic_id_to_label(%__MODULE__{} = scene), do: %{@semantic_id => scene.label}

  @doc """
  Where a sensor starts, standing off the part.

  A config's start pose describes an agent in *its* scene — MuJoCo's, with the
  object where that scene put it — and a part is a different scene: at the
  origin, in millimetres, whichever face happens to be up. So the placement is
  read from the part rather than borrowed from the config: `:standoff` metres
  above its highest point, looking down its own −z, which is where a patch sensor
  can start.

  `:standoff` defaults to five centimetres, the reach a surface agent's transform
  clips at — a sensor that started further away would see the part as one flat
  patch of nothing.
  """
  @spec start_pose(t(), keyword()) :: %{position: Rotation.vector(), rotation: Rotation.t()}
  def start_pose(%__MODULE__{} = scene, options \\ []) do
    standoff = Keyword.get(options, :standoff, @default_standoff)
    {_lowest, highest} = Part.bounds(scene.part)
    [across, along, _height] = Enum.map(Part.centre(scene.part), &(&1 / @millimetres_per_metre))
    [_low_x, _low_y, high_z] = Enum.map(highest, &(&1 / @millimetres_per_metre))

    %{position: [across, along, high_z + standoff], rotation: Rotation.identity()}
  end

  # A pinhole camera where the sensor is and pointing the way it points, in the
  # sensor's own roll: Monty's sensor looks along −z with +y up, so the image is
  # the sensor's frame rather than one chosen for it. The field of view is the
  # transform's own inverse — the framework unprojects with
  # `fx = tan(hfov / 2) / zoom`.
  defp camera(eye, rotation, {height, width}, options) do
    hfov = options |> Keyword.get(:hfov, @hfov) |> radians()
    zoom = Keyword.get(options, :zoom, 1.0)
    forward = Rotation.apply(rotation, [0.0, 0.0, -1.0])

    {:ok, camera} =
      Quiddity.Camera.looking_at(
        eye,
        SpatialArithmetics.add(eye, forward),
        up: Rotation.apply(rotation, [0.0, 1.0, 0.0]),
        width: width,
        height: height,
        fov_x: 2.0 * :math.atan(:math.tan(hfov / 2.0) / zoom),
        # Millimetres: the search has to reach across a machine, not a room.
        far: 100_000.0
      )

    camera
  end

  # Depth is measured along the sensor's axis, not along the ray. The frame
  # answers the point each ray met exactly, so the axis distance is a dot
  # product rather than a correction by the pixel's angle.
  defp pixels(frame, eye, forward) do
    [Frame.points(frame), Frame.face_ids(frame), Frame.rgba(frame)]
    |> Enum.zip_with(fn
      [_point, nil, _shade] ->
        %{on_object: false, depth: nil, rgba: nil}

      [point, _face, shade] ->
        %{
          on_object: true,
          depth:
            SpatialArithmetics.dot(SpatialArithmetics.subtract(point, eye), forward) /
              @millimetres_per_metre,
          rgba: unit(shade)
        }
    end)
  end

  # A camera image's bytes as the port's scene answers colour: 0..1 per channel,
  # which is what `rgb2hsv` reads as a float image.
  defp unit([red, green, blue, alpha]),
    do: [red / 255.0, green / 255.0, blue / 255.0, alpha / 255.0]

  defp frame!({:ok, frame}), do: frame

  defp frame!({:error, error}),
    do: raise("this scene could not be rendered: #{Exception.message(error)}")

  defp resolution({height, width}) when is_integer(height) and is_integer(width),
    do: {height, width}

  defp resolution(size) when is_integer(size) and size > 0, do: {size, size}

  defp radians(degrees), do: degrees * :math.pi() / 180.0
end
