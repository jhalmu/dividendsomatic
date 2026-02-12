defmodule Dividendsomatic.Portfolio.PositionReconstructor do
  @moduledoc """
  Reconstructs historical portfolio positions from broker transaction data.

  Walks buy/sell transactions chronologically to build a daily position history,
  tracking running quantities per ISIN with FIFO cost basis. Samples at weekly
  intervals plus every transaction date for chart data generation.
  """

  import Ecto.Query

  alias Dividendsomatic.Portfolio.BrokerTransaction
  alias Dividendsomatic.Repo

  @doc """
  Reconstructs position history from broker transactions.

  Returns a list of `%{date, positions}` maps sorted chronologically, sampled
  at weekly intervals and on every transaction date. Each position includes:
  - `:isin` - Security identifier
  - `:quantity` - Shares held (Decimal)
  - `:currency` - Transaction currency
  - `:cost_basis` - Total cost basis in local currency (Decimal)
  - `:security_name` - Name of the security
  """
  def reconstruct do
    transactions = load_transactions()

    case transactions do
      [] ->
        []

      txns ->
        positions_over_time = walk_transactions(txns)
        sample_dates = build_sample_dates(txns)
        sample_positions(positions_over_time, sample_dates)
    end
  end

  @doc """
  Returns distinct ISINs with activity from broker transactions.
  Excludes leveraged/structured products.
  """
  def active_isins do
    BrokerTransaction
    |> where([t], not is_nil(t.isin) and t.transaction_type in ["buy", "sell"])
    |> group_by([t], [t.isin, t.security_name])
    |> select([t], %{isin: t.isin, security_name: max(t.security_name)})
    |> Repo.all()
    |> Enum.reject(&leveraged_product?/1)
  end

  # Load buy/sell transactions ordered chronologically
  defp load_transactions do
    BrokerTransaction
    |> where([t], t.transaction_type in ["buy", "sell"] and not is_nil(t.isin))
    |> order_by([t], asc: t.trade_date)
    |> Repo.all()
  end

  # Walk transactions chronologically, building running position state.
  # Returns [{date, positions_map}] where positions_map is %{isin => position}
  defp walk_transactions(transactions) do
    {snapshots, _final} =
      Enum.reduce(transactions, {[], %{}}, fn txn, {snapshots, positions} ->
        positions = update_position(positions, txn)
        snapshot = {txn.trade_date, deep_copy_positions(positions)}
        {[snapshot | snapshots], positions}
      end)

    Enum.reverse(snapshots)
  end

  defp update_position(positions, txn) do
    isin = txn.isin
    current = Map.get(positions, isin, empty_position(txn))

    updated =
      case txn.transaction_type do
        "buy" ->
          qty = Decimal.add(current.quantity, txn.quantity || Decimal.new("0"))
          cost = Decimal.add(current.cost_basis, transaction_cost(txn))
          %{current | quantity: qty, cost_basis: cost}

        "sell" ->
          sell_qty = Decimal.abs(txn.quantity || Decimal.new("0"))
          remaining = Decimal.sub(current.quantity, sell_qty)

          # FIFO: reduce cost basis proportionally
          cost_basis =
            if Decimal.compare(current.quantity, Decimal.new("0")) == :gt do
              ratio = Decimal.div(remaining, current.quantity)
              Decimal.mult(current.cost_basis, Decimal.max(ratio, Decimal.new("0")))
            else
              Decimal.new("0")
            end

          %{current | quantity: Decimal.max(remaining, Decimal.new("0")), cost_basis: cost_basis}
      end

    if Decimal.compare(updated.quantity, Decimal.new("0")) == :eq do
      Map.delete(positions, isin)
    else
      Map.put(positions, isin, updated)
    end
  end

  defp transaction_cost(txn) do
    price = txn.price || Decimal.new("0")
    qty = Decimal.abs(txn.quantity || Decimal.new("0"))
    Decimal.mult(price, qty)
  end

  defp empty_position(txn) do
    %{
      isin: txn.isin,
      quantity: Decimal.new("0"),
      currency: txn.currency || "EUR",
      cost_basis: Decimal.new("0"),
      security_name: txn.security_name
    }
  end

  defp deep_copy_positions(positions) do
    Map.new(positions, fn {k, v} -> {k, to_plain_map(v)} end)
  end

  defp to_plain_map(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp to_plain_map(map) when is_map(map), do: map

  # Build sample dates: every Monday + every transaction date
  defp build_sample_dates(transactions) do
    txn_dates = Enum.map(transactions, & &1.trade_date) |> Enum.uniq()
    first_date = List.first(txn_dates)
    last_date = List.last(txn_dates)

    weekly_dates = generate_weekly_dates(first_date, last_date)

    (txn_dates ++ weekly_dates)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  defp generate_weekly_dates(from, to) do
    # Start from the Monday of the first week
    days_to_monday = rem(Date.day_of_week(from) - 1, 7)
    first_monday = Date.add(from, -days_to_monday)

    Stream.iterate(first_monday, &Date.add(&1, 7))
    |> Enum.take_while(&(Date.compare(&1, to) != :gt))
  end

  # Sample positions at each sample date using the last known state
  defp sample_positions(snapshots, sample_dates) do
    Enum.map(sample_dates, fn date ->
      # Find the latest snapshot on or before this date
      positions =
        snapshots
        |> Enum.filter(fn {snap_date, _} -> Date.compare(snap_date, date) != :gt end)
        |> List.last()
        |> case do
          nil -> %{}
          {_date, pos} -> pos
        end

      position_list =
        positions
        |> Map.values()
        |> Enum.filter(fn p -> Decimal.compare(p.quantity, Decimal.new("0")) == :gt end)

      %{date: date, positions: position_list}
    end)
    |> Enum.filter(fn %{positions: p} -> p != [] end)
  end

  defp leveraged_product?(%{security_name: nil}), do: false

  defp leveraged_product?(%{security_name: name}) do
    upper = String.upcase(name)

    Enum.any?(
      ~w(BULL BEAR TRACKER MINI TURBO WARRANT CERTIFIKAT),
      &String.contains?(upper, &1)
    )
  end
end
