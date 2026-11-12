defmodule MontyCad.Plugin do
  @moduledoc """
  What a plugin tells a cluster about itself, and what a cluster may rely on.

  A run is assembled from modules: the experiment that drives it, the learning
  modules it steps, the motor policies that decide where to sense next. Not all
  of them live in the same node — a policy that reads a part's B-rep has to run
  where the part was opened — so a cluster has to be able to ask a module what it
  is before it decides where to call it.

  That answer is `describe/0`, and this module is its contract: the three kinds,
  the two placements, and `conforms?/1`, which says what is wrong with a
  description rather than only that something is.

  ## The description

      %{
        "name" => "follow_chamfers",
        "kind" => :motor_policy,
        "version" => "0.1.0",
        "placement" => :owner_only,
        "needs" => [:quiddity]
      }

  * `name` — the name the cluster registers it under, and the name a run asks
    for. Two plugins with one name on one node is a mistake the registry reports.
  * `kind` — one of `kinds/0`: an experiment, a learning module, or a motor
    policy. The kind says how often it is called: an experiment and a policy once
    per step, a learning module thousands of times, which is why a learning
    module is advertised rather than routed.
  * `version` — the plugin's own version string, so a run's record says which
    decision-maker produced it.
  * `placement` — `:anywhere` when any node may answer a call, `:owner_only` when
    a call has to reach the node that holds the state. A B-rep handle cannot
    leave its node, so anything that reads one is `:owner_only`.
  * `needs` — what the plugin must be able to reach to answer at all, as atoms:
    `:quiddity` for the geometry, `:cadmpeg` for the file, `:monty` for the
    framework. A cluster uses it to refuse a plugin it cannot serve rather than
    to fail its first call.

  `mix monty_cad.gen.policy` and `mix monty_cad.gen.transform` write a module that
  implements this behaviour, so a generated plugin is already offerable.
  """

  @type kind :: :experiment | :learning_module | :motor_policy
  @type placement :: :anywhere | :owner_only

  @doc "What a plugin says about itself."
  @callback describe() :: description()

  @typedoc "The map `describe/0` answers."
  @type description :: %{
          required(String.t()) => term(),
          optional(String.t()) => term()
        }

  @kinds [:experiment, :learning_module, :motor_policy]
  @placements [:anywhere, :owner_only]

  @doc "The kinds of plugin a run is assembled from."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Where a plugin may be called: anywhere, or only where its state is."
  @spec placements() :: [placement()]
  def placements, do: @placements

  @doc """
  Whether a description says enough for a cluster to use it.

  `:ok`, or a sentence naming the first thing that is wrong — which is what a
  generated plugin's test asserts, and what a person reads when a hand-written
  one is refused.
  """
  @spec conforms?(description()) :: :ok | {:error, String.t()}
  def conforms?(description) when is_map(description) do
    with :ok <- has(description, "name", &is_binary/1, "a string"),
         :ok <- has(description, "version", &is_binary/1, "a string"),
         :ok <- has(description, "kind", &(&1 in @kinds), "one of #{inspect(@kinds)}"),
         :ok <-
           has(description, "placement", &(&1 in @placements), "one of #{inspect(@placements)}") do
      has(description, "needs", &is_list/1, "a list of atoms")
    end
  end

  def conforms?(description) do
    {:error, "a description is a map, and this is #{inspect(description)}"}
  end

  defp has(description, key, valid?, expected) do
    case Map.fetch(description, key) do
      :error ->
        {:error, "`#{key}` is missing; it is #{expected}"}

      {:ok, value} ->
        if valid?.(value),
          do: :ok,
          else: {:error, "`#{key}` is #{inspect(value)}, and #{expected} is what it has to be"}
    end
  end
end
