defmodule Dividendsomatic.MarketData.Dispatcher do
  @moduledoc """
  Dispatches market data requests through a provider fallback chain.

  Tries each provider in order. Stops on first `{:ok, _}` result.
  Skips providers returning `{:error, :not_supported}` or any other error.
  """

  require Logger

  @doc """
  Dispatches a callback to an explicit list of providers.
  """
  def dispatch(callback, args, providers) when is_list(providers) do
    try_providers(providers, callback, args)
  end

  @doc """
  Dispatches using the configured provider chain for the given data type.

  Reads provider list from `config :dividendsomatic, :market_data, providers: %{data_type => [modules]}`.
  """
  def dispatch_for(callback, args, data_type) do
    providers = providers_for(data_type)
    try_providers(providers, callback, args)
  end

  defp try_providers([], _callback, _args), do: {:error, :all_providers_failed}

  defp try_providers([provider | rest], callback, args) do
    case apply(provider, callback, args) do
      {:ok, _} = success ->
        success

      {:error, :not_supported} ->
        try_providers(rest, callback, args)

      {:error, reason} ->
        Logger.debug("Provider #{inspect(provider)} failed for #{callback}: #{inspect(reason)}")
        try_providers(rest, callback, args)
    end
  end

  defp providers_for(data_type) do
    :dividendsomatic
    |> Application.get_env(:market_data, [])
    |> Keyword.get(:providers, %{})
    |> Map.get(data_type, [])
  end
end
