defmodule Dividendsomatic.Stocks.SymbolMapper do
  @moduledoc """
  Resolves ISIN identifiers to Finnhub-compatible ticker symbols.

  Uses a cascading lookup strategy:
  1. Check `symbol_mappings` table (cached result)
  2. Check `holdings` table (IBKR has isin + symbol + listing_exchange)
  3. Country-prefix heuristics (FI* → .HE, SE* → .ST, etc.)
  4. Auto-detect unmappable: BULL/BEAR/TRACKER in security_name
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.Holding
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks.SymbolMapping

  # IB exchange → Finnhub symbol suffix mapping
  @exchange_suffix %{
    "HEX" => ".HE",
    "SFB" => ".ST",
    "OSE" => ".OL",
    "TSE" => ".TO",
    "TSEJ" => ".T",
    "SBF" => ".PA",
    "FWB" => ".F",
    "FWB2" => ".F",
    "IBIS" => ".DE",
    "LSE" => ".L",
    "SEHK" => ".HK",
    "NYSE" => "",
    "NASDAQ" => "",
    "ARCA" => "",
    "AMEX" => ""
  }

  # Patterns indicating leveraged/structured products that can't be priced
  @unmappable_patterns ~w(BULL BEAR TRACKER MINI TURBO WARRANT CERTIFIKAT)

  @doc """
  Resolves an ISIN to a Finnhub symbol.

  Returns `{:ok, symbol}` if resolved, `{:unmappable, reason}` if the security
  can't be mapped, or `{:pending, isin}` if resolution failed.
  """
  def resolve(isin, security_name \\ nil) do
    case check_cache(isin) do
      {:ok, _} = cached -> cached
      {:unmappable, _} = cached -> cached
      {:miss, _} -> resolve_uncached(isin, security_name)
    end
  end

  defp resolve_uncached(isin, security_name) do
    result =
      case check_holdings(isin) do
        {:ok, _} = found -> found
        {:miss, _} -> resolve_by_heuristics(isin, security_name)
      end

    cache_result(isin, security_name, result)
    result
  end

  @doc """
  Resolves all unresolved ISINs from broker_transactions.

  Returns `{resolved, unmappable, pending}` counts.
  """
  def resolve_all do
    distinct_isins()
    |> Enum.reduce({0, 0, 0}, fn {isin, security_name}, {res, unmap, pend} ->
      case resolve(isin, security_name) do
        {:ok, _} -> {res + 1, unmap, pend}
        {:unmappable, _} -> {res, unmap + 1, pend}
        {:pending, _} -> {res, unmap, pend + 1}
      end
    end)
  end

  @doc """
  Returns all resolved symbol mappings.
  """
  def list_resolved do
    SymbolMapping
    |> where([m], m.status == "resolved")
    |> Repo.all()
  end

  @doc """
  Returns all symbol mappings.
  """
  def list_all do
    SymbolMapping
    |> order_by([m], asc: m.isin)
    |> Repo.all()
  end

  @doc """
  Returns the exchange suffix map for reference.
  """
  def exchange_suffix_map, do: @exchange_suffix

  # Step 1: Check cached result in symbol_mappings table
  defp check_cache(isin) do
    case Repo.get_by(SymbolMapping, isin: isin) do
      %SymbolMapping{status: "resolved", finnhub_symbol: symbol} ->
        {:ok, symbol}

      %SymbolMapping{status: "unmappable", notes: notes} ->
        {:unmappable, notes || "cached unmappable"}

      _ ->
        {:miss, isin}
    end
  end

  # Step 2: Check holdings table for IBKR data (has isin + symbol + listing_exchange)
  defp check_holdings(isin) do
    holding =
      Holding
      |> where([h], h.isin == ^isin and not is_nil(h.listing_exchange))
      |> order_by([h], desc: h.report_date)
      |> limit(1)
      |> Repo.one()

    case holding do
      %Holding{symbol: symbol, listing_exchange: exchange} when is_binary(symbol) ->
        finnhub_symbol = apply_exchange_suffix(symbol, exchange)
        {:ok, finnhub_symbol}

      _ ->
        {:miss, isin}
    end
  end

  # Step 3: Heuristic resolution — detect unmappable products, otherwise pending
  defp resolve_by_heuristics(isin, security_name) do
    if unmappable_product?(security_name) do
      {:unmappable, "leveraged/structured product: #{security_name}"}
    else
      {:pending, isin}
    end
  end

  defp unmappable_product?(nil), do: false

  defp unmappable_product?(name) do
    upper = String.upcase(name)
    Enum.any?(@unmappable_patterns, &String.contains?(upper, &1))
  end

  defp apply_exchange_suffix(symbol, exchange) do
    suffix = Map.get(@exchange_suffix, exchange, "")
    symbol <> suffix
  end

  # Cache the resolution result
  defp cache_result(isin, security_name, result) do
    attrs =
      case result do
        {:ok, symbol} ->
          %{
            isin: isin,
            finnhub_symbol: symbol,
            security_name: security_name,
            status: "resolved"
          }

        {:unmappable, reason} ->
          %{
            isin: isin,
            security_name: security_name,
            status: "unmappable",
            notes: reason
          }

        {:pending, _} ->
          %{
            isin: isin,
            security_name: security_name,
            status: "pending"
          }
      end

    case Repo.get_by(SymbolMapping, isin: isin) do
      nil ->
        %SymbolMapping{}
        |> SymbolMapping.changeset(attrs)
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:isin])

      existing ->
        existing
        |> SymbolMapping.changeset(attrs)
        |> Repo.update()
    end
  end

  # Get distinct ISINs with security names from broker_transactions
  defp distinct_isins do
    alias Dividendsomatic.Portfolio.BrokerTransaction

    BrokerTransaction
    |> where([t], not is_nil(t.isin) and t.transaction_type in ["buy", "sell"])
    |> group_by([t], [t.isin, t.security_name])
    |> select([t], {t.isin, max(t.security_name)})
    |> Repo.all()
  end
end
