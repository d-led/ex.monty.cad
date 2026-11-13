defmodule MontyCad.Inputs do
  @moduledoc """
  Where a part and a memory come from: the directories a run and a tool share.

  Monty's object sets are unpacked under `MONTY_DATA` — a directory per archive
  (`ycb/`, `compositional_objects_1.4_mujoco/`, …) — and a CAD part is the same
  kind of input, so it lives beside them:

      $MONTY_DATA/parts/bracket.step

  A part is therefore addressed by **name**, not by path: `MONTY_CAD_PART=bracket`
  finds `parts/bracket.step` (or `.stp`), and a value that is the path of a file
  which exists is used as it is, for a one-off part that should not have to be
  moved first.

  A memory is the other input, and it lives where the studio reads one:

      $MONTY_LIBRARIES/<release>/<name>.jsonl.gz

  ## Why this is here and not in the studio

  `ex.tbp.monty` and `ex.monty.cad.server` both need the answer, and neither
  depends on the other — the studio asks a plugin host over `:pg`, and the server
  is a host. This package is what both already depend on, so the convention has
  one owner: a rule written twice is a rule that disagrees, and the way it
  disagrees is a run that cannot find the part a tool wrote.

  The data root is `MONTY_DATA` when it is set, and otherwise the same folder the
  studio uses (`<user data>/ex-tbp-monty/data`), so a node with nothing exported
  resolves both to one place.
  """

  @data_variable "MONTY_DATA"
  @libraries_variable "MONTY_LIBRARIES"
  @part_variable "MONTY_CAD_PART"
  @app_folder "ex-tbp-monty"

  @extensions [".step", ".stp"]

  @doc "The root Monty's downloaded sets and this estate's parts live under."
  @spec data_root() :: Path.t()
  def data_root do
    System.get_env(@data_variable) || Path.join(user_data(), "data")
  end

  @doc "The directory a part is named from."
  @spec parts_dir() :: Path.t()
  def parts_dir, do: Path.join(data_root(), "parts")

  @doc """
  The parts in `parts_dir/0`, by file name, sorted.

  Read from the directory rather than kept in a list, so a part an operator put
  there — or a tool wrote there — is offered without a second place to update.
  """
  @spec parts() :: [String.t()]
  def parts do
    parts_dir()
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.filter(&(File.regular?(&1) and Path.extname(&1) in @extensions))
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  @doc """
  The part `MONTY_CAD_PART` names, as a path.

  `{:error, sentence}` rather than a `nil` when there is nothing to open: the
  sentence is what a CLI prints and what a page shows, and a caller that had to
  invent one would invent a different one.
  """
  @spec part_path() :: {:ok, Path.t()} | {:error, String.t()}
  def part_path do
    case System.get_env(@part_variable) do
      nil ->
        {:error,
         "no CAD part is named: `#{@part_variable}` is the name of a part in #{parts_dir()}"}

      named ->
        part_path(named)
    end
  end

  @doc """
  The path of `named`, a part's name in `parts_dir/0` or the path of a file.

  The `.step` and `.stp` extensions are tried when the name has none, because
  naming a part by its stem is what a person does and what a config would.
  """
  @spec part_path(String.t()) :: {:ok, Path.t()} | {:error, String.t()}
  def part_path(named) when is_binary(named) do
    candidates =
      [named, Path.join(parts_dir(), named)] ++
        Enum.map(@extensions, &Path.join(parts_dir(), named <> &1))

    case Enum.find(candidates, &File.regular?/1) do
      nil ->
        {:error, "there is no part #{inspect(named)}: #{parts_dir()} holds #{inspect(parts())}"}

      path ->
        {:ok, Path.expand(path)}
    end
  end

  @doc "The root the studio reads memories from."
  @spec libraries_dir() :: Path.t()
  def libraries_dir do
    System.get_env(@libraries_variable) || Path.join(user_data(), "libraries")
  end

  @doc """
  Where a memory called `name` from release `release` belongs.

  The address the studio loads a library by (`Monty.Studio.Memory`), so a memory
  written here is one a run can name — release and name, because the same name in
  two releases is two different memories.
  """
  @spec library_path(String.t(), String.t()) :: Path.t()
  def library_path(name, release) when is_binary(name) and is_binary(release),
    do: Path.join([libraries_dir(), release, name <> ".jsonl.gz"])

  # The same folder the studio names, because a package cannot depend on the
  # studio: `Monty.Paths.root/0` is `:filename.basedir(:user_data, "ex-tbp-monty")`.
  defp user_data, do: :filename.basedir(:user_data, @app_folder)
end
