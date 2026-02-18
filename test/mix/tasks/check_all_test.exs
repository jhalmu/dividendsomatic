defmodule Mix.Tasks.Check.AllTest do
  use Dividendsomatic.DataCase, async: true

  alias Mix.Tasks.Check.All, as: CheckAll

  import ExUnit.CaptureIO

  describe "mix check.all" do
    test "should run without errors on empty database" do
      output =
        capture_io(fn ->
          CheckAll.run([])
        end)

      assert output =~ "Data Integrity Check"
      assert output =~ "Dividend Validation:"
      assert output =~ "Data Gap Analysis:"
    end

    test "should print combined summary" do
      output =
        capture_io(fn ->
          CheckAll.run([])
        end)

      assert output =~ "Summary"
      assert output =~ "All checks passed"
    end
  end
end
