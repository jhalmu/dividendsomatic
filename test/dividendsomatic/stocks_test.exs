defmodule Dividendsomatic.StocksTest do
  use Dividendsomatic.DataCase

  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks

  alias Dividendsomatic.Stocks.{
    CompanyNote,
    CompanyProfile,
    HistoricalPrice,
    StockMetric,
    StockQuote,
    SymbolMapping
  }

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

  describe "stock metric schema" do
    test "should reject empty changeset" do
      changeset = StockMetric.changeset(%StockMetric{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).symbol
      assert "can't be blank" in errors_on(changeset).fetched_at
    end

    test "should accept valid metric data" do
      attrs = %{
        symbol: "AAPL",
        pe_ratio: Decimal.new("28.50"),
        pb_ratio: Decimal.new("45.20"),
        eps: Decimal.new("6.42"),
        roe: Decimal.new("147.25"),
        roa: Decimal.new("28.30"),
        net_margin: Decimal.new("25.31"),
        operating_margin: Decimal.new("30.74"),
        debt_to_equity: Decimal.new("1.87"),
        current_ratio: Decimal.new("0.99"),
        fcf_margin: Decimal.new("26.15"),
        beta: Decimal.new("1.24"),
        payout_ratio: Decimal.new("15.47"),
        fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      changeset = StockMetric.changeset(%StockMetric{}, attrs)
      assert changeset.valid?
    end

    test "should persist and retrieve metric" do
      attrs = %{
        symbol: "MSFT",
        pe_ratio: Decimal.new("35.00"),
        roe: Decimal.new("40.50"),
        fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      {:ok, metric} =
        %StockMetric{}
        |> StockMetric.changeset(attrs)
        |> Repo.insert()

      assert metric.symbol == "MSFT"
      assert Decimal.equal?(metric.pe_ratio, Decimal.new("35.00"))
      assert Decimal.equal?(metric.roe, Decimal.new("40.50"))
    end
  end

  describe "get_financial_metrics/1" do
    test "should return not_configured when API key is missing" do
      assert Stocks.get_financial_metrics("AAPL") == {:error, :not_configured}
    end

    test "should return cached metrics when fresh" do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.insert!(%StockMetric{
        symbol: "AAPL",
        pe_ratio: Decimal.new("28.50"),
        roe: Decimal.new("147.25"),
        fetched_at: now
      })

      assert {:ok, metric} = Stocks.get_financial_metrics("AAPL")
      assert metric.symbol == "AAPL"
      assert Decimal.equal?(metric.pe_ratio, Decimal.new("28.50"))
    end

    test "should try to refresh stale cached metrics" do
      stale_time =
        DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -700_000, :second)

      Repo.insert!(%StockMetric{
        symbol: "AAPL",
        pe_ratio: Decimal.new("28.50"),
        fetched_at: stale_time
      })

      # Without API key, refresh will fail with :not_configured
      assert Stocks.get_financial_metrics("AAPL") == {:error, :not_configured}
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

  describe "company note schema" do
    test "should reject empty changeset" do
      changeset = CompanyNote.changeset(%CompanyNote{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).isin
    end

    test "should accept valid note with only ISIN" do
      changeset = CompanyNote.changeset(%CompanyNote{}, %{isin: "FI0009000202"})
      assert changeset.valid?
    end

    test "should reject invalid asset_type" do
      changeset =
        CompanyNote.changeset(%CompanyNote{}, %{isin: "FI0009000202", asset_type: "bond"})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).asset_type
    end
  end

  describe "get_company_note_by_isin/1" do
    test "should return nil when no note exists" do
      assert is_nil(Stocks.get_company_note_by_isin("NONEXISTENT"))
    end

    test "should return note when it exists" do
      {:ok, _} = Stocks.upsert_company_note(%{isin: "FI0009000202", symbol: "KESKOB"})

      note = Stocks.get_company_note_by_isin("FI0009000202")
      assert note.isin == "FI0009000202"
      assert note.symbol == "KESKOB"
    end
  end

  describe "get_or_init_company_note/2" do
    test "should return unsaved struct when no note exists" do
      note = Stocks.get_or_init_company_note("FI0009000202", %{symbol: "KESKOB"})

      assert is_nil(note.id)
      assert note.isin == "FI0009000202"
      assert note.symbol == "KESKOB"
    end

    test "should return existing note when it exists" do
      {:ok, created} = Stocks.upsert_company_note(%{isin: "FI0009000202", symbol: "KESKOB"})

      note = Stocks.get_or_init_company_note("FI0009000202")
      assert note.id == created.id
    end
  end

  describe "upsert_company_note/1" do
    test "should create a new note" do
      assert {:ok, note} =
               Stocks.upsert_company_note(%{
                 isin: "FI0009000202",
                 symbol: "KESKOB",
                 thesis: "Solid Finnish retailer"
               })

      assert note.isin == "FI0009000202"
      assert note.thesis == "Solid Finnish retailer"
    end

    test "should update existing note" do
      {:ok, _} = Stocks.upsert_company_note(%{isin: "FI0009000202", thesis: "Original"})
      {:ok, updated} = Stocks.upsert_company_note(%{isin: "FI0009000202", thesis: "Updated"})

      assert updated.thesis == "Updated"
      assert length(Repo.all(CompanyNote)) == 1
    end

    test "should handle watchlist toggle" do
      {:ok, note} = Stocks.upsert_company_note(%{isin: "FI0009000202", watchlist: false})
      refute note.watchlist

      {:ok, toggled} = Stocks.upsert_company_note(%{isin: "FI0009000202", watchlist: true})
      assert toggled.watchlist
    end
  end

  describe "list_watchlist/0" do
    test "should return empty list when no watchlist items" do
      assert Stocks.list_watchlist() == []
    end

    test "should return only watchlisted notes" do
      {:ok, _} =
        Stocks.upsert_company_note(%{isin: "FI0009000202", symbol: "KESKOB", watchlist: true})

      {:ok, _} =
        Stocks.upsert_company_note(%{isin: "SE0000667925", symbol: "TELIA1", watchlist: false})

      watchlist = Stocks.list_watchlist()
      assert length(watchlist) == 1
      assert hd(watchlist).symbol == "KESKOB"
    end
  end

  describe "batch_symbol_mappings/1" do
    test "should return resolved mappings keyed by ISIN" do
      Repo.insert!(%SymbolMapping{
        isin: "FI0009000202",
        finnhub_symbol: "KESKOB.HE",
        status: "resolved"
      })

      Repo.insert!(%SymbolMapping{
        isin: "SE0000667925",
        finnhub_symbol: "TELIA1.ST",
        status: "resolved"
      })

      result = Stocks.batch_symbol_mappings(["FI0009000202", "SE0000667925"])

      assert map_size(result) == 2
      assert result["FI0009000202"].finnhub_symbol == "KESKOB.HE"
      assert result["SE0000667925"].finnhub_symbol == "TELIA1.ST"
    end

    test "should exclude non-resolved mappings" do
      Repo.insert!(%SymbolMapping{isin: "FI0009000202", status: "resolved", finnhub_symbol: "X"})
      Repo.insert!(%SymbolMapping{isin: "SE0000667925", status: "pending"})
      Repo.insert!(%SymbolMapping{isin: "US0000000000", status: "unmappable"})

      result = Stocks.batch_symbol_mappings(["FI0009000202", "SE0000667925", "US0000000000"])

      assert map_size(result) == 1
      assert Map.has_key?(result, "FI0009000202")
    end

    test "should return empty map for empty input" do
      assert Stocks.batch_symbol_mappings([]) == %{}
    end
  end

  describe "batch_historical_prices/3" do
    test "should return prices keyed by symbol then date" do
      Repo.insert!(%HistoricalPrice{
        symbol: "KESKOB.HE",
        date: ~D[2026-01-15],
        close: Decimal.new("21.00")
      })

      Repo.insert!(%HistoricalPrice{
        symbol: "KESKOB.HE",
        date: ~D[2026-01-16],
        close: Decimal.new("21.50")
      })

      Repo.insert!(%HistoricalPrice{
        symbol: "TELIA1.ST",
        date: ~D[2026-01-15],
        close: Decimal.new("3.85")
      })

      result =
        Stocks.batch_historical_prices(
          ["KESKOB.HE", "TELIA1.ST"],
          ~D[2026-01-15],
          ~D[2026-01-16]
        )

      assert map_size(result) == 2
      assert Decimal.equal?(result["KESKOB.HE"][~D[2026-01-15]], Decimal.new("21.00"))
      assert Decimal.equal?(result["KESKOB.HE"][~D[2026-01-16]], Decimal.new("21.50"))
      assert Decimal.equal?(result["TELIA1.ST"][~D[2026-01-15]], Decimal.new("3.85"))
    end

    test "should respect date range" do
      Repo.insert!(%HistoricalPrice{
        symbol: "X",
        date: ~D[2026-01-10],
        close: Decimal.new("10")
      })

      Repo.insert!(%HistoricalPrice{
        symbol: "X",
        date: ~D[2026-01-20],
        close: Decimal.new("20")
      })

      result = Stocks.batch_historical_prices(["X"], ~D[2026-01-15], ~D[2026-01-25])

      assert map_size(result["X"]) == 1
      assert Map.has_key?(result["X"], ~D[2026-01-20])
    end

    test "should return empty map for empty symbols" do
      assert Stocks.batch_historical_prices([], ~D[2026-01-01], ~D[2026-01-31]) == %{}
    end
  end

  describe "batch_get_close_price/3" do
    test "should return exact date price" do
      price_map = %{
        "KESKOB.HE" => %{~D[2026-01-15] => Decimal.new("21.00")}
      }

      assert {:ok, price} = Stocks.batch_get_close_price(price_map, "KESKOB.HE", ~D[2026-01-15])
      assert Decimal.equal?(price, Decimal.new("21.00"))
    end

    test "should fall back to previous days within 5-day window" do
      price_map = %{
        "X" => %{~D[2026-01-10] => Decimal.new("100")}
      }

      # 3 days after last price — within 5-day window
      assert {:ok, price} = Stocks.batch_get_close_price(price_map, "X", ~D[2026-01-13])
      assert Decimal.equal?(price, Decimal.new("100"))
    end

    test "should return error when no price within 5-day window" do
      price_map = %{
        "X" => %{~D[2026-01-01] => Decimal.new("100")}
      }

      # 10 days after — outside window
      assert {:error, :no_price} =
               Stocks.batch_get_close_price(price_map, "X", ~D[2026-01-11])
    end

    test "should return error for unknown symbol" do
      assert {:error, :no_price} =
               Stocks.batch_get_close_price(%{}, "UNKNOWN", ~D[2026-01-15])
    end
  end
end
