defmodule Dividendsomatic.Portfolio.IntegrityCheckerTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.IntegrityChecker

  @actions_data %{
    transactions: [
      %{
        activity_code: "DIV",
        activity_description: "TLS dividend",
        symbol: "TELIA1",
        isin: "SE0000667925",
        currency: "EUR",
        date: ~D[2026-02-11],
        settle_date: ~D[2026-02-11],
        amount: Decimal.new("471.84"),
        debit: nil,
        credit: Decimal.new("471.84"),
        trade_quantity: nil,
        trade_price: nil,
        trade_id: "",
        transaction_id: "5415909234",
        buy_sell: "",
        fx_rate: Decimal.new("1")
      },
      %{
        activity_code: "PIL",
        activity_description: "AGNC PIL",
        symbol: "AGNC",
        isin: "US00123Q1040",
        currency: "EUR",
        date: ~D[2026-02-10],
        settle_date: ~D[2026-02-10],
        amount: Decimal.new("201.77"),
        debit: nil,
        credit: Decimal.new("201.77"),
        trade_quantity: nil,
        trade_price: nil,
        trade_id: "",
        transaction_id: "5401920872",
        buy_sell: "",
        fx_rate: Decimal.new("1")
      },
      %{
        activity_code: "BUY",
        activity_description: "Buy 1000 NDA FI",
        symbol: "NDA FI",
        isin: "FI4000297767",
        currency: "EUR",
        date: ~D[2026-02-13],
        settle_date: ~D[2026-02-17],
        amount: Decimal.new("-16197.14"),
        debit: Decimal.new("-16197.14"),
        credit: nil,
        trade_quantity: Decimal.new("1000"),
        trade_price: Decimal.new("16.185"),
        trade_id: "1319331815",
        transaction_id: "5424348166",
        buy_sell: "BUY",
        fx_rate: Decimal.new("1")
      }
    ],
    summary: %{
      from_date: ~D[2026-02-09],
      to_date: ~D[2026-02-13],
      starting_cash: Decimal.new("-228542.73"),
      dividends: Decimal.new("471.84"),
      commissions: Decimal.new("-23.47"),
      ending_cash: Decimal.new("-256368.46")
    }
  }

  describe "reconcile_dividends/1" do
    test "should return a check result with dividend info" do
      result = IntegrityChecker.reconcile_dividends(@actions_data)

      assert result.name == "Dividend Reconciliation"
      assert result.status in [:pass, :warn, :fail]
      assert is_binary(result.message)
      assert is_list(result.details)
    end

    test "should count DIV and PIL transactions" do
      result = IntegrityChecker.reconcile_dividends(@actions_data)
      # Should find 2 dividend entries (DIV + PIL)
      assert String.contains?(result.message, "2 records")
    end
  end

  describe "reconcile_trades/1" do
    test "should return a check result with trade info" do
      result = IntegrityChecker.reconcile_trades(@actions_data)

      assert result.name == "Trade Reconciliation"
      assert result.status in [:pass, :warn, :fail]
      # Should find 1 stock trade (NDA FI BUY)
      assert String.contains?(result.message, "1 stock trades")
    end
  end

  describe "find_missing_isins/1" do
    test "should identify ISINs not in DB" do
      result = IntegrityChecker.find_missing_isins(@actions_data)

      assert result.name == "Missing ISINs"
      assert result.status in [:pass, :warn, :fail]
      assert is_list(result.details)
    end
  end

  describe "check_summary_totals/1" do
    test "should extract summary totals" do
      result = IntegrityChecker.check_summary_totals(@actions_data)

      assert result.name == "Summary Totals"
      assert result.status == :pass
      assert String.contains?(result.message, "2026-02-09")
      assert String.contains?(result.message, "2026-02-13")
    end
  end
end
