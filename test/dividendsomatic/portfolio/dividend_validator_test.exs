defmodule Dividendsomatic.Portfolio.DividendValidatorTest do
  use Dividendsomatic.DataCase, async: true

  alias Dividendsomatic.Portfolio.{Dividend, DividendValidator}

  describe "validate/0" do
    test "should return clean report with no data" do
      report = DividendValidator.validate()
      assert report.total_checked == 0
      assert report.issue_count == 0
      assert report.issues == []
    end

    test "should return clean report with valid data" do
      insert_dividend("AAPL", "US0378331005", ~D[2024-01-15], "0.24", "USD")

      report = DividendValidator.validate()
      assert report.total_checked == 1
      assert report.issue_count == 0
    end
  end

  describe "invalid_currencies/1" do
    test "should flag unknown currency codes" do
      div = build_dividend("TEST", nil, ~D[2024-01-01], "1.00", "XYZ")
      issues = DividendValidator.invalid_currencies([div])
      assert length(issues) == 1
      assert hd(issues).type == :invalid_currency
    end

    test "should accept valid currency codes" do
      for currency <- ~w(USD EUR CAD GBP JPY HKD SEK NOK) do
        div = build_dividend("TEST", nil, ~D[2024-01-01], "1.00", currency)
        assert DividendValidator.invalid_currencies([div]) == []
      end
    end
  end

  describe "isin_currency_mismatches/1" do
    test "should flag US ISIN with non-USD currency" do
      div = build_dividend("TEST", "US0378331005", ~D[2024-01-01], "1.00", "EUR")
      issues = DividendValidator.isin_currency_mismatches([div])
      assert length(issues) == 1
      assert hd(issues).type == :isin_currency_mismatch
    end

    test "should accept US ISIN with USD currency" do
      div = build_dividend("TEST", "US0378331005", ~D[2024-01-01], "1.00", "USD")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should accept Finnish ISIN with EUR currency" do
      div = build_dividend("TEST", "FI0009800643", ~D[2024-01-01], "1.00", "EUR")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end

    test "should skip dividends without ISIN" do
      div = build_dividend("TEST", nil, ~D[2024-01-01], "1.00", "USD")
      assert DividendValidator.isin_currency_mismatches([div]) == []
    end
  end

  describe "suspicious_amounts/1" do
    test "should flag per-share amounts over 1000" do
      div = build_dividend("TEST", nil, ~D[2024-01-01], "1500.00", "USD")
      div = %{div | amount_type: "per_share"}
      issues = DividendValidator.suspicious_amounts([div])
      assert length(issues) == 1
      assert hd(issues).type == :suspicious_amount
    end

    test "should not flag total_net amounts over 1000" do
      div = build_dividend("TEST", nil, ~D[2024-01-01], "5000.00", "USD")
      div = %{div | amount_type: "total_net"}
      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should not flag normal per-share amounts" do
      div = build_dividend("TEST", nil, ~D[2024-01-01], "2.50", "USD")
      div = %{div | amount_type: "per_share"}
      assert DividendValidator.suspicious_amounts([div]) == []
    end
  end

  describe "cross_source_duplicates/0" do
    test "should detect duplicate ISIN+date records" do
      insert_dividend("AAPL", "US0378331005", ~D[2024-01-15], "0.24", "USD", "ibkr")
      insert_dividend("APPLE INC", "US0378331005", ~D[2024-01-15], "0.24", "USD", "yfinance")

      dupes = DividendValidator.cross_source_duplicates()
      assert length(dupes) == 1
      assert hd(dupes).type == :duplicate
    end

    test "should not flag unique ISIN+date combinations" do
      insert_dividend("AAPL", "US0378331005", ~D[2024-01-15], "0.24", "USD")
      insert_dividend("AAPL", "US0378331005", ~D[2024-04-15], "0.25", "USD")

      dupes = DividendValidator.cross_source_duplicates()
      assert dupes == []
    end
  end

  defp build_dividend(symbol, isin, ex_date, amount, currency) do
    %Dividend{
      symbol: symbol,
      isin: isin,
      ex_date: ex_date,
      amount: Decimal.new(amount),
      currency: currency,
      amount_type: "per_share"
    }
  end

  defp insert_dividend(symbol, isin, ex_date, amount, currency, source \\ "test") do
    %Dividend{}
    |> Dividend.changeset(%{
      symbol: symbol,
      isin: isin,
      ex_date: ex_date,
      amount: Decimal.new(amount),
      currency: currency,
      source: source
    })
    |> Repo.insert!()
  end
end
