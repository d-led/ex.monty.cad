defmodule MontyCad.GenTest do
  @moduledoc """
  What a generator promises: the code it writes compiles, says what it is, and is
  the contract it claims to be rather than a plausible-looking stub.

  The generated source is compiled here rather than written and read back, because
  the promise is about the code, not about the file: a template that produces
  valid Elixir in the wrong namespace, or a module that does not describe itself,
  fails here.
  """

  use ExUnit.Case, async: false

  alias MontyCad.Gen

  @policy "generated_probe_policy"
  @transform "generated_probe_transform"

  setup_all do
    policy = compile(Gen.Policy.source(Gen.module_name!(@policy)))
    {:ok, policy: policy}
  end

  describe "a generated policy" do
    test "describes itself the way a cluster asks", %{policy: policy} do
      assert :ok = MontyCad.Plugin.conforms?(policy.describe())
    end

    test "is a motor policy that has to run where its part is", %{policy: policy} do
      description = policy.describe()

      assert description["name"] == @policy
      assert description["kind"] == :motor_policy
      assert description["placement"] == :owner_only
      assert :quiddity in description["needs"]
    end

    test "forgets what it learned between episodes", %{policy: policy} do
      specimen = struct(policy)

      assert policy.reset(specimen) == specimen
      assert policy.state_dict(specimen) == %{sensor_id: "sensor_0"}
    end

    test "has no decision yet, and says so instead of guessing", %{policy: policy} do
      assert_raise RuntimeError, ~r/has not decided anything yet/, fn ->
        policy.call(struct(policy), nil, nil, nil, nil, nil)
      end
    end
  end

  describe "a generated transform" do
    test "is a sensor transform, and has no stage yet" do
      module = compile(Gen.Transform.source(Gen.module_name!(@transform)))
      behaviours = module.module_info(:attributes)[:behaviour] || []

      assert Monty.SensorModules.SensorModule.Transform in behaviours

      assert_raise RuntimeError, ~r/has not done anything with the payload yet/, fn ->
        module.call(struct(module), nil, nil)
      end
    end
  end

  describe "a generated test" do
    test "compiles, so a scaffolded project starts green" do
      compile(Gen.Policy.test_source(Gen.module_name!(@policy)))
      compile(Gen.Transform.test_source(Gen.module_name!(@transform)))
    end
  end

  describe "naming" do
    test "refuses a name that is not a plugin's" do
      assert {:error, message} = Gen.module_name("Follow-Chamfers")
      assert message =~ "lowercase words joined by underscores"
    end

    test "puts the module in the application's namespace, not this package's" do
      assert Gen.module_name!(@policy) |> Module.split() |> Enum.take(2) == [
               "ExMontyCad",
               "Plugins"
             ]
    end

    test "writes source the formatter would have written" do
      # Compared without the trailing newline: the formatter normalises it, and a
      # file gets one either way.
      source = Gen.Policy.source(Gen.module_name!(@policy))

      assert String.trim_trailing(Gen.format(source)) == String.trim_trailing(source)
    end
  end

  # A module compiled from a string has to be purged when the test ends, or the
  # next test that compiles the same name is compiling over a live module.
  defp compile(source) do
    [{module, _binary} | _] = Code.compile_string(source)
    on_exit(fn -> :code.purge(module) && :code.delete(module) end)
    module
  end
end
