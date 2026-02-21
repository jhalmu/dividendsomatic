defmodule Dividendsomatic.Portfolio.SchemaIntegrityTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.SchemaIntegrity

  alias Dividendsomatic.Portfolio.{
    DividendPayment,
    Instrument,
    PortfolioSnapshot,
    Trade
  }

  alias Dividendsomatic.Repo

  defp create_instrument(attrs \\ %{}) do
    defaults = %{
      isin:
        "US#{:rand.uniform(999_999_999) |> Integer.to_string() |> String.pad_leading(10, "0")}",
      name: "Test Corp",
      currency: "USD"
    }

    %Instrument{}
    |> Instrument.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_trade(instrument, attrs \\ %{}) do
    defaults = %{
      external_id: "trade_#{Ecto.UUID.generate()}",
      instrument_id: instrument.id,
      trade_date: ~D[2025-01-15],
      quantity: Decimal.new("100"),
      price: Decimal.new("50.00"),
      amount: Decimal.new("5000.00"),
      currency: "USD"
    }

    %Trade{}
    |> Trade.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_dividend_payment(instrument, attrs \\ %{}) do
    defaults = %{
      external_id: "dp_#{Ecto.UUID.generate()}",
      instrument_id: instrument.id,
      pay_date: ~D[2025-03-15],
      ex_date: ~D[2025-03-01],
      gross_amount: Decimal.new("100.00"),
      net_amount: Decimal.new("85.00"),
      currency: "USD"
    }

    %DividendPayment{}
    |> DividendPayment.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "check_all/0" do
    test "should return result map with all checks" do
      result = SchemaIntegrity.check_all()

      assert is_map(result)
      assert Map.has_key?(result, :total_checks)
      assert Map.has_key?(result, :total_issues)
      assert Map.has_key?(result, :issues)
      assert Map.has_key?(result, :by_severity)
      assert result.total_checks == 4
    end
  end

  describe "orphan_check/0" do
    test "should detect instruments with no trades or dividend payments" do
      # Create an orphan instrument (no trades, no dividends)
      create_instrument(%{isin: "XX0000000001", name: "Orphan Corp"})

      issues = SchemaIntegrity.orphan_check()
      orphan_issue = Enum.find(issues, &(&1.check == :orphan_instruments))

      assert orphan_issue
      assert orphan_issue.severity == :info
      assert orphan_issue.count >= 1
    end

    test "should not flag instruments with trades" do
      inst = create_instrument(%{isin: "XX0000000002", name: "Active Corp"})
      create_trade(inst)

      issues = SchemaIntegrity.orphan_check()
      orphan_details = Enum.find(issues, &(&1.check == :orphan_instruments))

      # If there's an orphan issue, our instrument shouldn't be in it
      if orphan_details do
        refute Enum.any?(orphan_details.details, &(&1.isin == "XX0000000002"))
      end
    end
  end

  describe "null_field_check/0" do
    test "should detect instruments missing currency" do
      %Instrument{}
      |> Ecto.Changeset.change(%{isin: "XX0000000003", name: "No Currency"})
      |> Repo.insert!()

      issues = SchemaIntegrity.null_field_check()
      currency_issue = Enum.find(issues, &(&1.check == :null_instrument_currency))

      assert currency_issue
      assert currency_issue.severity == :warning
      assert currency_issue.count >= 1
    end

    test "should detect non-EUR dividends missing fx_rate" do
      inst = create_instrument(%{isin: "XX0000000004"})

      create_dividend_payment(inst, %{
        currency: "USD",
        fx_rate: nil
      })

      issues = SchemaIntegrity.null_field_check()
      fx_issue = Enum.find(issues, &(&1.check == :null_fx_rate))

      assert fx_issue
      assert fx_issue.severity == :warning
    end
  end

  describe "fk_integrity_check/0" do
    test "should return empty list when all FKs are valid" do
      inst = create_instrument(%{isin: "XX0000000005"})
      create_trade(inst)

      issues = SchemaIntegrity.fk_integrity_check()

      # Should have no FK issues (DB-level constraints prevent orphans)
      fk_trade = Enum.find(issues, &(&1.check == :fk_trade_instrument))
      assert is_nil(fk_trade)
    end
  end

  describe "duplicate_check/0" do
    test "should return empty list when no duplicates exist" do
      # Unique indexes prevent duplicates at DB level, so this check
      # is a safety net. Verify it runs cleanly with no false positives.
      inst = create_instrument(%{isin: "XX0000000010"})
      create_trade(inst, %{external_id: "unique_1"})
      create_trade(inst, %{external_id: "unique_2"})

      issues = SchemaIntegrity.duplicate_check()
      assert issues == []
    end
  end
end
