defmodule Dividendsomatic.MarketSentimentHistoryTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.MarketSentiment
  alias Dividendsomatic.MarketSentiment.FearGreedRecord

  describe "get_fear_greed_for_date/1" do
    test "should return nil when no data exists" do
      assert MarketSentiment.get_fear_greed_for_date(~D[2026-01-15]) == nil
    end

    test "should return data for exact date match" do
      insert_fg_record(~D[2026-01-15], 42, "Fear")

      result = MarketSentiment.get_fear_greed_for_date(~D[2026-01-15])
      assert result.value == 42
      assert result.classification == "Fear"
      assert result.color == "orange"
    end

    test "should fall back to nearest date within 3 days" do
      insert_fg_record(~D[2026-01-13], 55, "Neutral")

      result = MarketSentiment.get_fear_greed_for_date(~D[2026-01-15])
      assert result.value == 55
      assert result.classification == "Neutral"
    end

    test "should not fall back beyond 3 days" do
      insert_fg_record(~D[2026-01-10], 55, "Neutral")

      assert MarketSentiment.get_fear_greed_for_date(~D[2026-01-15]) == nil
    end

    test "should prefer exact date over nearby dates" do
      insert_fg_record(~D[2026-01-14], 30, "Fear")
      insert_fg_record(~D[2026-01-15], 70, "Greed")
      insert_fg_record(~D[2026-01-16], 40, "Fear")

      result = MarketSentiment.get_fear_greed_for_date(~D[2026-01-15])
      assert result.value == 70
    end

    test "should return correct color for different value ranges" do
      insert_fg_record(~D[2026-01-01], 10, "Extreme Fear")
      insert_fg_record(~D[2026-01-02], 35, "Fear")
      insert_fg_record(~D[2026-01-03], 50, "Neutral")
      insert_fg_record(~D[2026-01-04], 65, "Greed")
      insert_fg_record(~D[2026-01-05], 85, "Extreme Greed")

      assert MarketSentiment.get_fear_greed_for_date(~D[2026-01-01]).color == "red"
      assert MarketSentiment.get_fear_greed_for_date(~D[2026-01-02]).color == "orange"
      assert MarketSentiment.get_fear_greed_for_date(~D[2026-01-03]).color == "yellow"
      assert MarketSentiment.get_fear_greed_for_date(~D[2026-01-04]).color == "emerald"
      assert MarketSentiment.get_fear_greed_for_date(~D[2026-01-05]).color == "green"
    end
  end

  describe "get_color/1" do
    test "should classify values correctly" do
      assert MarketSentiment.get_color(0) == "red"
      assert MarketSentiment.get_color(25) == "red"
      assert MarketSentiment.get_color(26) == "orange"
      assert MarketSentiment.get_color(45) == "orange"
      assert MarketSentiment.get_color(46) == "yellow"
      assert MarketSentiment.get_color(55) == "yellow"
      assert MarketSentiment.get_color(56) == "emerald"
      assert MarketSentiment.get_color(75) == "emerald"
      assert MarketSentiment.get_color(76) == "green"
      assert MarketSentiment.get_color(100) == "green"
    end
  end

  defp insert_fg_record(date, value, classification) do
    %FearGreedRecord{}
    |> FearGreedRecord.changeset(%{date: date, value: value, classification: classification})
    |> Repo.insert!()
  end
end
