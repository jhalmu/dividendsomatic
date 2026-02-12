defmodule Dividendsomatic.Portfolio.Processors.CostProcessor do
  @moduledoc """
  Extracts cost records from broker transactions.

  Handles commissions (from buy/sell), withholding tax, foreign tax,
  loan interest, and capital interest. All amounts stored as positive.
  Supports both Nordnet and IBKR brokers.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.Portfolio.{BrokerTransaction, Cost}
  alias Dividendsomatic.Repo

  # Transaction types that produce costs
  @cost_type_map %{
    "withholding_tax" => "withholding_tax",
    "foreign_tax" => "foreign_tax",
    "loan_interest" => "loan_interest",
    "capital_interest" => "capital_interest"
  }

  @doc """
  Processes all broker transactions and extracts costs.
  Returns `{:ok, count}` with the number of new costs created.
  """
  def process do
    results = extract_commissions() ++ extract_typed_costs()

    created = Enum.count(results, &(&1 == :created))
    skipped = Enum.count(results, &(&1 == :skipped))
    Logger.info("CostProcessor: #{created} created, #{skipped} skipped")
    {:ok, created}
  end

  # Extract commissions from buy/sell transactions where commission > 0
  defp extract_commissions do
    BrokerTransaction
    |> where(
      [t],
      t.transaction_type in ["buy", "sell"] and not is_nil(t.commission)
    )
    |> Repo.all()
    |> Enum.map(fn txn ->
      amount = Decimal.abs(txn.commission)

      if Decimal.compare(amount, Decimal.new("0")) == :gt do
        insert_cost(txn, "commission", amount)
      else
        :skipped
      end
    end)
  end

  # Extract costs from dedicated transaction types (tax, interest)
  defp extract_typed_costs do
    types = Map.keys(@cost_type_map)

    BrokerTransaction
    |> where([t], t.transaction_type in ^types)
    |> Repo.all()
    |> Enum.map(fn txn ->
      cost_type = Map.get(@cost_type_map, txn.transaction_type)
      amount = Decimal.abs(txn.amount || Decimal.new("0"))

      if Decimal.compare(amount, Decimal.new("0")) == :gt do
        insert_cost(txn, cost_type, amount)
      else
        :skipped
      end
    end)
  end

  defp insert_cost(txn, cost_type, amount) do
    if cost_exists?(txn) do
      :skipped
    else
      # IBKR amounts are already in EUR (base currency) regardless of Price Currency
      currency = if txn.broker == "ibkr", do: "EUR", else: txn.currency || "EUR"

      attrs = %{
        cost_type: cost_type,
        date: txn.trade_date || txn.entry_date,
        amount: amount,
        currency: currency,
        symbol: txn.security_name,
        isin: txn.isin,
        description: txn.description || txn.raw_type,
        broker: txn.broker,
        broker_transaction_id: txn.id
      }

      case %Cost{} |> Cost.changeset(attrs) |> Repo.insert() do
        {:ok, _} -> :created
        {:error, _} -> :skipped
      end
    end
  end

  defp cost_exists?(txn) do
    Cost
    |> where([c], c.broker_transaction_id == ^txn.id)
    |> Repo.exists?()
  end
end
