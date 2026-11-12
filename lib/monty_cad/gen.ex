defmodule MontyCad.Gen do
  @moduledoc """
  The shared half of the code generators: what a plugin is called, where it goes,
  and that what is written is formatted.

  A generator that writes unformatted code teaches the wrong thing on its first
  line, so every source here goes through the formatter before it is written. A
  generator that writes into the wrong namespace is worse: the module would be
  in this package's namespace while the plugin belongs to the application that
  asked for it, so the namespace comes from the project's own `:app`.
  """

  @doc """
  The module a plugin name becomes, in the host application's namespace.

  `follow_chamfers` in an application called `my_agent` is
  `MyAgent.Plugins.FollowChamfers`.
  """
  @spec module_name(String.t()) :: {:ok, module()} | {:error, String.t()}
  def module_name(name) when is_binary(name) do
    if name =~ ~r/\A[a-z][a-z0-9_]*\z/ do
      {:ok, Module.concat([namespace(), "Plugins", Macro.camelize(name)])}
    else
      {:error,
       "`#{name}` is not a plugin name: lowercase words joined by underscores, " <>
         "like `follow_chamfers`"}
    end
  end

  @doc "The module a plugin name becomes, or the reason it is not a name."
  @spec module_name!(String.t()) :: module()
  def module_name!(name) do
    case module_name(name) do
      {:ok, module} -> module
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc "Where the module's source goes."
  @spec file_path(module()) :: Path.t()
  def file_path(module) do
    Path.join([lib(), folder(), Macro.underscore(last(module)) <> ".ex"])
  end

  @doc "Where the module's test goes."
  @spec test_path(module()) :: Path.t()
  def test_path(module) do
    Path.join(["test", folder(), Macro.underscore(last(module)) <> "_test.exs"])
  end

  @doc "The application this generation is for, as a module prefix."
  @spec namespace() :: String.t()
  def namespace, do: Mix.Project.config()[:app] |> to_string() |> Macro.camelize()

  @doc """
  Writes the files a generator made, and answers the paths it wrote.

  An existing file is refused rather than overwritten: a generator run a second
  time by mistake would otherwise take the decisions the first run's owner has
  since written into it.
  """
  @spec write!([{Path.t(), String.t()}]) :: [Path.t()]
  def write!(files) do
    for {path, source} <- files do
      if File.exists?(path) do
        Mix.raise("#{path} is already there; nothing was written")
      end

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, format(source))
      path
    end
  end

  @doc "One source as the formatter leaves it."
  @spec format(String.t()) :: String.t()
  def format(source), do: source |> Code.format_string!() |> IO.iodata_to_binary()

  defp lib, do: "lib"
  defp folder, do: Macro.underscore(namespace())

  defp last(module), do: module |> Module.split() |> List.last()
end
