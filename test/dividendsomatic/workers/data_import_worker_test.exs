defmodule Dividendsomatic.Workers.DataImportWorkerTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Workers.DataImportWorker

  describe "perform/1 with csv_directory source" do
    test "should handle csv_directory source with non-existent directory" do
      # Point to a directory that does not exist - worker returns :ok even on
      # errors by design, to avoid Oban retries for known issues
      Application.put_env(:dividendsomatic, :csv_import_dir, "tmp/test_nonexistent_dir")

      on_exit(fn ->
        Application.put_env(:dividendsomatic, :csv_import_dir, "csv_data")
      end)

      job = %Oban.Job{args: %{"source" => "csv_directory"}}

      assert :ok = DataImportWorker.perform(job)
    end

    test "should handle csv_directory source with empty directory" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "data_import_worker_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
        Application.put_env(:dividendsomatic, :csv_import_dir, "csv_data")
      end)

      Application.put_env(:dividendsomatic, :csv_import_dir, tmp_dir)

      job = %Oban.Job{args: %{"source" => "csv_directory"}}

      assert :ok = DataImportWorker.perform(job)
    end
  end

  describe "run_post_import_validation (via perform)" do
    test "should run validation after successful import with empty directory" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "data_import_validation_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
        Application.put_env(:dividendsomatic, :csv_import_dir, "csv_data")
      end)

      Application.put_env(:dividendsomatic, :csv_import_dir, tmp_dir)

      job = %Oban.Job{args: %{"source" => "csv_directory"}}

      # Should complete without error - validation runs silently when no issues
      assert :ok = DataImportWorker.perform(job)
    end
  end

  describe "perform/1 with unknown source" do
    test "should handle unknown source args" do
      job = %Oban.Job{args: %{"source" => "unknown_source"}}

      assert :ok = DataImportWorker.perform(job)
    end
  end

  describe "new/1" do
    test "should create a valid Oban job changeset" do
      changeset = DataImportWorker.new(%{"source" => "csv_directory"})

      assert changeset.valid?
    end
  end
end
