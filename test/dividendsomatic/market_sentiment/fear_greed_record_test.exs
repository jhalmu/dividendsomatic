defmodule Dividendsomatic.MarketSentiment.FearGreedRecordTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.MarketSentiment.FearGreedRecord

  describe "changeset/2" do
    test "should accept valid attributes" do
      changeset =
        FearGreedRecord.changeset(%FearGreedRecord{}, %{
          date: ~D[2026-01-15],
          value: 45,
          classification: "Fear"
        })

      assert changeset.valid?
    end

    test "should require all fields" do
      changeset = FearGreedRecord.changeset(%FearGreedRecord{}, %{})
      refute changeset.valid?
      assert errors_on(changeset) |> Map.has_key?(:date)
      assert errors_on(changeset) |> Map.has_key?(:value)
      assert errors_on(changeset) |> Map.has_key?(:classification)
    end

    test "should validate value range 0-100" do
      changeset =
        FearGreedRecord.changeset(%FearGreedRecord{}, %{
          date: ~D[2026-01-15],
          value: 101,
          classification: "Extreme Greed"
        })

      refute changeset.valid?

      changeset =
        FearGreedRecord.changeset(%FearGreedRecord{}, %{
          date: ~D[2026-01-15],
          value: -1,
          classification: "Extreme Fear"
        })

      refute changeset.valid?
    end

    test "should enforce unique date constraint" do
      attrs = %{date: ~D[2026-01-15], value: 50, classification: "Neutral"}

      {:ok, _} =
        %FearGreedRecord{}
        |> FearGreedRecord.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %FearGreedRecord{}
        |> FearGreedRecord.changeset(attrs)
        |> Repo.insert()

      assert errors_on(changeset) |> Map.has_key?(:date)
    end
  end
end
