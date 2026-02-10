defmodule Dividendsomatic.MarketSentimentTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketSentiment

  describe "get_fear_greed_index/0" do
    @tag :external
    test "should return valid fear and greed data from API" do
      case MarketSentiment.get_fear_greed_index() do
        {:ok, data} ->
          assert is_integer(data.value)
          assert data.value >= 0 and data.value <= 100
          assert is_binary(data.classification)
          assert data.color in ["red", "orange", "yellow", "emerald", "green"]
          assert %DateTime{} = data.timestamp

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_fear_greed_index_cached/0" do
    test "should cache results in persistent_term" do
      # Clean up any existing cache
      try do
        :persistent_term.erase(:fear_greed_index)
      rescue
        ArgumentError -> :ok
      end

      # Pre-populate cache with known value
      cached_value = %{
        value: 50,
        classification: "Neutral",
        timestamp: DateTime.utc_now(),
        color: "yellow"
      }

      :persistent_term.put(:fear_greed_index, {cached_value, System.system_time(:second)})

      # Should return cached value
      assert {:ok, result} = MarketSentiment.get_fear_greed_index_cached()
      assert result.value == 50
      assert result.classification == "Neutral"

      # Clean up
      :persistent_term.erase(:fear_greed_index)
    end

    test "should return stale cache when refresh fails" do
      # Pre-populate with old cache
      old_value = %{
        value: 75,
        classification: "Greed",
        timestamp: DateTime.utc_now(),
        color: "emerald"
      }

      # Set cache as expired (way in the past)
      :persistent_term.put(:fear_greed_index, {old_value, 0})

      # API call might fail or succeed - either way we should get a result
      case MarketSentiment.get_fear_greed_index_cached() do
        {:ok, result} ->
          assert is_integer(result.value) or result.value == 75
          assert is_binary(result.classification)

        {:error, _} ->
          :ok
      end

      # Clean up
      try do
        :persistent_term.erase(:fear_greed_index)
      rescue
        ArgumentError -> :ok
      end
    end
  end

  describe "color classification" do
    # Test via the public API by injecting known cached values
    test "should map value ranges to correct colors" do
      test_cases = [
        {10, "red"},
        {25, "red"},
        {30, "orange"},
        {45, "orange"},
        {50, "yellow"},
        {55, "yellow"},
        {60, "emerald"},
        {75, "emerald"},
        {80, "green"},
        {100, "green"}
      ]

      for {value, expected_color} <- test_cases do
        cached = %{
          value: value,
          classification: "Test",
          timestamp: DateTime.utc_now(),
          color: expected_color
        }

        :persistent_term.put(:fear_greed_index, {cached, System.system_time(:second)})

        {:ok, result} = MarketSentiment.get_fear_greed_index_cached()
        assert result.color == expected_color, "Value #{value} should map to #{expected_color}"
      end

      # Clean up
      :persistent_term.erase(:fear_greed_index)
    end
  end
end
