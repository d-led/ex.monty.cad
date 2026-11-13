defmodule MontyCad.Test.Fixtures do
  @moduledoc """
  Plugins to check, one of each kind of drift.

  Compiled into the test build rather than compiled from a string, because what
  `MontyCad.Plugin.Check.plugins/1` reads is an application's module list, and only
  a module that was compiled into the application appears there.
  """

  defmodule GoodPolicy do
    @moduledoc "A motor policy that is everything it claims."
    @behaviour MontyPlugin

    defstruct sensor_id: "sensor_0"

    @impl MontyPlugin
    def describe do
      %{
        "name" => "good_policy",
        "kind" => :motor_policy,
        "version" => "0.1.0",
        "placement" => :owner_only,
        "needs" => [:quiddity]
      }
    end

    def call(policy, _ctx, _observations, _state, _percept, _goal), do: {policy, policy}
    def reset(policy), do: policy
    def state_dict(policy), do: %{sensor_id: policy.sensor_id}
  end

  defmodule PartialPolicy do
    @moduledoc """
    A motor policy whose description says so, and which cannot be called: the
    callback a run needs first is the one it does not export.
    """
    @behaviour MontyPlugin

    defstruct sensor_id: "sensor_0"

    @impl MontyPlugin
    def describe do
      %{
        "name" => "partial_policy",
        "kind" => :motor_policy,
        "version" => "0.1.0",
        "placement" => :anywhere,
        "needs" => []
      }
    end

    def reset(policy), do: policy
    def state_dict(policy), do: %{sensor_id: policy.sensor_id}
  end

  defmodule Unnamed do
    @moduledoc "A plugin whose description forgot the one field a cluster registers."
    @behaviour MontyPlugin

    @impl MontyPlugin
    def describe do
      %{"kind" => :experiment, "version" => "0.1.0", "placement" => :anywhere, "needs" => []}
    end
  end
end
