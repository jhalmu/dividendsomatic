defmodule Dividendsomatic.Portfolio.CsvParserTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.Portfolio.CsvParser

  # Format B (18 cols): newer format with Description and FifoPnlUnrealized
  @format_b_csv """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-02-10","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","2000","20.88","41760","19.5300875","39060.175","19.5300875","12.87","2699.825","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  """

  # Format A (17 cols): older format with HoldingPeriodDateTime, no Description/FifoPnlUnrealized
  @format_a_csv """
  "ReportDate","CurrencyPrimary","Symbol","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI","HoldingPeriodDateTime"
  "2025-07-04","EUR","ENGI","COMMON","1000","19.835","19835","19.33449","19334.49","19.33449","7.27","SBF","STK","1","FR0010208488","BBG000BJNPL1",""
  """

  @format_b_multi """
  "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
  "2026-02-10","EUR","KESKOB","KESKO OYJ-B SHS","COMMON","2000","20.88","41760","19.5300875","39060.175","19.5300875","12.87","2699.825","HEX","STK","1","FI0009000202","BBG000BNP2B2"
  "2026-02-10","USD","ABR","ARBOR REALTY TRUST","REIT","500","10.9","5450","10.3154","5157.7","10.3154","1.70","292.3","NYSE","STK","0.84909","US0389231087","BBG000KMVDV1"
  """

  @snapshot_id "test-snapshot-id"

  describe "parse/2" do
    test "should parse Format B CSV with all fields correctly" do
      [holding] = CsvParser.parse(@format_b_csv, @snapshot_id)

      assert holding.portfolio_snapshot_id == @snapshot_id
      assert holding.report_date == ~D[2026-02-10]
      assert holding.currency_primary == "EUR"
      assert holding.symbol == "KESKOB"
      assert holding.description == "KESKO OYJ-B SHS"
      assert holding.sub_category == "COMMON"
      assert Decimal.equal?(holding.quantity, Decimal.new("2000"))
      assert Decimal.equal?(holding.mark_price, Decimal.new("20.88"))
      assert Decimal.equal?(holding.position_value, Decimal.new("41760"))
      assert Decimal.equal?(holding.cost_basis_price, Decimal.new("19.5300875"))
      assert Decimal.equal?(holding.cost_basis_money, Decimal.new("39060.175"))
      assert Decimal.equal?(holding.open_price, Decimal.new("19.5300875"))
      assert Decimal.equal?(holding.percent_of_nav, Decimal.new("12.87"))
      assert Decimal.equal?(holding.fifo_pnl_unrealized, Decimal.new("2699.825"))
      assert holding.listing_exchange == "HEX"
      assert holding.asset_class == "STK"
      assert Decimal.equal?(holding.fx_rate_to_base, Decimal.new("1"))
      assert holding.isin == "FI0009000202"
      assert holding.figi == "BBG000BNP2B2"
    end

    test "should parse Format A CSV with HoldingPeriodDateTime" do
      [holding] = CsvParser.parse(@format_a_csv, @snapshot_id)

      assert holding.portfolio_snapshot_id == @snapshot_id
      assert holding.report_date == ~D[2025-07-04]
      assert holding.symbol == "ENGI"
      assert holding.sub_category == "COMMON"
      assert Decimal.equal?(holding.quantity, Decimal.new("1000"))
      assert holding.listing_exchange == "SBF"
      assert holding.isin == "FR0010208488"
      assert holding.figi == "BBG000BJNPL1"
      assert holding.holding_period_date_time == ""
      # Format A has no Description column
      assert holding[:description] == nil
      # Format A has no FifoPnlUnrealized column
      assert holding[:fifo_pnl_unrealized] == nil
    end

    test "should parse multiple rows" do
      holdings = CsvParser.parse(@format_b_multi, @snapshot_id)

      assert length(holdings) == 2
      assert Enum.at(holdings, 0).symbol == "KESKOB"
      assert Enum.at(holdings, 1).symbol == "ABR"
    end

    test "should return empty list for empty CSV" do
      assert [] == CsvParser.parse("", @snapshot_id)
    end

    test "should return empty list for header-only CSV" do
      header_only =
        ~s("ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"\n)

      assert [] == CsvParser.parse(header_only, @snapshot_id)
    end

    test "should compute identifier_key from ISIN when present" do
      [holding] = CsvParser.parse(@format_b_csv, @snapshot_id)
      assert holding.identifier_key == "FI0009000202"
    end

    test "should compute identifier_key from FIGI when ISIN is missing" do
      csv = """
      "ReportDate","CurrencyPrimary","Symbol","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
      "2026-01-01","EUR","TEST","COMMON","100","10","1000","9","900","9","5","HEX","STK","1","","BBG000TEST01"
      """

      [holding] = CsvParser.parse(csv, @snapshot_id)
      assert holding.identifier_key == "BBG000TEST01"
    end

    test "should compute identifier_key from symbol:exchange when ISIN and FIGI missing" do
      csv = """
      "ReportDate","CurrencyPrimary","Symbol","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
      "2026-01-01","EUR","TEST","COMMON","100","10","1000","9","900","9","5","HEX","STK","1","",""
      """

      [holding] = CsvParser.parse(csv, @snapshot_id)
      assert holding.identifier_key == "TEST:HEX"
    end

    test "should handle decimal parsing for negative values" do
      csv = """
      "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
      "2026-02-10","EUR","NESTE","NESTE OYJ","COMMON","2000","20.41","40820","20.46182029","40923.64058","20.46182029","12.58","-103.64058","HEX","STK","1","FI0009013296","BBG000C4DP34"
      """

      [holding] = CsvParser.parse(csv, @snapshot_id)
      assert Decimal.negative?(holding.fifo_pnl_unrealized)
    end

    test "should handle unquoted CSV fields" do
      csv = """
      ReportDate,CurrencyPrimary,Symbol,SubCategory,Quantity,MarkPrice,PositionValue,CostBasisPrice,CostBasisMoney,OpenPrice,PercentOfNAV,ListingExchange,AssetClass,FXRateToBase,ISIN,FIGI
      2026-01-01,EUR,TEST,COMMON,100,10,1000,9,900,9,5,HEX,STK,1,FI0000000001,BBG000000001
      """

      [holding] = CsvParser.parse(csv, @snapshot_id)
      assert holding.symbol == "TEST"
      assert holding.isin == "FI0000000001"
    end
  end

  describe "extract_report_date/1" do
    test "should extract date from Format B CSV" do
      assert {:ok, ~D[2026-02-10]} = CsvParser.extract_report_date(@format_b_csv)
    end

    test "should extract date from Format A CSV" do
      assert {:ok, ~D[2025-07-04]} = CsvParser.extract_report_date(@format_a_csv)
    end

    test "should return error for empty CSV" do
      assert {:error, "no data rows"} = CsvParser.extract_report_date("")
    end

    test "should return error for header-only CSV" do
      header_only = ~s("ReportDate","Symbol"\n)
      assert {:error, "no data rows"} = CsvParser.extract_report_date(header_only)
    end

    test "should return error for invalid date format" do
      csv = """
      "ReportDate","Symbol"
      "not-a-date","KESKOB"
      """

      assert {:error, "invalid date: " <> _} = CsvParser.extract_report_date(csv)
    end

    test "should handle Windows-style line endings" do
      csv = "\"ReportDate\",\"Symbol\"\r\n\"2026-03-01\",\"KESKOB\"\r\n"
      assert {:ok, ~D[2026-03-01]} = CsvParser.extract_report_date(csv)
    end

    test "should handle unquoted date values" do
      csv = """
      ReportDate,Symbol
      2026-02-15,KESKOB
      """

      assert {:ok, ~D[2026-02-15]} = CsvParser.extract_report_date(csv)
    end
  end

  describe "detect_format/1" do
    test "should detect Format A (with HoldingPeriodDateTime)" do
      assert :format_a == CsvParser.detect_format(@format_a_csv)
    end

    test "should detect Format B (with Description)" do
      assert :format_b == CsvParser.detect_format(@format_b_csv)
    end

    test "should return unknown for empty CSV" do
      assert :unknown == CsvParser.detect_format("")
    end

    test "should return unknown for unrecognized headers" do
      csv = """
      "Column1","Column2"
      "val1","val2"
      """

      assert :unknown == CsvParser.detect_format(csv)
    end
  end
end
