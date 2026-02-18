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
    test "should flag per-share amount of 281.77 (> 50)" do
      div = build_dividend("AGNC", "US00123Q1040", ~D[2024-01-01], "281.77", "USD")
      issues = DividendValidator.suspicious_amounts([div])
      assert length(issues) == 1
      assert hd(issues).type == :suspicious_amount
    end

    test "should not flag normal amount of 45.00 (< 50)" do
      div = build_dividend("TEST", nil, ~D[2024-01-01], "45.00", "USD")
      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should not flag total_net amounts over 50" do
      div =
        build_dividend("TEST", nil, ~D[2024-01-01], "5000.00", "USD", amount_type: "total_net")

      assert DividendValidator.suspicious_amounts([div]) == []
    end

    test "should not flag normal per-share amounts" do
      div = build_dividend("TEST", nil, ~D[2024-01-01], "2.50", "USD")
      assert DividendValidator.suspicious_amounts([div]) == []
    end
  end

  describe "inconsistent_amounts_per_stock/1" do
    test "should flag same stock with per_share amounts varying >10x" do
      divs = [
        build_dividend("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_dividend("AGNC", "US00123Q1040", ~D[2024-02-01], "0.12", "USD"),
        build_dividend("AGNC", "US00123Q1040", ~D[2024-03-01], "281.77", "USD")
      ]

      issues = DividendValidator.inconsistent_amounts_per_stock(divs)
      assert length(issues) == 1
      assert hd(issues).type == :inconsistent_amount
      assert hd(issues).symbol == "AGNC"
    end

    test "should not flag consistent dividends with small variation" do
      divs = [
        build_dividend("AAPL", "US0378331005", ~D[2024-01-01], "0.24", "USD"),
        build_dividend("AAPL", "US0378331005", ~D[2024-04-01], "0.25", "USD")
      ]

      assert DividendValidator.inconsistent_amounts_per_stock(divs) == []
    end

    test "should not flag single-dividend stocks" do
      divs = [build_dividend("AAPL", "US0378331005", ~D[2024-01-01], "0.24", "USD")]
      assert DividendValidator.inconsistent_amounts_per_stock(divs) == []
    end

    test "should group by ISIN, not symbol" do
      # Same ISIN, different symbols - should group together
      divs = [
        build_dividend("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_dividend("AGNC INC", "US00123Q1040", ~D[2024-02-01], "0.12", "USD"),
        build_dividend("AGNC INC", "US00123Q1040", ~D[2024-03-01], "281.77", "USD")
      ]

      issues = DividendValidator.inconsistent_amounts_per_stock(divs)
      assert length(issues) == 1
    end

    test "should only check per_share records (skip total_net)" do
      divs = [
        build_dividend("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_dividend("AGNC", "US00123Q1040", ~D[2024-02-01], "0.12", "USD"),
        build_dividend("AGNC", "US00123Q1040", ~D[2024-03-01], "281.77", "USD",
          amount_type: "total_net"
        )
      ]

      assert DividendValidator.inconsistent_amounts_per_stock(divs) == []
    end
  end

  describe "mixed_amount_types_per_stock/1" do
    test "should flag stock with both per_share and total_net records" do
      divs = [
        build_dividend("AGNC", "US00123Q1040", ~D[2024-01-01], "0.12", "USD"),
        build_dividend("AGNC", "US00123Q1040", ~D[2024-02-01], "281.77", "USD",
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
        build_dividend("AAPL", "US0378331005", ~D[2024-01-01], "0.24", "USD"),
        build_dividend("AAPL", "US0378331005", ~D[2024-04-01], "0.25", "USD")
      ]

      assert DividendValidator.mixed_amount_types_per_stock(divs) == []
    end
  end

  describe "validate/0 integration" do
    test "should catch AGNC-like records with inconsistent amounts" do
      insert_dividend("AGNC", "US00123Q1040", ~D[2024-01-15], "0.12", "USD")

      insert_dividend("AGNC", "US00123Q1040", ~D[2024-02-15], "0.12", "USD", "ibkr",
        amount_type: "per_share"
      )

      insert_dividend("AGNC", "US00123Q1040", ~D[2024-03-15], "281.77", "USD", "ibkr",
        amount_type: "per_share"
      )

      report = DividendValidator.validate()
      types = Enum.map(report.issues, & &1.type)
      assert :inconsistent_amount in types
      assert :suspicious_amount in types
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

  defp build_dividend(symbol, isin, ex_date, amount, currency, opts \\ []) do
    %Dividend{
      symbol: symbol,
      isin: isin,
      ex_date: ex_date,
      amount: Decimal.new(amount),
      currency: currency,
      amount_type: Keyword.get(opts, :amount_type, "per_share"),
      gross_rate: opts |> Keyword.get(:gross_rate) |> maybe_decimal(),
      net_amount: opts |> Keyword.get(:net_amount) |> maybe_decimal(),
      quantity_at_record: opts |> Keyword.get(:quantity_at_record) |> maybe_decimal()
    }
  end

  defp maybe_decimal(nil), do: nil
  defp maybe_decimal(val) when is_binary(val), do: Decimal.new(val)
  defp maybe_decimal(%Decimal{} = val), do: val

  defp insert_dividend(symbol, isin, ex_date, amount, currency, source \\ "test", opts \\ []) do
    attrs =
      %{
        symbol: symbol,
        isin: isin,
        ex_date: ex_date,
        amount: Decimal.new(amount),
        currency: currency,
        source: source
      }
      |> Map.merge(Map.new(opts))

    %Dividend{}
    |> Dividend.changeset(attrs)
    |> Repo.insert!()
  end
end
