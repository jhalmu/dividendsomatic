defmodule Dividendsomatic.MarketData.Providers.EodhdTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Providers.Eodhd

  describe "get_quote/1" do
    test "should return quote data on success" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, %{
          "code" => "AAPL.US",
          "timestamp" => 1_711_670_340,
          "open" => 170.0,
          "high" => 172.0,
          "low" => 169.0,
          "close" => 171.5,
          "volume" => 50_000_000,
          "previousClose" => 170.0,
          "change" => 1.5,
          "change_p" => 0.88
        })
      end)

      assert {:ok, quote_data} = Eodhd.get_quote("AAPL.US", api_key: "test_key")
      assert quote_data.current_price == 171.5
      assert quote_data.change == 1.5
      assert quote_data.percent_change == 0.88
      assert quote_data.previous_close == 170.0
    end

    test "should return not_configured without API key" do
      assert {:error, :not_configured} = Eodhd.get_quote("AAPL.US")
    end

    test "should return rate_limited on 429" do
      Req.Test.stub(Eodhd, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Rate limited")
      end)

      assert {:error, :rate_limited} = Eodhd.get_quote("AAPL.US", api_key: "test_key")
    end
  end

  describe "get_candles/4" do
    test "should return candle records on success" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, [
          %{
            "date" => "2024-01-01",
            "open" => 100.0,
            "high" => 105.0,
            "low" => 99.0,
            "close" => 104.0,
            "adjusted_close" => 104.0,
            "volume" => 1_000_000
          },
          %{
            "date" => "2024-01-02",
            "open" => 104.0,
            "high" => 106.0,
            "low" => 103.0,
            "close" => 105.5,
            "adjusted_close" => 105.5,
            "volume" => 1_100_000
          }
        ])
      end)

      assert {:ok, records} =
               Eodhd.get_candles("AAPL.US", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")

      assert length(records) == 2
      assert hd(records).date == ~D[2024-01-01]
      assert hd(records).close == 104.0
    end

    test "should return empty list for empty response" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} =
               Eodhd.get_candles("AAPL.US", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")
    end
  end

  describe "get_forex_candles/3" do
    test "should convert OANDA pair to EODHD format and fetch" do
      Req.Test.stub(Eodhd, fn conn ->
        assert String.contains?(conn.request_path, "EURUSD.FOREX")

        Req.Test.json(conn, [
          %{
            "date" => "2024-01-01",
            "open" => 1.1,
            "high" => 1.12,
            "low" => 1.09,
            "close" => 1.11,
            "adjusted_close" => 1.11,
            "volume" => 0
          }
        ])
      end)

      assert {:ok, [record]} =
               Eodhd.get_forex_candles("OANDA:EUR_USD", ~D[2024-01-01], ~D[2024-01-01],
                 api_key: "test_key"
               )

      assert record.close == 1.11
    end
  end

  describe "get_company_profile/1" do
    test "should return profile data from fundamentals endpoint" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, %{
          "General" => %{
            "Code" => "AAPL",
            "Name" => "Apple Inc.",
            "CountryName" => "USA",
            "CurrencyCode" => "USD",
            "Exchange" => "NASDAQ",
            "Sector" => "Technology",
            "Industry" => "Consumer Electronics",
            "WebURL" => "https://apple.com",
            "LogoURL" => "https://eodhd.com/img/logos/US/AAPL.png",
            "ISIN" => "US0378331005",
            "IPODate" => "1980-12-12"
          },
          "Highlights" => %{
            "MarketCapitalization" => 3_000_000_000_000
          }
        })
      end)

      assert {:ok, profile} = Eodhd.get_company_profile("AAPL.US", api_key: "test_key")
      assert profile.name == "Apple Inc."
      assert profile.country == "USA"
      assert profile.sector == "Technology"
      assert profile.industry == "Consumer Electronics"
      assert profile.isin == "US0378331005"
    end

    test "should return no_data for empty response" do
      Req.Test.stub(Eodhd, fn conn ->
        Req.Test.json(conn, %{})
      end)

      assert {:error, :no_data} = Eodhd.get_company_profile("INVALID", api_key: "test_key")
    end
  end

  describe "symbol_to_eodhd/1" do
    test "should preserve symbols with exchange suffix" do
      assert Eodhd.symbol_to_eodhd("NOKIA.HE") == "NOKIA.HE"
      assert Eodhd.symbol_to_eodhd("TELIA1.ST") == "TELIA1.ST"
      assert Eodhd.symbol_to_eodhd("EQNR.OL") == "EQNR.OL"
    end

    test "should append .US for symbols without suffix" do
      assert Eodhd.symbol_to_eodhd("AAPL") == "AAPL.US"
      assert Eodhd.symbol_to_eodhd("MAIN") == "MAIN.US"
    end
  end

  describe "oanda_to_eodhd/1" do
    test "should convert OANDA pair to EODHD forex format" do
      assert Eodhd.oanda_to_eodhd("OANDA:EUR_USD") == "EURUSD.FOREX"
      assert Eodhd.oanda_to_eodhd("OANDA:GBP_SEK") == "GBPSEK.FOREX"
    end

    test "should pass through non-OANDA strings" do
      assert Eodhd.oanda_to_eodhd("EURUSD.FOREX") == "EURUSD.FOREX"
    end
  end
end
