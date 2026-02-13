defmodule Dividendsomatic.Portfolio.Processors.SoldPositionProcessor do
  @moduledoc """
  Derives sold position records from broker sell transactions.

  Nordnet: back-calculates purchase price from P&L data, finds earliest buy by ISIN.
  IBKR: finds earliest buy by security name (matching company name), uses buy price.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Holding, IsinMap, SoldPosition}
  alias Dividendsomatic.Repo
  alias Dividendsomatic.Stocks

  @doc """
  Processes all sell transactions and inserts into sold_positions table.
  Returns `{:ok, count}` with the number of new sold positions created.
  """
  def process do
    sell_txns =
      BrokerTransaction
      |> where([t], t.transaction_type == "sell")
      |> order_by([t], asc: t.trade_date)
      |> Repo.all()

    results = Enum.map(sell_txns, &insert_sold_position/1)

    created = Enum.count(results, &(&1 == :created))
    skipped = Enum.count(results, &(&1 == :skipped))
    Logger.info("SoldPositionProcessor: #{created} created, #{skipped} skipped")
    {:ok, created}
  end

  defp insert_sold_position(txn) do
    if sold_position_exists?(txn), do: :skipped, else: do_insert_sold_position(txn)
  end

  defp do_insert_sold_position(txn) do
    quantity = Decimal.abs(txn.quantity || Decimal.new("0"))
    sale_price = txn.price || Decimal.new("0")

    if zero?(quantity) || zero?(sale_price) do
      :skipped
    else
      build_and_insert(txn, quantity, sale_price)
    end
  end

  # Nordnet: has P&L (result) and ISIN on sell transactions
  defp build_and_insert(%{broker: "nordnet"} = txn, quantity, sale_price) do
    purchase_price = back_calculate_purchase_price(sale_price, txn.result, quantity)
    purchase_date = find_nordnet_purchase_date(txn.isin)

    insert_position(txn, quantity, sale_price, purchase_price, purchase_date)
  end

  # IBKR: no P&L, no ISIN on sells — find earliest buy by company name
  defp build_and_insert(%{broker: "ibkr"} = txn, quantity, sale_price) do
    {purchase_date, purchase_price} = find_ibkr_purchase(txn.security_name)
    purchase_price = purchase_price || sale_price

    insert_position(txn, quantity, sale_price, purchase_price, purchase_date)
  end

  defp build_and_insert(txn, quantity, sale_price) do
    insert_position(txn, quantity, sale_price, sale_price, nil)
  end

  defp insert_position(txn, quantity, sale_price, purchase_price, purchase_date) do
    symbol = ibkr_symbol(txn) || txn.security_name
    currency = txn.currency || "EUR"
    isin = txn.isin || resolve_isin(symbol)

    eur_fields = compute_eur_fields(currency, txn.result, txn.trade_date)

    attrs =
      %{
        symbol: symbol,
        quantity: quantity,
        purchase_price: purchase_price,
        purchase_date: purchase_date || txn.trade_date,
        sale_price: sale_price,
        sale_date: txn.trade_date,
        currency: currency,
        realized_pnl: txn.result,
        isin: isin,
        source: txn.broker,
        notes: "Imported from #{txn.broker}"
      }
      |> Map.merge(eur_fields)

    case %SoldPosition{} |> SoldPosition.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> :created
      {:error, _} -> :skipped
    end
  end

  # Resolve ISIN from holdings, dividend transactions, or static map
  defp resolve_isin(symbol) when is_binary(symbol) do
    resolve_isin_from_holdings(symbol) ||
      resolve_isin_from_dividends(symbol) ||
      Map.get(isin_static_map(), symbol)
  end

  defp resolve_isin(_), do: nil

  defp resolve_isin_from_holdings(symbol) do
    Holding
    |> where([h], h.symbol == ^symbol and not is_nil(h.isin) and h.isin > "")
    |> limit(1)
    |> select([h], h.isin)
    |> Repo.one()
  end

  defp resolve_isin_from_dividends(symbol) do
    BrokerTransaction
    |> where(
      [t],
      t.transaction_type in ["dividend", "withholding_tax"] and
        not is_nil(t.isin) and
        fragment("?->>? = ?", t.raw_data, "symbol", ^symbol)
    )
    |> limit(1)
    |> select([t], t.isin)
    |> Repo.one()
  end

  defp isin_static_map, do: IsinMap.static_map()

  defp compute_eur_fields("EUR", _pnl, _sale_date) do
    %{realized_pnl_eur: nil, exchange_rate_to_eur: Decimal.new("1")}
  end

  defp compute_eur_fields(currency, pnl, sale_date) when not is_nil(pnl) do
    pair = "OANDA:EUR_#{currency}"

    case Stocks.get_fx_rate(pair, sale_date) do
      {:ok, rate} ->
        if Decimal.compare(rate, Decimal.new("0")) == :gt do
          %{realized_pnl_eur: Decimal.div(pnl, rate), exchange_rate_to_eur: rate}
        else
          %{}
        end

      _ ->
        %{}
    end
  end

  defp compute_eur_fields(_currency, _pnl, _sale_date), do: %{}

  defp zero?(decimal), do: Decimal.compare(decimal, Decimal.new("0")) == :eq

  # Nordnet: purchase_price = sale_price - (result / quantity)
  defp back_calculate_purchase_price(sale_price, nil, _quantity), do: sale_price

  defp back_calculate_purchase_price(sale_price, result, quantity) do
    if Decimal.compare(quantity, Decimal.new("0")) != :eq do
      per_share_pnl = Decimal.div(result, quantity)
      price = Decimal.sub(sale_price, per_share_pnl)
      if Decimal.compare(price, Decimal.new("0")) == :gt, do: price, else: sale_price
    else
      sale_price
    end
  end

  # Find earliest Nordnet buy by ISIN (FIFO)
  defp find_nordnet_purchase_date(nil), do: nil

  defp find_nordnet_purchase_date(isin) do
    BrokerTransaction
    |> where([t], t.transaction_type == "buy" and t.isin == ^isin and t.broker == "nordnet")
    |> order_by([t], asc: t.trade_date)
    |> limit(1)
    |> select([t], t.trade_date)
    |> Repo.one()
  end

  # Find earliest IBKR buy by company name, falling back to ticker symbol.
  # CSV-parsed buys have company names as security_name; PDF-parsed buys have tickers.
  # Tries company name first, then ticker from raw_data["symbol"].
  defp find_ibkr_purchase(nil), do: {nil, nil}

  defp find_ibkr_purchase(security_name) do
    # Try matching by security_name (company name for CSV, ticker for PDF)
    result = find_ibkr_buy_by_field(:security_name, security_name)

    # Fallback: try matching by ticker stored in raw_data->symbol
    result = result || find_ibkr_buy_by_symbol(security_name)

    result || {nil, nil}
  end

  defp find_ibkr_buy_by_field(field, value) do
    BrokerTransaction
    |> where(
      [t],
      t.broker == "ibkr" and t.transaction_type == "buy" and field(t, ^field) == ^value
    )
    |> order_by([t], asc: t.trade_date)
    |> limit(1)
    |> select([t], {t.trade_date, t.price})
    |> Repo.one()
  end

  defp find_ibkr_buy_by_symbol(security_name) do
    BrokerTransaction
    |> where(
      [t],
      t.broker == "ibkr" and t.transaction_type == "buy" and
        fragment("?->>'symbol' = ?", t.raw_data, ^security_name)
    )
    |> order_by([t], asc: t.trade_date)
    |> limit(1)
    |> select([t], {t.trade_date, t.price})
    |> Repo.one()
  end

  # For IBKR, prefer ticker symbol from raw_data over full company name
  defp ibkr_symbol(%{broker: "ibkr", raw_data: %{"symbol" => symbol}}) when is_binary(symbol),
    do: symbol

  defp ibkr_symbol(_), do: nil

  defp sold_position_exists?(txn) do
    symbol = ibkr_symbol(txn) || txn.security_name
    quantity = Decimal.abs(txn.quantity || Decimal.new("0"))

    if txn.isin do
      SoldPosition
      |> where(
        [s],
        s.isin == ^txn.isin and s.sale_date == ^txn.trade_date and s.quantity == ^quantity
      )
      |> Repo.exists?()
    else
      SoldPosition
      |> where(
        [s],
        s.symbol == ^symbol and s.sale_date == ^txn.trade_date and s.quantity == ^quantity
      )
      |> Repo.exists?()
    end
  end
end
