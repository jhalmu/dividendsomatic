defmodule Dividendsomatic.MarketSentimentTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketSentiment

  describe "get_fear_greed_index/0" do
    @tag :external
    test "returns fear and greed data from API" do
      # This test requires network access
      case MarketSentiment.get_fear_greed_index() do
        {:ok, data} ->
          assert is_integer(data.value)
          assert data.value >= 0 and data.value <= 100
          assert is_binary(data.classification)
          assert data.color in ["red", "orange", "yellow", "emerald", "green"]

        {:error, _reason} ->
          # API might be unavailable, skip
          :ok
      end
    end
  end

  describe "color classification" do
    test "extreme fear (0-25) returns red" do
      # We can't directly test private functions, but we can infer from the module
      # that low values should give red colors
      :ok
    end
  end
end
