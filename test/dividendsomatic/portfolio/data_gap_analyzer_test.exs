defmodule Dividendsomatic.Portfolio.DataGapAnalyzerTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.DataGapAnalyzer
  alias Dividendsomatic.Portfolio.{Dividend, PortfolioSnapshot}

  describe "analyze/0" do
    test "should return a complete report structure with empty data" do
      report = DataGapAnalyzer.analyze()

      assert is_list(report.chunks)
      assert is_list(report.dividend_gaps)
      assert is_list(report.snapshot_gaps)
      assert is_map(report.summary)
    end

    test "should include summary counts" do
      report = DataGapAnalyzer.analyze()

      assert report.summary.dividend_count == 0
      assert report.summary.snapshot_count == 0
      assert report.summary.transaction_count == 0
    end
  end

  describe "analyze_dividend_gaps/0" do
    test "should detect gaps >400 days between consecutive dividends" do
      # Insert dividends with a large gap
      insert_dividend("AAPL", "US0378331005", ~D[2020-01-15], "0.77")
      insert_dividend("AAPL", "US0378331005", ~D[2022-06-15], "0.23")

      gaps = DataGapAnalyzer.analyze_dividend_gaps()
      assert length(gaps) == 1

      [aapl_gap] = gaps
      assert aapl_gap.symbol == "AAPL"
      assert length(aapl_gap.gaps) == 1
      assert hd(aapl_gap.gaps).days > 400
    end

    test "should not flag gaps <= 400 days" do
      insert_dividend("MSFT", "US5949181045", ~D[2024-01-15], "0.75")
      insert_dividend("MSFT", "US5949181045", ~D[2024-04-15], "0.75")

      gaps = DataGapAnalyzer.analyze_dividend_gaps()
      assert gaps == []
    end

    test "should handle empty dividend data" do
      assert DataGapAnalyzer.analyze_dividend_gaps() == []
    end
  end

  describe "analyze_snapshot_gaps/0" do
    test "should detect gaps >7 days between snapshots" do
      insert_snapshot(~D[2024-01-15])
      insert_snapshot(~D[2024-02-15])

      gaps = DataGapAnalyzer.analyze_snapshot_gaps()
      assert length(gaps) == 1
      assert hd(gaps).days == 31
    end

    test "should not flag gaps <= 7 days" do
      insert_snapshot(~D[2024-01-15])
      insert_snapshot(~D[2024-01-16])

      gaps = DataGapAnalyzer.analyze_snapshot_gaps()
      assert gaps == []
    end

    test "should handle empty snapshot data" do
      assert DataGapAnalyzer.analyze_snapshot_gaps() == []
    end
  end

  describe "missing_by_year_chunks/0" do
    test "should return empty list with no data" do
      assert DataGapAnalyzer.missing_by_year_chunks() == []
    end
  end

  defp insert_dividend(symbol, isin, ex_date, amount) do
    %Dividend{}
    |> Dividend.changeset(%{
      symbol: symbol,
      isin: isin,
      ex_date: ex_date,
      amount: Decimal.new(amount),
      currency: "USD"
    })
    |> Repo.insert!()
  end

  defp insert_snapshot(date) do
    %PortfolioSnapshot{}
    |> PortfolioSnapshot.changeset(%{
      date: date,
      source: "test",
      data_quality: "actual",
      total_value: Decimal.new("10000"),
      total_cost: Decimal.new("8000")
    })
    |> Repo.insert!()
  end
end
