defmodule Dividendsomatic.Portfolio.IbkrFlexDividendParserTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.IbkrFlexDividendParser

  @sample_csv """
  "Symbol","PayDate","NetAmount","FXRateToBase","ISIN","CUSIP"
  "AGNC","2024-01-10","30.6","0.90606","US00123Q1040","00123Q104"
  "AQN","2024-01-15","21.68","0.90606","CA0158571053","015857105"
  "CIBUS","","28","1","SE0010832204",""
  """

  describe "parse/1" do
    test "should parse valid CSV with multiple records" do
      {:ok, records} = IbkrFlexDividendParser.parse(@sample_csv)
      assert length(records) == 3
    end

    test "should extract symbol, amount, and ISIN" do
      {:ok, [first | _]} = IbkrFlexDividendParser.parse(@sample_csv)
      assert first.symbol == "AGNC"
      assert Decimal.equal?(first.net_amount, Decimal.new("30.6"))
      assert first.isin == "US00123Q1040"
      assert first.amount_type == "total_net"
      assert first.source == "ibkr_flex_dividend"
    end

    test "should parse pay_date correctly" do
      {:ok, [first | _]} = IbkrFlexDividendParser.parse(@sample_csv)
      assert first.pay_date == ~D[2024-01-10]
    end

    test "should handle empty pay_date" do
      {:ok, records} = IbkrFlexDividendParser.parse(@sample_csv)
      cibus = Enum.find(records, &(&1.symbol == "CIBUS"))
      assert cibus.pay_date == nil
    end

    test "should parse fx_rate as Decimal" do
      {:ok, [first | _]} = IbkrFlexDividendParser.parse(@sample_csv)
      assert Decimal.equal?(first.fx_rate, Decimal.new("0.90606"))
    end

    test "should handle empty ISIN" do
      csv = """
      "Symbol","PayDate","NetAmount","FXRateToBase","ISIN","CUSIP"
      "NCZ","2020-01-02","38.25","0.89184","","018825109"
      """

      {:ok, [record]} = IbkrFlexDividendParser.parse(csv)
      assert record.isin == nil
    end

    test "should skip records with zero or negative amounts" do
      csv = """
      "Symbol","PayDate","NetAmount","FXRateToBase","ISIN","CUSIP"
      "TEST","2024-01-01","0","1","US1234567890",""
      "TEST2","2024-01-01","-5.00","1","US1234567890",""
      """

      {:ok, records} = IbkrFlexDividendParser.parse(csv)
      assert records == []
    end

    test "should return error for empty CSV" do
      assert {:error, :empty_csv} = IbkrFlexDividendParser.parse("")
    end
  end
end
