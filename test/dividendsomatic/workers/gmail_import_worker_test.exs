defmodule Dividendsomatic.Workers.GmailImportWorkerTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Workers.GmailImportWorker

  describe "perform/1" do
    test "should succeed when Gmail is not configured" do
      job = %Oban.Job{args: %{}}

      assert {:ok, %{imported: 0, skipped: 0, errors: 0}} =
               GmailImportWorker.perform(job)
    end

    test "should accept custom args" do
      job = %Oban.Job{args: %{"days_back" => 7, "max_results" => 5}}

      assert {:ok, %{imported: 0, skipped: 0, errors: 0}} =
               GmailImportWorker.perform(job)
    end

    test "should use default args when empty" do
      job = %Oban.Job{args: %{}}

      result = GmailImportWorker.perform(job)
      assert {:ok, _} = result
    end
  end

  describe "new/1" do
    test "should create a valid Oban job changeset" do
      changeset = GmailImportWorker.new(%{})
      assert changeset.valid?
    end

    test "should create job with custom args" do
      changeset = GmailImportWorker.new(%{"days_back" => 14})
      assert changeset.valid?
    end
  end
end
