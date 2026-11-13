defmodule MontyCad.InputsTest do
  @moduledoc """
  Where a part and a memory are looked for.

  The cases are about the directory, not about a file being a valid STEP: what a
  caller has to be able to rely on is that a name resolves to the same path on
  every node that shares `MONTY_DATA`, and that a name nobody wrote says so.
  """

  use ExUnit.Case, async: false

  alias MontyCad.Inputs

  setup do
    data = Path.join(System.tmp_dir!(), "cad-inputs-#{System.unique_integer([:positive])}")

    libraries =
      Path.join(System.tmp_dir!(), "cad-libraries-#{System.unique_integer([:positive])}")

    for {variable, value} <- [
          {"MONTY_DATA", data},
          {"MONTY_LIBRARIES", libraries},
          {"MONTY_CAD_PART", nil}
        ] do
      previous = System.get_env(variable)
      if value, do: System.put_env(variable, value), else: System.delete_env(variable)

      on_exit(fn ->
        if previous, do: System.put_env(variable, previous), else: System.delete_env(variable)
      end)
    end

    File.mkdir_p!(Path.join(data, "parts"))
    File.mkdir_p!(libraries)
    on_exit(fn -> File.rm_rf!(data) && File.rm_rf!(libraries) end)

    %{data: data, libraries: libraries}
  end

  test "a part is a name in the parts directory, with or without its extension", %{
    data: data
  } do
    File.write!(Path.join([data, "parts", "bracket.step"]), "")
    File.write!(Path.join([data, "parts", "plate.stp"]), "")

    assert Inputs.part_path("bracket") == {:ok, Path.join([data, "parts", "bracket.step"])}
    assert Inputs.part_path("bracket.step") == {:ok, Path.join([data, "parts", "bracket.step"])}
    assert Inputs.part_path("plate") == {:ok, Path.join([data, "parts", "plate.stp"])}
  end

  test "the parts directory lists what is there and nothing else", %{data: data} do
    File.write!(Path.join([data, "parts", "bracket.step"]), "")
    File.write!(Path.join([data, "parts", "notes.txt"]), "")

    assert Inputs.parts() == ["bracket.step"]
  end

  test "a name nobody wrote says which parts there are" do
    assert {:error, sentence} = Inputs.part_path("bracket")
    assert sentence =~ ~s(there is no part "bracket")
    assert sentence =~ "holds"
  end

  test "a path to a file that exists is used as it is" do
    loose = Path.join(System.tmp_dir!(), "loose-#{System.unique_integer([:positive])}.step")
    File.write!(loose, "")
    on_exit(fn -> File.rm(loose) end)

    assert Inputs.part_path(loose) == {:ok, loose}
  end

  test "no part named is a sentence, not a nil" do
    assert {:error, sentence} = Inputs.part_path()
    assert sentence =~ "MONTY_CAD_PART"
  end

  # The studio loads a memory by release and name (`Monty.Studio.Memory`), so a
  # memory written here is one a run can ask for — the same address, both sides.
  test "a memory has the address the studio loads it by", %{libraries: libraries} do
    assert Inputs.library_path("bracket", "cad") ==
             Path.join([libraries, "cad", "bracket.jsonl.gz"])
  end
end
