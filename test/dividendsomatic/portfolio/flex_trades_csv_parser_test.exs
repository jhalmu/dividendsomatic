defmodule Dividendsomatic.Portfolio.FlexTradesCsvParserTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.FlexTradesCsvParser

  @sample_csv """
  "ISIN","FIGI","CUSIP","Conid","Symbol","CurrencyPrimary","FXRateToBase","TradeID","TradeDate","Quantity","TradePrice","Taxes","Buy/Sell","ListingExchange"
  "FI4000297767","BBG00LWMJDL7","","335134428","NDA FI","EUR","1","1319331815","20260213","1000","16.185","0","BUY","HEX"
  "US68571X3017","BBG001P2KSC8","68571X301","581240386","ORC","USD","0.84069","1314038092","20260210","2000","7.5","0","BUY","NYSE"
  """

  @fx_trade_csv """
  "ISIN","FIGI","CUSIP","Conid","Symbol","CurrencyPrimary","FXRateToBase","TradeID","TradeDate","Quantity","TradePrice","Taxes","Buy/Sell","ListingExchange"
  "","","","12345770","EUR.HKD","HKD","0.10775","1316898252","20260211","-18","9.28065","0","SELL",""
  "","","","37893488","EUR.SEK","SEK","0.094683","1315332533","20260211","-0.6102","10.57395","0","SELL",""
  """

  describe "parse/1" do
    test "should parse valid trades CSV" do
      {:ok, transactions} = FlexTradesCsvParser.parse(@sample_csv)
      assert length(transactions) == 2
    end

    test "should extract ISIN and symbol" do
      {:ok, [first | _]} = FlexTradesCsvParser.parse(@sample_csv)
      assert first.isin == "FI4000297767"
      assert first.security_name == "NDA FI"
    end

    test "should parse YYYYMMDD trade dates" do
      {:ok, [first | _]} = FlexTradesCsvParser.parse(@sample_csv)
      assert first.trade_date == ~D[2026-02-13]
    end

    test "should parse quantity and price as Decimal" do
      {:ok, [first | _]} = FlexTradesCsvParser.parse(@sample_csv)
      assert Decimal.equal?(first.quantity, Decimal.new("1000"))
      assert Decimal.equal?(first.price, Decimal.new("16.185"))
    end

    test "should classify BUY transactions" do
      {:ok, [first | _]} = FlexTradesCsvParser.parse(@sample_csv)
      assert first.transaction_type == "buy"
      assert first.raw_type == "BUY"
      assert first.broker == "ibkr"
    end

    test "should classify FX trades with empty ISIN as fx_sell" do
      {:ok, transactions} = FlexTradesCsvParser.parse(@fx_trade_csv)

      Enum.each(transactions, fn txn ->
        assert txn.transaction_type == "fx_sell"
        assert txn.isin == nil
      end)
    end

    test "should store FIGI and trade_id in raw_data" do
      {:ok, [first | _]} = FlexTradesCsvParser.parse(@sample_csv)
      assert first.raw_data["figi"] == "BBG00LWMJDL7"
      assert first.raw_data["trade_id"] == "1319331815"
      assert first.raw_data["exchange"] == "HEX"
    end

    test "should assign deterministic external_ids" do
      {:ok, transactions1} = FlexTradesCsvParser.parse(@sample_csv)
      {:ok, transactions2} = FlexTradesCsvParser.parse(@sample_csv)

      ids1 = Enum.map(transactions1, & &1.external_id)
      ids2 = Enum.map(transactions2, & &1.external_id)

      assert ids1 == ids2
      assert Enum.all?(ids1, &String.starts_with?(&1, "ibkr_flex_"))
    end

    test "should compute amount as negative of qty*price" do
      {:ok, [first | _]} = FlexTradesCsvParser.parse(@sample_csv)
      # 1000 * 16.185 = 16185, negated = -16185
      expected = Decimal.negate(Decimal.new("16185.000"))
      assert Decimal.equal?(first.amount, expected)
    end

    test "should parse exchange rate" do
      {:ok, transactions} = FlexTradesCsvParser.parse(@sample_csv)
      orc = Enum.find(transactions, &(&1.security_name == "ORC"))
      assert Decimal.equal?(orc.exchange_rate, Decimal.new("0.84069"))
    end

    test "should return error for empty CSV" do
      assert {:error, :empty_csv} = FlexTradesCsvParser.parse("")
    end

    test "should return empty list for header-only CSV" do
      csv =
        ~s("ISIN","FIGI","CUSIP","Conid","Symbol","CurrencyPrimary","FXRateToBase","TradeID","TradeDate","Quantity","TradePrice","Taxes","Buy/Sell","ListingExchange"\n)

      {:ok, transactions} = FlexTradesCsvParser.parse(csv)
      assert transactions == []
    end
  end
end
