defmodule Dividendsomatic.Portfolio.FlexCsvRouterTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.FlexCsvRouter

  @portfolio_csv """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-02-16","EUR","AKTIA","AKTIA BANK OYJ","COMMON","1000","12.18","12180","11.950746","11950.746","11.950746","3.56","229.254","HEX","STK","1","FI4000058870","BBG000CNBSS1"
  """

  @dividends_csv """
  "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
  "TELIA1","SE0000667925","BBG000GJ9377","STK","SEK","0.094367","2026-02-05","2026-02-11","10000","0.5","-3500"
  """

  @trades_csv """
  "ISIN","FIGI","CUSIP","Conid","Symbol","CurrencyPrimary","FXRateToBase","TradeID","TradeDate","Quantity","TradePrice","Taxes","Buy/Sell","ListingExchange"
  "FI4000297767","BBG00LWMJDL7","","335134428","NDA FI","EUR","1","1319331815","20260213","1000","16.185","0","BUY","HEX"
  """

  @actions_csv """
  "ClientAccountID","AccountAlias","Model","CurrencyPrimary","FXRateToBase","AssetClass","Symbol","Description","Conid","SecurityID","SecurityIDType","CUSIP","ISIN","ListingExchange","UnderlyingConid","UnderlyingSymbol","UnderlyingSecurityID","UnderlyingListingExchange","Issuer","Multiplier","Strike","Expiry","Put/Call","PrincipalAdjustFactor","ReportDate","Date","SettleDate","ActivityCode","ActivityDescription","TradeID","OrderID","Buy/Sell","TradeQuantity","TradePrice","TradeGross","TradeCommission","TradeTax","Debit","Credit","Amount","TradeCode","Balance","LevelOfDetail","TransactionID"
  "U7299935","","","EUR","1","STK","TRIN","TRINITY CAPITAL INC","468533653","US8964423086","ISIN","896442308","US8964423086","NASDAQ","","TRIN","","","","1","","","","","2026-02-09","2026-01-15","2026-01-15","FRTAX","TRIN description","","","","0","0","0","0","0","","10.0791523","10.0791523","","-228532.648612115","BaseCurrency","5393915966"
  """

  @dividends_with_dupe_header """
  "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
  "TELIA1","SE0000667925","BBG000GJ9377","STK","SEK","0.094367","2026-02-05","2026-02-11","10000","0.5","-3500"
  "AGNC","US00123Q1040","BBG000TJ8XZ7","STK","USD","0.84069","2026-01-30","2026-02-10","2000","0.12","-204"
  "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
  "CSWC","US1405011073","BBG000BGJ661","STK","USD","0.84258","2026-02-13","2026-02-27","1000","0.1934","164.39"
  """

  describe "detect_csv_type/1" do
    test "should detect portfolio CSV" do
      assert :portfolio == FlexCsvRouter.detect_csv_type(@portfolio_csv)
    end

    test "should detect dividends CSV" do
      assert :dividends == FlexCsvRouter.detect_csv_type(@dividends_csv)
    end

    test "should detect trades CSV" do
      assert :trades == FlexCsvRouter.detect_csv_type(@trades_csv)
    end

    test "should detect actions CSV" do
      assert :actions == FlexCsvRouter.detect_csv_type(@actions_csv)
    end

    test "should return unknown for empty string" do
      assert :unknown == FlexCsvRouter.detect_csv_type("")
    end

    test "should return unknown for unrecognized headers" do
      csv = ~s("Foo","Bar","Baz"\n"1","2","3")
      assert :unknown == FlexCsvRouter.detect_csv_type(csv)
    end
  end

  describe "strip_duplicate_headers/1" do
    test "should remove duplicate header rows from mid-file" do
      cleaned = FlexCsvRouter.strip_duplicate_headers(@dividends_with_dupe_header)
      lines = cleaned |> String.split("\n") |> Enum.reject(&(&1 == ""))

      # Should have header + 3 data rows (not 4 lines + header)
      assert length(lines) == 4

      # Header should appear only once
      header_count =
        Enum.count(lines, &String.contains?(&1, "GrossRate"))

      assert header_count == 1
    end

    test "should not modify CSV without duplicate headers" do
      original = @portfolio_csv
      assert FlexCsvRouter.strip_duplicate_headers(original) == original
    end

    test "should handle empty string" do
      assert "" == FlexCsvRouter.strip_duplicate_headers("")
    end
  end

  describe "classify_and_clean/1" do
    test "should return type and cleaned CSV" do
      {type, cleaned} = FlexCsvRouter.classify_and_clean(@dividends_with_dupe_header)
      assert type == :dividends

      lines = cleaned |> String.split("\n") |> Enum.reject(&(&1 == ""))
      header_count = Enum.count(lines, &String.contains?(&1, "GrossRate"))
      assert header_count == 1
    end
  end
end
