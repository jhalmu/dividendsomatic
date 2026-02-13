defmodule Dividendsomatic.MarketData.ProviderTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Provider

  defmodule FullProvider do
    @behaviour Provider

    @impl true
    def get_quote(_symbol), do: {:ok, %{price: 100}}

    @impl true
    def get_candles(_symbol, _from, _to, _opts), do: {:ok, []}

    @impl true
    def get_company_profile(_symbol), do: {:ok, %{name: "Test"}}

    @impl true
    def get_forex_candles(_pair, _from, _to), do: {:ok, []}

    @impl true
    def get_financial_metrics(_symbol), do: {:ok, %{}}

    @impl true
    def lookup_symbol_by_isin(_isin), do: {:ok, %{symbol: "TEST"}}
  end

  defmodule PartialProvider do
    @behaviour Provider

    @impl true
    def get_quote(_symbol), do: {:ok, %{price: 50}}

    @impl true
    def get_candles(_symbol, _from, _to, _opts), do: {:ok, []}

    @impl true
    def get_company_profile(_symbol), do: {:ok, %{}}
  end

  describe "behaviour contract" do
    test "should compile full provider implementing all callbacks" do
      assert {:ok, %{price: 100}} = FullProvider.get_quote("AAPL")
      assert {:ok, []} = FullProvider.get_candles("AAPL", ~D[2025-01-01], ~D[2025-12-31], [])
      assert {:ok, %{name: "Test"}} = FullProvider.get_company_profile("AAPL")

      assert {:ok, []} =
               FullProvider.get_forex_candles("OANDA:EUR_USD", ~D[2025-01-01], ~D[2025-12-31])

      assert {:ok, %{}} = FullProvider.get_financial_metrics("AAPL")
      assert {:ok, %{symbol: "TEST"}} = FullProvider.lookup_symbol_by_isin("US0378331005")
    end

    test "should compile partial provider with only required callbacks" do
      assert {:ok, %{price: 50}} = PartialProvider.get_quote("AAPL")
      assert {:ok, []} = PartialProvider.get_candles("AAPL", ~D[2025-01-01], ~D[2025-12-31], [])
      assert {:ok, %{}} = PartialProvider.get_company_profile("AAPL")
    end
  end
end
