defmodule Dividendsomatic.StocksTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Stocks
  alias Dividendsomatic.Stocks.{CompanyProfile, StockQuote}

  describe "stock quotes" do
    test "list_cached_quotes/0 returns empty list when no quotes" do
      assert Stocks.list_cached_quotes() == []
    end

    test "get_quote/1 returns error when API not configured" do
      # Without FINNHUB_API_KEY, should return not_configured
      result = Stocks.get_quote("AAPL")
      assert result == {:error, :not_configured}
    end
  end

  describe "company profiles" do
    test "get_company_profile/1 returns error when API not configured" do
      result = Stocks.get_company_profile("AAPL")
      assert result == {:error, :not_configured}
    end
  end

  describe "stock quote schema" do
    test "changeset validates required fields" do
      changeset = StockQuote.changeset(%StockQuote{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).fetched_at
    end

    test "changeset accepts valid data" do
      attrs = %{
        symbol: "AAPL",
        current_price: Decimal.new("150.00"),
        fetched_at: DateTime.utc_now()
      }

      changeset = StockQuote.changeset(%StockQuote{}, attrs)
      assert changeset.valid?
    end
  end

  describe "company profile schema" do
    test "changeset validates required fields" do
      changeset = CompanyProfile.changeset(%CompanyProfile{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).fetched_at
    end

    test "changeset accepts valid data" do
      attrs = %{
        symbol: "AAPL",
        name: "Apple Inc.",
        fetched_at: DateTime.utc_now()
      }

      changeset = CompanyProfile.changeset(%CompanyProfile{}, attrs)
      assert changeset.valid?
    end
  end
end
