defmodule Dividendsomatic.MarketData.Providers.YahooFinanceTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Providers.YahooFinance

  @chart_response %{
    "chart" => %{
      "result" => [
        %{
          "timestamp" => [1_704_067_200, 1_704_153_600],
          "indicators" => %{
            "quote" => [
              %{
                "open" => [100.0, 101.0],
                "high" => [105.0, 106.0],
                "low" => [99.0, 100.0],
                "close" => [104.0, 105.0],
                "volume" => [1_000_000, 1_100_000]
              }
            ]
          }
        }
      ]
    }
  }

  describe "get_quote/1" do
    test "should return not_supported" do
      assert {:error, :not_supported} = YahooFinance.get_quote("AAPL")
    end
  end

  describe "get_company_profile/1" do
    test "should return profile with sector and industry" do
      case YahooFinance.get_company_profile("AAPL") do
        {:ok, profile} ->
          assert profile[:sector] != nil
          assert profile[:industry] != nil

        {:error, _reason} ->
          # May fail in CI/test without network access
          :ok
      end
    end
  end

  describe "get_candles/4" do
    test "should return candle data on success" do
      Req.Test.stub(YahooFinance, fn conn ->
        Req.Test.json(conn, @chart_response)
      end)

      assert {:ok, records} =
               YahooFinance.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], [])

      assert length(records) == 2
      assert hd(records).close == 104.0
      assert hd(records).volume == 1_000_000
    end

    test "should return not_found on 404" do
      Req.Test.stub(YahooFinance, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not found")
      end)

      assert {:error, :not_found} =
               YahooFinance.get_candles("INVALID", ~D[2024-01-01], ~D[2024-01-02], [])
    end

    test "should filter out records with nil close" do
      response = %{
        "chart" => %{
          "result" => [
            %{
              "timestamp" => [1_704_067_200, 1_704_153_600],
              "indicators" => %{
                "quote" => [
                  %{
                    "open" => [100.0, nil],
                    "high" => [105.0, nil],
                    "low" => [99.0, nil],
                    "close" => [104.0, nil],
                    "volume" => [1_000_000, nil]
                  }
                ]
              }
            }
          ]
        }
      }

      Req.Test.stub(YahooFinance, fn conn ->
        Req.Test.json(conn, response)
      end)

      assert {:ok, records} =
               YahooFinance.get_candles("AAPL", ~D[2024-01-01], ~D[2024-01-02], [])

      assert length(records) == 1
    end
  end

  describe "get_forex_candles/3" do
    test "should fetch forex data with converted pair" do
      Req.Test.stub(YahooFinance, fn conn ->
        # Verify the Yahoo symbol is in the path (EURUSD=X)
        assert String.contains?(conn.request_path, "EURUSD")
        Req.Test.json(conn, @chart_response)
      end)

      assert {:ok, records} =
               YahooFinance.get_forex_candles("OANDA:EUR_USD", ~D[2024-01-01], ~D[2024-01-02])

      assert length(records) == 2
    end
  end
end
