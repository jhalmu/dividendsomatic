defmodule Dividendsomatic.MarketData.Provider do
  @moduledoc """
  Behaviour for market data providers.

  Required callbacks: get_quote, get_candles, get_company_profile.
  Optional callbacks: get_forex_candles, get_financial_metrics, lookup_symbol_by_isin.

  Providers that don't support an optional callback should not implement it.
  The dispatcher will skip providers that raise `UndefinedFunctionError`.
  """

  @type quote_result :: {:ok, map()} | {:error, term()}
  @type candles_result :: {:ok, [map()]} | {:error, term()}
  @type profile_result :: {:ok, map()} | {:error, term()}
  @type metrics_result :: {:ok, map()} | {:error, term()}

  @callback get_quote(symbol :: String.t()) :: quote_result()
  @callback get_candles(symbol :: String.t(), from :: Date.t(), to :: Date.t(), opts :: keyword()) ::
              candles_result()
  @callback get_forex_candles(pair :: String.t(), from :: Date.t(), to :: Date.t()) ::
              candles_result()
  @callback get_company_profile(symbol :: String.t()) :: profile_result()
  @callback get_financial_metrics(symbol :: String.t()) :: metrics_result()
  @callback lookup_symbol_by_isin(isin :: String.t()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks get_forex_candles: 3, get_financial_metrics: 1, lookup_symbol_by_isin: 1
end
