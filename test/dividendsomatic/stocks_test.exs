defmodule Dividendsomatic.StocksTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks
  alias Dividendsomatic.Stocks.{CompanyProfile, StockQuote}

  describe "stock quote schema" do
    test "should reject empty changeset" do
      changeset = StockQuote.changeset(%StockQuote{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).fetched_at
    end

    test "should accept valid quote data" do
      attrs = %{
        symbol: "AAPL",
        current_price: Decimal.new("150.00"),
        change: Decimal.new("2.50"),
        percent_change: Decimal.new("1.69"),
        high: Decimal.new("152.00"),
        low: Decimal.new("148.00"),
        open: Decimal.new("149.00"),
        previous_close: Decimal.new("147.50"),
        fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      changeset = StockQuote.changeset(%StockQuote{}, attrs)
      assert changeset.valid?
    end

    test "should persist and retrieve quote" do
      attrs = %{
        symbol: "MSFT",
        current_price: Decimal.new("400.00"),
        fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      {:ok, quote} =
        %StockQuote{}
        |> StockQuote.changeset(attrs)
        |> Repo.insert()

      assert quote.symbol == "MSFT"
      assert Decimal.equal?(quote.current_price, Decimal.new("400.00"))
    end
  end

  describe "company profile schema" do
    test "should reject empty changeset" do
      changeset = CompanyProfile.changeset(%CompanyProfile{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).fetched_at
    end

    test "should accept valid profile data" do
      attrs = %{
        symbol: "AAPL",
        name: "Apple Inc.",
        country: "US",
        currency: "USD",
        exchange: "NASDAQ",
        sector: "Technology",
        industry: "Consumer Electronics",
        fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      changeset = CompanyProfile.changeset(%CompanyProfile{}, attrs)
      assert changeset.valid?
    end

    test "should persist and retrieve profile" do
      attrs = %{
        symbol: "GOOGL",
        name: "Alphabet Inc.",
        country: "US",
        fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      {:ok, profile} =
        %CompanyProfile{}
        |> CompanyProfile.changeset(attrs)
        |> Repo.insert()

      assert profile.symbol == "GOOGL"
      assert profile.name == "Alphabet Inc."
    end
  end

  describe "list_cached_quotes/0" do
    test "should return empty list when no quotes" do
      assert Stocks.list_cached_quotes() == []
    end

    test "should return cached quotes sorted by symbol" do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.insert!(%StockQuote{symbol: "MSFT", fetched_at: now})
      Repo.insert!(%StockQuote{symbol: "AAPL", fetched_at: now})

      quotes = Stocks.list_cached_quotes()
      assert length(quotes) == 2
      assert Enum.at(quotes, 0).symbol == "AAPL"
      assert Enum.at(quotes, 1).symbol == "MSFT"
    end
  end

  describe "get_quote/1" do
    test "should return not_configured when API key is missing" do
      assert Stocks.get_quote("AAPL") == {:error, :not_configured}
    end

    test "should return cached quote when fresh" do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.insert!(%StockQuote{
        symbol: "AAPL",
        current_price: Decimal.new("150.00"),
        fetched_at: now
      })

      assert {:ok, quote} = Stocks.get_quote("AAPL")
      assert quote.symbol == "AAPL"
      assert Decimal.equal?(quote.current_price, Decimal.new("150.00"))
    end

    test "should try to refresh stale cached quote" do
      stale_time = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -1000, :second)

      Repo.insert!(%StockQuote{
        symbol: "AAPL",
        current_price: Decimal.new("150.00"),
        fetched_at: stale_time
      })

      # Without API key, refresh will fail with :not_configured
      assert Stocks.get_quote("AAPL") == {:error, :not_configured}
    end
  end

  describe "get_company_profile/1" do
    test "should return not_configured when API key is missing" do
      assert Stocks.get_company_profile("AAPL") == {:error, :not_configured}
    end

    test "should return cached profile when fresh" do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.insert!(%CompanyProfile{
        symbol: "AAPL",
        name: "Apple Inc.",
        fetched_at: now
      })

      assert {:ok, profile} = Stocks.get_company_profile("AAPL")
      assert profile.name == "Apple Inc."
    end
  end

  describe "get_quotes/1" do
    test "should return map of symbol to quote or nil" do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.insert!(%StockQuote{
        symbol: "AAPL",
        current_price: Decimal.new("150.00"),
        fetched_at: now
      })

      result = Stocks.get_quotes(["AAPL", "UNKNOWN"])

      assert %StockQuote{} = result["AAPL"]
      assert is_nil(result["UNKNOWN"])
    end
  end

  describe "refresh_quote/1" do
    test "should return not_configured without API key" do
      assert Stocks.refresh_quote("AAPL") == {:error, :not_configured}
    end
  end
end
