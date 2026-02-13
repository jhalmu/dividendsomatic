defmodule Dividendsomatic.DataIngestion.CsvDirectoryTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.DataIngestion.CsvDirectory

  @moduletag :tmp_dir

  describe "archive_file/2" do
    test "should move file to archive/flex/ directory", %{tmp_dir: tmp_dir} do
      # Create source file
      src = Path.join(tmp_dir, "test.csv")
      File.write!(src, "header\ndata")

      assert :ok = CsvDirectory.archive_file(src, dir: tmp_dir)

      # Source file should be gone
      refute File.exists?(src)

      # Archived file should exist
      archived = Path.join([tmp_dir, "archive", "flex", "test.csv"])
      assert File.exists?(archived)
      assert File.read!(archived) == "header\ndata"
    end

    test "should create archive directory if it does not exist", %{tmp_dir: tmp_dir} do
      src = Path.join(tmp_dir, "new.csv")
      File.write!(src, "content")

      archive_dir = Path.join([tmp_dir, "archive", "flex"])
      refute File.exists?(archive_dir)

      assert :ok = CsvDirectory.archive_file(src, dir: tmp_dir)
      assert File.exists?(archive_dir)
    end

    test "should return error when source file does not exist", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "missing.csv")

      assert {:error, :enoent} = CsvDirectory.archive_file(missing, dir: tmp_dir)
    end

    test "should preserve filename when archiving", %{tmp_dir: tmp_dir} do
      filename = "flex.U123.PortfolioForWww.20260213.20260213.csv"
      src = Path.join(tmp_dir, filename)
      File.write!(src, "data")

      assert :ok = CsvDirectory.archive_file(src, dir: tmp_dir)

      archived = Path.join([tmp_dir, "archive", "flex", filename])
      assert File.exists?(archived)
    end
  end
end
