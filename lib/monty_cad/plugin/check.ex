defmodule MontyCad.Plugin.Check do
  @moduledoc """
  Whether the plugins in an application are still what they say they are.

  A plugin is offered to a run as a name and a kind, and then called through the
  callbacks of that kind's behaviour. The compiler already refuses a module that
  skips a callback it claims; what it cannot refuse is a *description* that has
  drifted, because a description is a map. So that is what is checked here, plus
  the callbacks of the kinds whose behaviour this package can name — one list, so
  a test can hold it and CI can fail on it.
  """

  @doc """
  What each callback a kind's behaviour requires.

  Only a motor policy is named here, because it is the kind whose behaviour this
  package depends on by name. A learning module and an experiment are checked for
  their description and nothing more, rather than for a callback list that would
  have to be guessed — a check that guesses is worse than a check that is narrow.
  """
  @spec required(kind :: atom()) :: [atom()]
  def required(:motor_policy), do: [:call, :reset, :state_dict]
  def required(_kind), do: []

  @doc """
  Every problem with one module, or an empty list for a plugin a cluster and a run
  can both use.
  """
  @spec problems(module()) :: [String.t()]
  def problems(module) do
    case Code.ensure_loaded(module) do
      {:module, _} -> description_problems(module) ++ callback_problems(module)
      {:error, reason} -> ["#{inspect(module)} cannot be loaded: #{inspect(reason)}"]
    end
  end

  defp description_problems(module) do
    if function_exported?(module, :describe, 0) do
      case MontyCad.Plugin.conforms?(module.describe()) do
        :ok -> []
        {:error, reason} -> ["#{inspect(module)} describes itself wrongly: #{reason}"]
      end
    else
      ["#{inspect(module)} does not describe itself: it has no describe/0"]
    end
  end

  defp callback_problems(module) do
    kind = kind_of(module)
    exported = module.__info__(:functions)

    for callback <- required(kind), not Enum.any?(exported, &(elem(&1, 0) == callback)) do
      "#{inspect(module)} is a #{kind} but does not export #{callback}/#{arity(callback)}"
    end
  end

  # The arities are the behaviours' own, so the sentence says "call/6" — the number
  # is what a person looking at their code checks first.
  defp arity(:call), do: 6
  defp arity(_callback), do: 1

  defp kind_of(module) do
    if function_exported?(module, :describe, 0) do
      Map.get(module.describe(), "kind", :unknown)
    else
      :undescribed
    end
  end

  @doc """
  The modules of an application that describe themselves as plugins.

  Asked of the application rather than of the file tree: a module that was never
  compiled is not a plugin anybody can call.
  """
  @spec plugins(atom()) :: [module()]
  def plugins(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} -> Enum.filter(modules, &plugin?/1)
      :undefined -> []
    end
  end

  defp plugin?(module) do
    case Code.ensure_loaded(module) do
      {:module, _} -> MontyCad.Plugin in (module.module_info(:attributes)[:behaviour] || [])
      _ -> false
    end
  end
end
