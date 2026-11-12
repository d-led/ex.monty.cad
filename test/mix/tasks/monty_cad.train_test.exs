defmodule Mix.Tasks.MontyCad.TrainTest do
  @moduledoc """
  The task is the same job as `MontyCad.Training.write/4`, so what is worth
  testing here is the part the library does not do: reading the command line,
  refusing an unusable one, and saying what it wrote.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.MontyCad.Train

  @fixture "test/fixtures/golden_simple_through_hole.step"

  @tag :tmp_dir
  test "writes the library it was asked for and says what is in it", %{tmp_dir: dir} do
    out = Path.join(dir, "plate.jsonl.gz")

    report =
      capture_io(fn ->
        Train.run([
          @fixture,
          "--object",
          "plate",
          "--out",
          out,
          "--limit",
          "12"
        ])
      end)

    assert File.exists?(out)
    assert report =~ "Wrote #{out} — `plate`"
    assert report =~ "Features held per node:"
  end

  @tag :tmp_dir
  test "the object name is required, because the file may not guess it", %{tmp_dir: dir} do
    out = Path.join(dir, "plate.jsonl.gz")

    error =
      assert_raise Mix.Error, fn ->
        Train.run([@fixture, "--out", out])
      end

    assert Exception.message(error) =~ "--object is required"
    refute File.exists?(out)
  end

  test "no part is a usage error, not a crash" do
    error =
      assert_raise Mix.Error, fn ->
        Train.run(["--object", "plate"])
      end

    assert Exception.message(error) =~ "usage: mix monty_cad.train"
  end

  @tag :tmp_dir
  test "a part that cannot be read is reported with its reason", %{tmp_dir: dir} do
    error =
      assert_raise Mix.Error, fn ->
        Train.run([Path.join(dir, "absent.step"), "--object", "plate"])
      end

    assert Exception.message(error) =~ "unreadable"
  end
end
