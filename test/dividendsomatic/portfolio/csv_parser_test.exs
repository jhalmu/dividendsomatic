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

  describe "parse/3" do
    test "should parse Format B CSV with all fields correctly" do
      [position] = CsvParser.parse(@format_b_csv, @snapshot_id, ~D[2026-02-10])

      assert position.portfolio_snapshot_id == @snapshot_id
      assert position.date == ~D[2026-02-10]
      assert position.currency == "EUR"
      assert position.symbol == "KESKOB"
      assert position.name == "KESKO OYJ-B SHS"
      assert Decimal.equal?(position.quantity, Decimal.new("2000"))
      assert Decimal.equal?(position.price, Decimal.new("20.88"))
      assert Decimal.equal?(position.value, Decimal.new("41760"))
      assert Decimal.equal?(position.cost_price, Decimal.new("19.5300875"))
      assert Decimal.equal?(position.cost_basis, Decimal.new("39060.175"))
      assert Decimal.equal?(position.weight, Decimal.new("12.87"))
      assert Decimal.equal?(position.unrealized_pnl, Decimal.new("2699.825"))
      assert position.exchange == "HEX"
      assert position.asset_class == "STK"
      assert Decimal.equal?(position.fx_rate, Decimal.new("1"))
      assert position.isin == "FI0009000202"
      assert position.figi == "BBG000BNP2B2"
      assert position.data_source == "ibkr_flex"
    end

    test "should parse Format A CSV with HoldingPeriodDateTime" do
      [position] = CsvParser.parse(@format_a_csv, @snapshot_id, ~D[2025-07-04])

      assert position.portfolio_snapshot_id == @snapshot_id
      assert position.date == ~D[2025-07-04]
      assert position.symbol == "ENGI"
      assert Decimal.equal?(position.quantity, Decimal.new("1000"))
      assert position.exchange == "SBF"
      assert position.isin == "FR0010208488"
      assert position.figi == "BBG000BJNPL1"
      # Dropped fields should not be present
      refute Map.has_key?(position, :_report_date)
      refute Map.has_key?(position, :_sub_category)
      refute Map.has_key?(position, :_open_price)
      refute Map.has_key?(position, :_holding_period)
      # Format A has no Description column
      assert position[:name] == nil
      # Format A has no FifoPnlUnrealized column
      assert position[:unrealized_pnl] == nil
    end

    test "should parse multiple rows" do
      positions = CsvParser.parse(@format_b_multi, @snapshot_id, ~D[2026-02-10])

      assert length(positions) == 2
      assert Enum.at(positions, 0).symbol == "KESKOB"
      assert Enum.at(positions, 1).symbol == "ABR"
    end

    test "should return empty list for empty CSV" do
      assert [] == CsvParser.parse("", @snapshot_id, ~D[2026-01-01])
    end

    test "should return empty list for header-only CSV" do
      header_only =
        ~s("ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"\n)

      assert [] == CsvParser.parse(header_only, @snapshot_id, ~D[2026-01-01])
    end

    test "should handle decimal parsing for negative values" do
      csv = """
      "ReportDate","CurrencyPrimary","Symbol","Description","SubCategory","Quantity","MarkPrice","PositionValue","CostBasisPrice","CostBasisMoney","OpenPrice","PercentOfNAV","FifoPnlUnrealized","ListingExchange","AssetClass","FXRateToBase","ISIN","FIGI"
      "2026-02-10","EUR","NESTE","NESTE OYJ","COMMON","2000","20.41","40820","20.46182029","40923.64058","20.46182029","12.58","-103.64058","HEX","STK","1","FI0009013296","BBG000C4DP34"
      """

      [position] = CsvParser.parse(csv, @snapshot_id, ~D[2026-02-10])
      assert Decimal.negative?(position.unrealized_pnl)
    end

    test "should handle unquoted CSV fields" do
      csv = """
      ReportDate,CurrencyPrimary,Symbol,SubCategory,Quantity,MarkPrice,PositionValue,CostBasisPrice,CostBasisMoney,OpenPrice,PercentOfNAV,ListingExchange,AssetClass,FXRateToBase,ISIN,FIGI
      2026-01-01,EUR,TEST,COMMON,100,10,1000,9,900,9,5,HEX,STK,1,FI0000000001,BBG000000001
      """

      [position] = CsvParser.parse(csv, @snapshot_id, ~D[2026-01-01])
      assert position.symbol == "TEST"
      assert position.isin == "FI0000000001"
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
