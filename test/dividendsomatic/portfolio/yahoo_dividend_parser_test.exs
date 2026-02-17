defmodule Dividendsomatic.Portfolio.YahooDividendParserTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.YahooDividendParser

  @sample_json """
  [
    {"symbol": "AGNC", "yahoo_symbol": "AGNC", "exchange": "NASDAQ", "isin": "US00123Q1040", "ex_date": "2008-06-30", "amount": 0.31, "currency": "USD"},
    {"symbol": "AGNC", "yahoo_symbol": "AGNC", "exchange": "NASDAQ", "isin": "US00123Q1040", "ex_date": "2008-09-29", "amount": 0.85, "currency": "USD"}
  ]
  """

  describe "parse/1" do
    test "should parse valid JSON array" do
      {:ok, records} = YahooDividendParser.parse(@sample_json)
      assert length(records) == 2
    end

    test "should extract all fields correctly" do
      {:ok, [first | _]} = YahooDividendParser.parse(@sample_json)
      assert first.symbol == "AGNC"
      assert first.yahoo_symbol == "AGNC"
      assert first.exchange == "NASDAQ"
      assert first.isin == "US00123Q1040"
      assert first.ex_date == ~D[2008-06-30]
      assert Decimal.equal?(first.amount, Decimal.new("0.31"))
      assert first.currency == "USD"
      assert first.source == "yfinance"
    end

    test "should skip records with zero amount" do
      json = ~s([{"symbol": "TEST", "ex_date": "2024-01-01", "amount": 0, "currency": "USD"}])
      {:ok, records} = YahooDividendParser.parse(json)
      assert records == []
    end

    test "should skip records with negative amount" do
      json = ~s([{"symbol": "TEST", "ex_date": "2024-01-01", "amount": -1.5, "currency": "USD"}])
      {:ok, records} = YahooDividendParser.parse(json)
      assert records == []
    end

    test "should skip records missing required fields" do
      json = ~s([{"symbol": "TEST"}])
      {:ok, records} = YahooDividendParser.parse(json)
      assert records == []
    end

    test "should default currency to USD" do
      json = ~s([{"symbol": "TEST", "ex_date": "2024-01-01", "amount": 1.5}])
      {:ok, [record]} = YahooDividendParser.parse(json)
      assert record.currency == "USD"
    end

    test "should return error for invalid JSON" do
      assert {:error, _} = YahooDividendParser.parse("not json")
    end

    test "should return error for non-array JSON" do
      assert {:error, :not_an_array} = YahooDividendParser.parse(~s({"key": "value"}))
    end

    test "should handle HK stock format" do
      json = """
      [{"symbol": "11", "yahoo_symbol": "0011.HK", "exchange": "SEHK", "isin": "HK0011000095", "ex_date": "2000-03-13", "amount": 2.5, "currency": "HKD"}]
      """

      {:ok, [record]} = YahooDividendParser.parse(json)
      assert record.symbol == "11"
      assert record.yahoo_symbol == "0011.HK"
      assert record.currency == "HKD"
      assert record.isin == "HK0011000095"
    end
  end
end
