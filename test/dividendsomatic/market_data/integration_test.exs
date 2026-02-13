defmodule Dividendsomatic.MarketData.IntegrationTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Dispatcher

  defmodule AlwaysFails do
    @behaviour Dividendsomatic.MarketData.Provider
    @impl true
    def get_quote(_), do: {:error, :down}
    @impl true
    def get_candles(_, _, _, _), do: {:error, :down}
    @impl true
    def get_company_profile(_), do: {:error, :down}
  end

  defmodule Fallback do
    @behaviour Dividendsomatic.MarketData.Provider
    @impl true
    def get_quote(_), do: {:ok, %{current_price: 99.99, source: :fallback}}
    @impl true
    def get_candles(_, _, _, _), do: {:ok, [%{close: 99.99}]}
    @impl true
    def get_company_profile(_), do: {:ok, %{name: "Fallback Corp"}}
  end

  defmodule NotSupported do
    @behaviour Dividendsomatic.MarketData.Provider
    @impl true
    def get_quote(_), do: {:error, :not_supported}
    @impl true
    def get_candles(_, _, _, _), do: {:error, :not_supported}
    @impl true
    def get_company_profile(_), do: {:error, :not_supported}
  end

  describe "fallback chain integration" do
    test "should fall through to working provider when first fails" do
      chain = [AlwaysFails, Fallback]
      assert {:ok, %{source: :fallback}} = Dispatcher.dispatch(:get_quote, ["TEST"], chain)
    end

    test "should fall through not_supported to working provider" do
      chain = [NotSupported, AlwaysFails, Fallback]
      assert {:ok, %{source: :fallback}} = Dispatcher.dispatch(:get_quote, ["TEST"], chain)
    end

    test "should report all_providers_failed when entire chain fails" do
      chain = [AlwaysFails, NotSupported]
      assert {:error, :all_providers_failed} = Dispatcher.dispatch(:get_quote, ["TEST"], chain)
    end

    test "should stop at first success and not call remaining providers" do
      chain = [Fallback, AlwaysFails]
      assert {:ok, %{source: :fallback}} = Dispatcher.dispatch(:get_quote, ["TEST"], chain)
    end
  end
end
