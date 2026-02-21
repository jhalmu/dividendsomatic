defmodule Dividendsomatic.Workers.IntegrityCheckWorkerTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Workers.IntegrityCheckWorker

  describe "perform/1" do
    test "should complete successfully" do
      assert :ok == IntegrityCheckWorker.perform(%Oban.Job{})
    end
  end
end
