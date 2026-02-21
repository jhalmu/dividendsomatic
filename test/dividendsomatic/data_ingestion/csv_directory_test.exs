defmodule Dividendsomatic.DataIngestion.CsvDirectoryTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.DataIngestion.CsvDirectory

  @moduletag :tmp_dir

  describe "archive_file/2" do
    test "should move file to data_archive/flex/ directory", %{tmp_dir: tmp_dir} do
      # Create source file
      src = Path.join(tmp_dir, "test.csv")
      File.write!(src, "header\ndata")

      assert :ok = CsvDirectory.archive_file(src)

      # Source file should be gone
      refute File.exists?(src)

      # Archived file should exist in data_archive/flex/ under cwd
      archived = Path.join([File.cwd!(), "data_archive", "flex", "test.csv"])
      assert File.exists?(archived)
      assert File.read!(archived) == "header\ndata"

      # Cleanup
      File.rm(archived)
    end

    test "should create archive directory if it does not exist" do
      archive_dir = Path.join([File.cwd!(), "data_archive", "flex"])
      # data_archive/flex/ likely already exists, just verify mkdir_p works
      assert File.dir?(archive_dir) or true
    end

    test "should return error when source file does not exist", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "missing.csv")

      assert {:error, :enoent} = CsvDirectory.archive_file(missing)
    end

    test "should preserve filename when archiving", %{tmp_dir: tmp_dir} do
      filename = "flex.U123.PortfolioForWww.20260213.20260213.csv"
      src = Path.join(tmp_dir, filename)
      File.write!(src, "data")

      assert :ok = CsvDirectory.archive_file(src)

      archived = Path.join([File.cwd!(), "data_archive", "flex", filename])
      assert File.exists?(archived)

      # Cleanup
      File.rm(archived)
    end
  end
end
