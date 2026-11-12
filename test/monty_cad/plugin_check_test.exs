defmodule MontyCad.PluginCheckTest do
  @moduledoc """
  What the checker is for: a plugin that has drifted is named, with the reason, and
  a plugin that has not is silent.
  """
  use ExUnit.Case, async: true

  alias MontyCad.Plugin.Check
  alias MontyCad.Test.Fixtures.{GoodPolicy, PartialPolicy, Unnamed}

  test "a plugin that is everything it claims has no problems" do
    assert Check.problems(GoodPolicy) == []
  end

  test "a policy that cannot be called is told which callback is missing" do
    assert [problem] = Check.problems(PartialPolicy)
    assert problem =~ "is a motor_policy"
    assert problem =~ "call/6"
  end

  test "a description missing what a cluster registers is refused, with the field named" do
    assert [problem] = Check.problems(Unnamed)
    assert problem =~ "describes itself wrongly"
    assert problem =~ "`name` is missing"
  end

  test "the plugins of an application are the modules that say they are" do
    plugins = Check.plugins(:ex_monty_cad)

    assert GoodPolicy in plugins
    assert PartialPolicy in plugins
    assert Unnamed in plugins
    refute Enum.any?(plugins, &(&1 == MontyCad.Plugin))
  end

  test "an application with no plugins has none" do
    assert Check.plugins(:no_such_application) == []
  end
end
