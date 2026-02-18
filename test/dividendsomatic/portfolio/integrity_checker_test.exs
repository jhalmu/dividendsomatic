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

  describe "run_all_from_string/1" do
    test "should run checks from CSV string" do
      csv_string = build_minimal_actions_csv()
      result = IntegrityChecker.run_all_from_string(csv_string)

      assert {:ok, checks} = result
      assert is_list(checks)
      assert length(checks) == 4
      check_names = Enum.map(checks, & &1.name)
      assert "Dividend Reconciliation" in check_names
      assert "Trade Reconciliation" in check_names
      assert "Missing ISINs" in check_names
      assert "Summary Totals" in check_names
    end

    test "should return error for empty CSV string" do
      assert {:error, :empty_csv} = IntegrityChecker.run_all_from_string("")
    end
  end

  describe "edge cases" do
    test "should handle empty transactions list in actions data" do
      empty_data = %{
        transactions: [],
        summary: %{
          from_date: ~D[2026-02-09],
          to_date: ~D[2026-02-13],
          starting_cash: Decimal.new("-100000"),
          dividends: Decimal.new("0"),
          commissions: Decimal.new("0"),
          ending_cash: Decimal.new("-100000")
        }
      }

      result = IntegrityChecker.reconcile_dividends(empty_data)
      assert result.status == :warn
      assert String.contains?(result.message, "0 records")

      trade_result = IntegrityChecker.reconcile_trades(empty_data)
      assert trade_result.status == :warn
    end

    test "should return :warn when trade count diff is exactly 2 (boundary)" do
      # Build data with 2 trades in CSV, 0 in DB → diff = 2
      data_with_2_trades = %{
        transactions: [
          %{
            activity_code: "BUY",
            activity_description: "Buy",
            symbol: "AAPL",
            isin: "US0378331005",
            currency: "USD",
            date: ~D[2026-01-10],
            settle_date: ~D[2026-01-12],
            amount: Decimal.new("-5000"),
            debit: Decimal.new("-5000"),
            credit: nil,
            trade_quantity: Decimal.new("25"),
            trade_price: Decimal.new("200"),
            trade_id: "T1",
            transaction_id: "TX1",
            buy_sell: "BUY",
            fx_rate: Decimal.new("1")
          },
          %{
            activity_code: "BUY",
            activity_description: "Buy",
            symbol: "MSFT",
            isin: "US5949181045",
            currency: "USD",
            date: ~D[2026-01-11],
            settle_date: ~D[2026-01-13],
            amount: Decimal.new("-3000"),
            debit: Decimal.new("-3000"),
            credit: nil,
            trade_quantity: Decimal.new("10"),
            trade_price: Decimal.new("300"),
            trade_id: "T2",
            transaction_id: "TX2",
            buy_sell: "BUY",
            fx_rate: Decimal.new("1")
          }
        ],
        summary: %{
          from_date: ~D[2026-01-09],
          to_date: ~D[2026-01-13]
        }
      }

      result = IntegrityChecker.reconcile_trades(data_with_2_trades)
      assert result.status == :warn
      assert String.contains?(result.message, "diff: 2")
    end

    test "should return :warn when missing ISIN count is exactly 3 (boundary)" do
      data = %{
        transactions: [
          %{isin: "XX0000000001", symbol: "SYM1", activity_code: "DIV"},
          %{isin: "XX0000000002", symbol: "SYM2", activity_code: "DIV"},
          %{isin: "XX0000000003", symbol: "SYM3", activity_code: "DIV"}
        ]
      }

      result = IntegrityChecker.find_missing_isins(data)
      assert result.status == :warn
      assert String.contains?(result.message, "3 not in DB")
    end
  end

  # Builds a minimal valid Actions CSV string for run_all_from_string/1 testing
  defp build_minimal_actions_csv do
    """
    ActivityCode,ActivityDescription,Symbol,ISIN,CurrencyPrimary,Date,SettleDate,Amount,Debit,Credit,TradeQuantity,TradePrice,TradeID,TransactionID,Buy/Sell,FXRateToBase
    DIV,Dividend,AAPL,US0378331005,USD,2026-02-10,2026-02-10,100.00,,100.00,,,,,1
    """
  end
end
