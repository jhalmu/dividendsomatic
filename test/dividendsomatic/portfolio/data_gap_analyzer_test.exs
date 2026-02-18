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

  describe "analyze_snapshot_gaps/0 boundary" do
    test "should not detect exactly 7-day gap (boundary: >7 required)" do
      insert_snapshot(~D[2024-01-01])
      insert_snapshot(~D[2024-01-08])

      gaps = DataGapAnalyzer.analyze_snapshot_gaps()
      assert gaps == []
    end

    test "should detect 8-day gap" do
      insert_snapshot(~D[2024-01-01])
      insert_snapshot(~D[2024-01-09])

      gaps = DataGapAnalyzer.analyze_snapshot_gaps()
      assert length(gaps) == 1
      assert hd(gaps).days == 8
    end
  end

  describe "analyze_dividend_gaps/0 edge cases" do
    test "should detect multiple gaps for same stock" do
      insert_dividend("AAPL", "US0378331005", ~D[2020-01-15], "0.77")
      insert_dividend("AAPL", "US0378331005", ~D[2022-06-15], "0.23")
      insert_dividend("AAPL", "US0378331005", ~D[2024-11-15], "0.25")

      gaps = DataGapAnalyzer.analyze_dividend_gaps()
      assert length(gaps) == 1
      aapl = hd(gaps)
      assert length(aapl.gaps) == 2
    end

    test "should handle single-dividend stocks (no gaps possible)" do
      insert_dividend("ONLY", "US9999999999", ~D[2024-01-15], "1.00")

      gaps = DataGapAnalyzer.analyze_dividend_gaps()
      assert gaps == []
    end
  end

  describe "missing_by_year_chunks/0" do
    test "should return empty list with no data" do
      assert DataGapAnalyzer.missing_by_year_chunks() == []
    end

    test "should return chunks when data exists across multiple years" do
      insert_snapshot(~D[2022-01-15])
      insert_snapshot(~D[2024-06-15])

      chunks = DataGapAnalyzer.missing_by_year_chunks()
      assert length(chunks) >= 2
      assert hd(chunks).from == ~D[2022-01-15]
      # Each chunk should have expected fields
      assert is_number(hd(chunks).coverage_pct)
      assert is_integer(hd(chunks).snapshot_count)
    end
  end

  describe "summary/0" do
    test "should return correct date ranges when data exists" do
      insert_snapshot(~D[2024-01-15])
      insert_snapshot(~D[2024-06-15])
      insert_dividend("MSFT", "US5949181045", ~D[2024-03-15], "0.75")

      summary = DataGapAnalyzer.summary()
      assert summary.dividend_count == 1
      assert summary.snapshot_count == 2
      assert summary.dividend_range.min == ~D[2024-03-15]
      assert summary.dividend_range.max == ~D[2024-03-15]
      assert summary.snapshot_range.min == ~D[2024-01-15]
      assert summary.snapshot_range.max == ~D[2024-06-15]
    end
  end

  describe "analyze/0 with populated data" do
    test "should build chunks from snapshot data spanning >1 year" do
      insert_snapshot(~D[2022-06-01])
      insert_snapshot(~D[2023-12-01])

      report = DataGapAnalyzer.analyze()
      assert report.chunks != []
      first_chunk = hd(report.chunks)
      assert first_chunk.calendar_days <= 364
    end

    test "should calculate coverage_pct correctly" do
      # Insert 5 snapshots spread across a single chunk
      for i <- 0..4 do
        insert_snapshot(Date.add(~D[2024-01-01], i * 7))
      end

      report = DataGapAnalyzer.analyze()
      assert report.chunks != []
      first_chunk = hd(report.chunks)
      assert first_chunk.snapshot_count == 5
      assert first_chunk.coverage_pct > 0
      assert first_chunk.coverage_pct < 100
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
