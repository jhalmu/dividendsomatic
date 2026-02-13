defmodule Dividendsomatic.MarketData.DispatcherTest do
  use ExUnit.Case, async: true

  alias Dividendsomatic.MarketData.Dispatcher

  defmodule SuccessProvider do
    @behaviour Dividendsomatic.MarketData.Provider

    @impl true
    def get_quote(_symbol), do: {:ok, %{source: :success, price: 150}}
    @impl true
    def get_candles(_s, _f, _t, _o), do: {:ok, [%{close: 150}]}
    @impl true
    def get_company_profile(_s), do: {:ok, %{name: "Success Corp"}}
  end

  defmodule FailProvider do
    @behaviour Dividendsomatic.MarketData.Provider

    @impl true
    def get_quote(_symbol), do: {:error, :api_error}
    @impl true
    def get_candles(_s, _f, _t, _o), do: {:error, :api_error}
    @impl true
    def get_company_profile(_s), do: {:error, :api_error}
  end

  defmodule PartialProvider do
    @behaviour Dividendsomatic.MarketData.Provider

    @impl true
    def get_quote(_symbol), do: {:error, :not_supported}
    @impl true
    def get_candles(_s, _f, _t, _o), do: {:ok, [%{close: 200}]}
    @impl true
    def get_company_profile(_s), do: {:error, :not_supported}
  end

  describe "dispatch/3" do
    test "should return first successful provider result" do
      providers = [SuccessProvider]
      assert {:ok, %{source: :success}} = Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should skip failing providers and use next" do
      providers = [FailProvider, SuccessProvider]
      assert {:ok, %{source: :success}} = Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should skip not_supported and use next" do
      providers = [PartialProvider, SuccessProvider]
      assert {:ok, %{source: :success}} = Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should return all_providers_failed when all fail" do
      providers = [FailProvider]

      assert {:error, :all_providers_failed} =
               Dispatcher.dispatch(:get_quote, ["AAPL"], providers)
    end

    test "should return all_providers_failed for empty provider list" do
      assert {:error, :all_providers_failed} = Dispatcher.dispatch(:get_quote, ["AAPL"], [])
    end

    test "should pass multiple args correctly" do
      providers = [SuccessProvider]

      assert {:ok, [%{close: 150}]} =
               Dispatcher.dispatch(
                 :get_candles,
                 ["AAPL", ~D[2025-01-01], ~D[2025-12-31], []],
                 providers
               )
    end
  end

  describe "dispatch_for/3" do
    setup do
      original = Application.get_env(:dividendsomatic, :market_data)

      Application.put_env(:dividendsomatic, :market_data,
        providers: %{
          quote: [FailProvider, SuccessProvider],
          candles: [PartialProvider]
        }
      )

      on_exit(fn ->
        if original,
          do: Application.put_env(:dividendsomatic, :market_data, original),
          else: Application.delete_env(:dividendsomatic, :market_data)
      end)

      :ok
    end

    test "should use config-based provider chain" do
      assert {:ok, %{source: :success}} = Dispatcher.dispatch_for(:get_quote, ["AAPL"], :quote)
    end

    test "should return all_providers_failed for unconfigured data type" do
      assert {:error, :all_providers_failed} =
               Dispatcher.dispatch_for(:get_quote, ["AAPL"], :unknown)
    end
  end
end
