defmodule Dividendsomatic.Portfolio.FlexDividendCsvParserTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.FlexDividendCsvParser

  @sample_csv """
  "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
  "TELIA1","SE0000667925","BBG000GJ9377","STK","SEK","0.094367","2026-02-05","2026-02-11","10000","0.5","-3500"
  "AGNC","US00123Q1040","BBG000TJ8XZ7","STK","USD","0.84069","2026-01-30","2026-02-10","2000","0.12","-204"
  "CSWC","US1405011073","BBG000BGJ661","STK","USD","0.84258","2026-02-13","2026-02-27","1000","0.1934","164.39"
  """

  @csv_with_dupe_headers """
  "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
  "TELIA1","SE0000667925","BBG000GJ9377","STK","SEK","0.094367","2026-02-05","2026-02-11","10000","0.5","-3500"
  "AGNC","US00123Q1040","BBG000TJ8XZ7","STK","USD","0.84069","2026-01-30","2026-02-10","2000","0.12","-204"
  "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
  "CSWC","US1405011073","BBG000BGJ661","STK","USD","0.84258","2026-02-13","2026-02-27","1000","0.1934","164.39"
  """

  describe "parse/1" do
    test "should parse valid CSV with multiple records" do
      {:ok, records} = FlexDividendCsvParser.parse(@sample_csv)
      assert length(records) == 3
    end

    test "should extract symbol, ISIN, and FIGI" do
      {:ok, [first | _]} = FlexDividendCsvParser.parse(@sample_csv)
      assert first.symbol == "TELIA1"
      assert first.isin == "SE0000667925"
      assert first.figi == "BBG000GJ9377"
    end

    test "should parse dates correctly" do
      {:ok, [first | _]} = FlexDividendCsvParser.parse(@sample_csv)
      assert first.ex_date == ~D[2026-02-05]
      assert first.pay_date == ~D[2026-02-11]
    end

    test "should parse decimals correctly" do
      {:ok, [first | _]} = FlexDividendCsvParser.parse(@sample_csv)
      assert Decimal.equal?(first.gross_rate, Decimal.new("0.5"))
      assert Decimal.equal?(first.fx_rate, Decimal.new("0.094367"))
      assert Decimal.equal?(first.quantity_at_record, Decimal.new("10000"))
    end

    test "should use absolute value of NetAmount" do
      {:ok, [telia | _]} = FlexDividendCsvParser.parse(@sample_csv)
      # TELIA1 has -3500 in CSV, should be stored as 3500
      assert Decimal.equal?(telia.net_amount, Decimal.new("3500"))
      assert Decimal.equal?(telia.amount, Decimal.new("3500"))
    end

    test "should handle positive NetAmount" do
      {:ok, records} = FlexDividendCsvParser.parse(@sample_csv)
      cswc = Enum.find(records, &(&1.symbol == "CSWC"))
      assert Decimal.equal?(cswc.net_amount, Decimal.new("164.39"))
    end

    test "should set amount_type to total_net" do
      {:ok, [first | _]} = FlexDividendCsvParser.parse(@sample_csv)
      assert first.amount_type == "total_net"
      assert first.source == "ibkr_flex_dividend"
    end

    test "should resolve currency from CSV field" do
      {:ok, records} = FlexDividendCsvParser.parse(@sample_csv)
      telia = Enum.find(records, &(&1.symbol == "TELIA1"))
      agnc = Enum.find(records, &(&1.symbol == "AGNC"))
      assert telia.currency == "SEK"
      assert agnc.currency == "USD"
    end

    test "should handle duplicate header rows" do
      {:ok, records} = FlexDividendCsvParser.parse(@csv_with_dupe_headers)
      assert length(records) == 3
      symbols = Enum.map(records, & &1.symbol)
      assert "TELIA1" in symbols
      assert "AGNC" in symbols
      assert "CSWC" in symbols
    end

    test "should skip records with zero net amount" do
      csv = """
      "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
      "TEST","US1234567890","BBG000000001","STK","USD","1","2026-01-01","2026-01-15","100","0.10","0"
      """

      {:ok, records} = FlexDividendCsvParser.parse(csv)
      assert records == []
    end

    test "should return error for empty CSV" do
      assert {:error, :empty_csv} = FlexDividendCsvParser.parse("")
    end

    test "should return empty list for header-only CSV" do
      csv =
        ~s("Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"\n)

      {:ok, records} = FlexDividendCsvParser.parse(csv)
      assert records == []
    end

    test "should handle empty ISIN and FIGI" do
      csv = """
      "Symbol","ISIN","FIGI","AssetClass","CurrencyPrimary","FXRateToBase","ExDate","PayDate","Quantity","GrossRate","NetAmount"
      "TEST","","","STK","EUR","1","2026-01-01","2026-01-15","100","0.10","50"
      """

      {:ok, [record]} = FlexDividendCsvParser.parse(csv)
      assert record.isin == nil
      assert record.figi == nil
      assert record.currency == "EUR"
    end
  end
end
