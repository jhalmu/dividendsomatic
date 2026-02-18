defmodule Mix.Tasks.Validate.DataTest do
  use Dividendsomatic.DataCase, async: true

  alias Mix.Tasks.Validate.Data, as: ValidateData

  import ExUnit.CaptureIO

  @export_dir "data_revisited"

  describe "mix validate.data" do
    test "should run without errors on empty database" do
      output =
        capture_io(fn ->
          ValidateData.run([])
        end)

      assert output =~ "Dividend Validation Report"
      assert output =~ "Total checked: 0"
      assert output =~ "Issues found:  0"
      assert output =~ "No issues found!"
    end

    test "should produce export files with --export flag" do
      output =
        capture_io(fn ->
          ValidateData.run(["--export"])
        end)

      assert output =~ "Exported to"
      assert output =~ "Updated"

      # Verify files were created
      latest_path = Path.join(@export_dir, "validation_latest.json")
      assert File.exists?(latest_path)

      # Verify JSON is valid
      {:ok, contents} = File.read(latest_path)
      parsed = Jason.decode!(contents)
      assert is_integer(parsed["total_checked"])
      assert is_integer(parsed["issue_count"])
    after
      File.rm_rf(@export_dir)
    end

    test "should produce timestamped + latest files" do
      capture_io(fn ->
        ValidateData.run(["--export"])
      end)

      files = File.ls!(@export_dir)
      assert Enum.any?(files, &(&1 == "validation_latest.json"))
      assert Enum.any?(files, &String.starts_with?(&1, "validation_2"))
    after
      File.rm_rf(@export_dir)
    end

    test "should handle --compare with no previous snapshot gracefully" do
      output =
        capture_io(fn ->
          ValidateData.run(["--compare"])
        end)

      assert output =~ "No previous snapshot found"
    end

    test "should run --suggest without errors" do
      output =
        capture_io(fn ->
          ValidateData.run(["--suggest"])
        end)

      assert output =~ "Dividend Validation Report"
      assert output =~ "No threshold adjustments suggested"
    end
  end
end
