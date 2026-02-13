defmodule Dividendsomatic.MarketData.Providers.FinnhubTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Providers.Finnhub

  describe "get_quote/1" do
    test "should return quote data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "c" => 150.0,
          "d" => 2.5,
          "dp" => 1.69,
          "h" => 152.0,
          "l" => 148.0,
          "o" => 149.0,
          "pc" => 147.5
        })
      end)

      assert {:ok, quote_data} = Finnhub.get_quote("AAPL", api_key: "test_key")
      assert quote_data.current_price == 150.0
      assert quote_data.change == 2.5
      assert quote_data.percent_change == 1.69
    end

    test "should return error when no data (price is 0)" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "c" => 0,
          "d" => nil,
          "dp" => nil,
          "h" => 0,
          "l" => 0,
          "o" => 0,
          "pc" => 0
        })
      end)

      assert {:error, :no_data} = Finnhub.get_quote("INVALID", api_key: "test_key")
    end

    test "should return rate_limited on 429" do
      Req.Test.stub(Finnhub, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Rate limited")
      end)

      assert {:error, :rate_limited} = Finnhub.get_quote("AAPL", api_key: "test_key")
    end

    test "should return not_configured without API key" do
      assert {:error, :not_configured} = Finnhub.get_quote("AAPL")
    end
  end

  describe "get_candles/4" do
    test "should return candle records on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "s" => "ok",
          "t" => [1_704_067_200, 1_704_153_600],
          "o" => [100.0, 101.0],
          "h" => [105.0, 106.0],
          "l" => [99.0, 100.0],
          "c" => [104.0, 105.0],
          "v" => [1_000_000, 1_100_000]
        })
      end)

      assert {:ok, records} =
               Finnhub.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")

      assert length(records) == 2
      assert hd(records).close == 104.0
      assert hd(records).volume == 1_000_000
    end

    test "should return empty list for no_data" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{"s" => "no_data"})
      end)

      assert {:ok, []} =
               Finnhub.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")
    end

    test "should return access_denied on 403" do
      Req.Test.stub(Finnhub, fn conn ->
        Plug.Conn.send_resp(conn, 403, "Forbidden")
      end)

      assert {:error, :access_denied} =
               Finnhub.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], api_key: "test_key")
    end
  end

  describe "get_forex_candles/3" do
    test "should return forex candle data" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "s" => "ok",
          "t" => [1_704_067_200],
          "o" => [1.1],
          "h" => [1.12],
          "l" => [1.09],
          "c" => [1.11],
          "v" => [0]
        })
      end)

      assert {:ok, [record]} =
               Finnhub.get_forex_candles("OANDA:EUR_USD", ~D[2024-01-01], ~D[2024-01-02],
                 api_key: "test_key"
               )

      assert record.close == 1.11
    end
  end

  describe "get_company_profile/1" do
    test "should return profile data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "name" => "Apple Inc.",
          "country" => "US",
          "currency" => "USD",
          "exchange" => "NASDAQ",
          "finnhubIndustry" => "Technology",
          "ipo" => "1980-12-12",
          "logo" => "https://example.com/logo.png",
          "weburl" => "https://apple.com",
          "marketCapitalization" => 3_000_000
        })
      end)

      assert {:ok, profile} = Finnhub.get_company_profile("AAPL", api_key: "test_key")
      assert profile.name == "Apple Inc."
      assert profile.country == "US"
      assert profile.exchange == "NASDAQ"
    end

    test "should return no_data for empty response" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{})
      end)

      assert {:error, :no_data} = Finnhub.get_company_profile("INVALID", api_key: "test_key")
    end
  end

  describe "get_financial_metrics/1" do
    test "should return metrics data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "metric" => %{
            "peBasicExclExtraTTM" => 28.5,
            "pbQuarterly" => 45.2,
            "epsBasicExclExtraItemsTTM" => 6.42,
            "roeRfy" => 147.25,
            "beta" => 1.24
          }
        })
      end)

      assert {:ok, metrics} = Finnhub.get_financial_metrics("AAPL", api_key: "test_key")
      assert metrics.pe_ratio == 28.5
      assert metrics.beta == 1.24
    end

    test "should return no_data for missing metrics" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{"metric" => nil})
      end)

      assert {:error, :no_data} = Finnhub.get_financial_metrics("INVALID", api_key: "test_key")
    end
  end

  describe "lookup_symbol_by_isin/1" do
    test "should return symbol data on success" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{
          "ticker" => "AAPL",
          "exchange" => "NASDAQ",
          "currency" => "USD",
          "name" => "Apple Inc."
        })
      end)

      assert {:ok, result} =
               Finnhub.lookup_symbol_by_isin("US0378331005", api_key: "test_key")

      assert result.symbol == "AAPL"
      assert result.exchange == "NASDAQ"
    end

    test "should return not_found for unknown ISIN" do
      Req.Test.stub(Finnhub, fn conn ->
        Req.Test.json(conn, %{})
      end)

      assert {:error, :not_found} =
               Finnhub.lookup_symbol_by_isin("XX0000000000", api_key: "test_key")
    end
  end
end
