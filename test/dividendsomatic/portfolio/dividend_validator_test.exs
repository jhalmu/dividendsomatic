defmodule Dividendsomatic.Portfolio.DividendValidatorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{
    DividendPayment,
    DividendValidator,
    Instrument,
    InstrumentAlias
  }

  describe "validate/0" do
    test "should return clean report with no data" do
      report = DividendValidator.validate()
      assert report.total_checked == 0
      assert report.issue_count == 0
      assert report.issues == []
    end

    test "should return clean report with valid data" do
      insert_dividend_payment("AAPL", "US0378331005", ~D[2024-01-15], "0.24", "USD")

      report = DividendValidator.validate()
      assert report.total_checked == 1
      assert report.issue_count == 0
    end
  end

  describe "invalid_currencies/1" do
    test "should flag unknown currency codes" do
      div = build_div_map("TEST", nil, ~D[2024-01-01], "1.00", "XYZ")
      issues = DividendValidator.invalid_currencies([div])
      assert length(issues) == 1
      assert hd(issues).type == :invalid_currency
    end

    test "should accept valid currency codes" do
      for currency <- ~w(USD EUR CAD GBP JPY HKD SEK NOK) do
        div = build_div_map("TEST", nil, ~D[2024-01-01], "1.00", currency)
        assert DividendValidator.invalid_currencies([div]) == []
      end
    end
  end

  describe "isin_currency_mismatches/1" do
    test "should flag US ISIN with non-USD currency" do
      div = build_div_map("TEST", "US0378331005", ~D[2024-01-01], "1.00", "EUR")
      issues = DividendValidator.isin_currency_mismatches([div])
      assert length(issues) == 1
      assert hd(issues).type == :isin_currency_mismatch
    end

    test "should accept US ISIN with USD currency" do
      div = build_div_map("TEST", "US0378331005", ~D[2024-01-01], "1.00", "USD")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should accept Finnish ISIN with EUR currency" do
      div = build_div_map("TEST", "FI0009800643", ~D[2024-01-01], "1.00", "EUR")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should skip dividends without ISIN" do
      div = build_div_map("TEST", nil, ~D[2024-01-01], "1.00", "USD")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should accept IE ISIN with USD currency" do
      div = build_div_map("CRH", "IE0001827041", ~D[2024-01-01], "1.00", "USD")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should accept IE ISIN with EUR currency" do
      div = build_div_map("KERRY", "IE0004906560", ~D[2024-01-01], "1.00", "EUR")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should skip unknown country prefixes not in map" do
      div = build_div_map("TEST", "XX1234567890", ~D[2024-01-01], "1.00", "BRL")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should skip LEGACY: ISINs" do
      div = build_div_map("TEST", "LEGACY:TEST", ~D[2024-01-01], "1.00", "USD")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end
  end

  describe "suspicious_amounts/1" do
    test "should flag USD per-share amount over 50" do
      div = build_div_map("AGNC", "US00123Q1040", ~D[2024-01-01], "281.77", "USD")
      issues = DividendValidator.suspicious_amounts([div])
      assert length(issues) == 1
      assert hd(issues).type == :suspicious_amount
    end

    test "should not flag USD amount under 50" do
      div = build_div_map("TEST", nil, ~D[2024-01-01], "45.00", "USD")
      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should not flag total_net amounts" do
      div =
        build_div_map("TEST", nil, ~D[2024-01-01], "5000.00", "USD", amount_type: "total_net")

      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should not flag normal GBp amount under 4000" do
      div = build_div_map("BHP", nil, ~D[2024-01-01], "151.46", "GBp")
      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should flag GBp amount over 4000" do
      div = build_div_map("TEST", nil, ~D[2024-01-01], "5000.00", "GBp")
      issues = DividendValidator.suspicious_amounts([div])
      assert length(issues) == 1
    end

    test "should not flag normal NOK amount under 550" do
      div = build_div_map("FROo", nil, ~D[2024-01-01], "236.60", "NOK")
      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should not flag normal JPY amount under 7500" do
      div = build_div_map("8031.T", nil, ~D[2024-01-01], "55.00", "JPY")
      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should not flag SEK amount at 549 (under 550 threshold)" do
      div = build_div_map("TEST", nil, ~D[2024-01-01], "549.00", "SEK")
      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should flag SEK amount at 551 (over 550 threshold)" do
      div = build_div_map("TEST", nil, ~D[2024-01-01], "551.00", "SEK")
      issues = DividendValidator.suspicious_amounts([div])
      assert length(issues) == 1
      assert hd(issues).type == :suspicious_amount
    end

    test "should use default threshold of 50 for unknown currency" do
      div = build_div_map("TEST", nil, ~D[2024-01-01], "51.00", "BRL")
      issues = DividendValidator.suspicious_amounts([div])
      assert length(issues) == 1

      div_under = build_div_map("TEST", nil, ~D[2024-01-01], "49.00", "BRL")
      assert DividendValidator.suspicious_amounts([div_under]) == []
    end
  end

  describe "inconsistent_amounts_per_stock/1" do
    test "should flag same stock with per_share amounts varying >10x" do
      divs = [
        build_div_map("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_div_map("AGNC", "US00123Q1040", ~D[2024-02-01], "0.12", "USD"),
        build_div_map("AGNC", "US00123Q1040", ~D[2024-03-01], "281.77", "USD")
      ]

      issues = DividendValidator.inconsistent_amounts_per_stock(divs)
      assert length(issues) == 1
      assert hd(issues).type == :inconsistent_amount
      assert hd(issues).symbol == "AGNC"
    end

    test "should not flag consistent dividends with small variation" do
      divs = [
        build_div_map("AAPL", "US0378331005", ~D[2024-01-01], "0.24", "USD"),
        build_div_map("AAPL", "US0378331005", ~D[2024-04-01], "0.25", "USD")
      ]

      assert DividendValidator.inconsistent_amounts_per_stock(divs) == []
    end

    test "should not flag single-dividend stocks" do
      divs = [build_div_map("AAPL", "US0378331005", ~D[2024-01-01], "0.24", "USD")]
      assert DividendValidator.inconsistent_amounts_per_stock(divs) == []
    end

    test "should group by ISIN, not symbol" do
      # Same ISIN, different symbols - should group together
      divs = [
        build_div_map("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_div_map("AGNC INC", "US00123Q1040", ~D[2024-02-01], "0.12", "USD"),
        build_div_map("AGNC INC", "US00123Q1040", ~D[2024-03-01], "281.77", "USD")
      ]

      issues = DividendValidator.inconsistent_amounts_per_stock(divs)
      assert length(issues) == 1
    end

    test "should only check per_share records (skip total_net)" do
      divs = [
        build_div_map("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_div_map("AGNC", "US00123Q1040", ~D[2024-02-01], "0.12", "USD"),
        build_div_map("AGNC", "US00123Q1040", ~D[2024-03-01], "281.77", "USD",
          amount_type: "total_net"
        )
      ]

      assert DividendValidator.inconsistent_amounts_per_stock(divs) == []
    end

    test "should fall back to symbol key when ISIN is nil" do
      divs = [
        build_div_map("MYSTERY", nil, ~D[2024-01-01], "0.10", "USD"),
        build_div_map("MYSTERY", nil, ~D[2024-02-01], "0.10", "USD"),
        build_div_map("MYSTERY", nil, ~D[2024-03-01], "50.00", "USD")
      ]

      issues = DividendValidator.inconsistent_amounts_per_stock(divs)
      assert length(issues) == 1
      assert hd(issues).type == :inconsistent_amount
    end

    test "should not flag when all amounts are zero (median=0 guard)" do
      divs = [
        build_div_map("ZERO", nil, ~D[2024-01-01], "0.001", "USD"),
        build_div_map("ZERO", nil, ~D[2024-02-01], "0.001", "USD")
      ]

      assert DividendValidator.inconsistent_amounts_per_stock(divs) == []
    end
  end

  describe "mixed_amount_types_per_stock/1" do
    test "should flag stock with both per_share and total_net records" do
      divs = [
        build_div_map("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_div_map("AGNC", "US00123Q1040", ~D[2024-02-01], "281.77", "USD",
          amount_type: "total_net"
        )
      ]

      issues = DividendValidator.mixed_amount_types_per_stock(divs)
      assert length(issues) == 1
      assert hd(issues).type == :mixed_amount_types
      assert hd(issues).severity == :info
    end

    test "should not flag stock with only per_share records" do
      divs = [
        build_div_map("AAPL", "US0378331005", ~D[2024-01-01], "0.24", "USD"),
        build_div_map("AAPL", "US0378331005", ~D[2024-04-01], "0.25", "USD")
      ]

      assert DividendValidator.mixed_amount_types_per_stock(divs) == []
    end
  end

  describe "validate/0 integration" do
    test "should catch records with inconsistent amounts" do
      insert_dividend_payment("AGNC", "US00123Q1040", ~D[2024-01-15], "0.12", "USD")
      insert_dividend_payment("AGNC2", "US00123Q1040", ~D[2024-02-15], "0.12", "USD")
      insert_dividend_payment("AGNC3", "US00123Q1040", ~D[2024-03-15], "281.77", "USD")

      report = DividendValidator.validate()
      types = Enum.map(report.issues, & &1.type)
      assert :inconsistent_amount in types
      assert :suspicious_amount in types
    end

    test "should count all severity types in by_severity map" do
      # Insert data that triggers :warning (suspicious_amount)
      insert_dividend_payment("BIG", "US9999999999", ~D[2024-01-15], "100.00", "USD")

      report = DividendValidator.validate()
      assert is_map(report.by_severity)
      assert report.by_severity[:warning] >= 1
    end

    test "should return issues grouped correctly with multiple check types" do
      # suspicious_amount + isin_currency_mismatch
      insert_dividend_payment("WEIRDUS", "US1234567890", ~D[2024-01-15], "200.00", "EUR")

      report = DividendValidator.validate()
      types = Enum.map(report.issues, & &1.type)
      assert :suspicious_amount in types or :isin_currency_mismatch in types
      assert report.issue_count == length(report.issues)
    end
  end

  describe "cross_source_duplicates/0" do
    test "should detect duplicate ISIN+date records" do
      {instrument, _alias} = find_or_create_instrument("US0378331005", "AAPL")

      insert_dp(instrument, ~D[2024-01-15], "0.24", "USD", "ibkr-1")
      insert_dp(instrument, ~D[2024-01-15], "0.24", "USD", "yfinance-1")

      dupes = DividendValidator.cross_source_duplicates()
      assert length(dupes) == 1
      assert hd(dupes).type == :duplicate
    end

    test "should not flag unique ISIN+date combinations" do
      {instrument, _alias} = find_or_create_instrument("US0378331005", "AAPL")

      insert_dp(instrument, ~D[2024-01-15], "0.24", "USD", "ibkr-1")
      insert_dp(instrument, ~D[2024-04-15], "0.25", "USD", "ibkr-2")

      dupes = DividendValidator.cross_source_duplicates()
      assert dupes == []
    end
  end

  describe "suggest_threshold_adjustments/0" do
    test "should suggest threshold when currency has 3+ flags" do
      insert_dividend_payment("BDC1", "US1111111111", ~D[2024-01-15], "60.00", "USD")
      insert_dividend_payment("BDC2", "US2222222222", ~D[2024-02-15], "75.00", "USD")
      insert_dividend_payment("BDC3", "US3333333333", ~D[2024-03-15], "90.00", "USD")

      suggestions = DividendValidator.suggest_threshold_adjustments()
      assert length(suggestions) == 1

      suggestion = hd(suggestions)
      assert suggestion.currency == "USD"
      assert suggestion.current_threshold == "50"
      assert suggestion.flagged_count == 3
      assert String.to_integer(suggestion.suggested_threshold) >= 100
    end

    test "should ignore currencies with fewer than 3 flags" do
      insert_dividend_payment("BDC1", "US1111111111", ~D[2024-01-15], "60.00", "USD")
      insert_dividend_payment("BDC2", "US2222222222", ~D[2024-02-15], "75.00", "USD")

      suggestions = DividendValidator.suggest_threshold_adjustments()
      assert suggestions == []
    end

    test "should return empty list when no flags exist" do
      insert_dividend_payment("AAPL", "US0378331005", ~D[2024-01-15], "0.24", "USD")

      suggestions = DividendValidator.suggest_threshold_adjustments()
      assert suggestions == []
    end
  end

  describe "missing_fx_conversion/1" do
    test "should flag total_net non-EUR dividend with nil fx_rate" do
      div =
        build_div_map("TELIA1", "SE0000667925", ~D[2024-08-03], "400.00", "SEK",
          amount_type: "total_net"
        )

      issues = DividendValidator.missing_fx_conversion([div])
      assert length(issues) == 1
      assert hd(issues).type == :missing_fx_conversion
      assert hd(issues).severity == :warning
    end

    test "should flag total_net non-EUR dividend with fx_rate of 1.0" do
      div =
        build_div_map("TELIA1", "SE0000667925", ~D[2024-08-03], "400.00", "SEK",
          amount_type: "total_net",
          fx_rate: "1"
        )

      issues = DividendValidator.missing_fx_conversion([div])
      assert length(issues) == 1
    end

    test "should not flag total_net EUR dividend" do
      div =
        build_div_map("KESKOB", "FI0009000202", ~D[2024-04-15], "150.00", "EUR",
          amount_type: "total_net"
        )

      assert DividendValidator.missing_fx_conversion([div]) == []
    end

    test "should not flag total_net non-EUR dividend with valid fx_rate" do
      div =
        build_div_map("TELIA1", "SE0000667925", ~D[2024-08-03], "400.00", "SEK",
          amount_type: "total_net",
          fx_rate: "0.094"
        )

      assert DividendValidator.missing_fx_conversion([div]) == []
    end

    test "should not flag per_share dividends regardless of fx_rate" do
      div = build_div_map("AAPL", "US0378331005", ~D[2024-01-15], "0.24", "USD")
      assert DividendValidator.missing_fx_conversion([div]) == []
    end
  end

  # Build a plain map matching the validator's expected shape
  defp build_div_map(symbol, isin, ex_date, amount, currency, opts \\ []) do
    amount_type = Keyword.get(opts, :amount_type, "per_share")
    fx_rate = opts |> Keyword.get(:fx_rate) |> maybe_decimal()

    %{
      symbol: symbol,
      isin: isin,
      ex_date: ex_date,
      pay_date: ex_date,
      amount: Decimal.new(amount),
      net_amount: Decimal.new(amount),
      currency: currency,
      amount_type: amount_type,
      fx_rate: fx_rate,
      gross_rate: Decimal.new(amount),
      quantity_at_record: nil
    }
  end

  defp maybe_decimal(nil), do: nil
  defp maybe_decimal(val) when is_binary(val), do: Decimal.new(val)
  defp maybe_decimal(%Decimal{} = val), do: val

  # Insert a dividend_payment with instrument + alias (for integration tests)
  defp insert_dividend_payment(symbol, isin, pay_date, per_share, currency) do
    {instrument, _alias} = find_or_create_instrument(isin, symbol)
    ext_id = "test-#{symbol}-#{Date.to_iso8601(pay_date)}-#{System.unique_integer([:positive])}"
    insert_dp(instrument, pay_date, per_share, currency, ext_id)
  end

  defp find_or_create_instrument(isin, symbol) do
    instrument =
      case Repo.get_by(Instrument, isin: isin) do
        nil ->
          %Instrument{}
          |> Instrument.changeset(%{isin: isin, name: symbol})
          |> Repo.insert!()

        existing ->
          existing
      end

    alias_rec =
      case Repo.get_by(InstrumentAlias, instrument_id: instrument.id, symbol: symbol) do
        nil ->
          %InstrumentAlias{}
          |> InstrumentAlias.changeset(%{instrument_id: instrument.id, symbol: symbol})
          |> Repo.insert!()

        existing ->
          existing
      end

    {instrument, alias_rec}
  end

  defp insert_dp(instrument, pay_date, per_share, currency, external_id) do
    %DividendPayment{}
    |> DividendPayment.changeset(%{
      external_id: external_id,
      instrument_id: instrument.id,
      pay_date: pay_date,
      gross_amount: Decimal.new(per_share),
      net_amount: Decimal.new(per_share),
      per_share: Decimal.new(per_share),
      currency: currency
    })
    |> Repo.insert!()
  end
end
