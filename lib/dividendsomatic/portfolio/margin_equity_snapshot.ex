defmodule Dividendsomatic.Portfolio.MarginEquitySnapshot do
  @moduledoc """
  Schema for daily margin and equity breakdown.

  Stores cash balance, margin loan, and derived metrics from IBKR Flex reports.
  One row per date — the source of truth for own equity vs borrowed capital.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "margin_equity_snapshots" do
    field :date, :date
    field :cash_balance, :decimal
    field :margin_loan, :decimal
    field :net_liquidation_value, :decimal
    field :own_equity, :decimal
    field :leverage_ratio, :decimal
    field :loan_to_value, :decimal
    field :source, :string
    field :metadata, :map

    timestamps()
  end

  @required_fields [:date, :source]
  @optional_fields [
    :cash_balance,
    :margin_loan,
    :net_liquidation_value,
    :own_equity,
    :leverage_ratio,
    :loan_to_value,
    :metadata
  ]

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:date)
    |> compute_derived_fields()
  end

  defp compute_derived_fields(changeset) do
    nlv = get_field(changeset, :net_liquidation_value)
    own = get_field(changeset, :own_equity)
    margin = get_field(changeset, :margin_loan)

    changeset
    |> maybe_compute_leverage(nlv, own)
    |> maybe_compute_ltv(margin, nlv)
  end

  defp maybe_compute_leverage(changeset, nlv, own)
       when not is_nil(nlv) and not is_nil(own) do
    zero = Decimal.new("0")

    if Decimal.compare(own, zero) == :gt do
      ratio = nlv |> Decimal.div(own) |> Decimal.round(2)
      put_change(changeset, :leverage_ratio, ratio)
    else
      changeset
    end
  end

  defp maybe_compute_leverage(changeset, _, _), do: changeset

  defp maybe_compute_ltv(changeset, margin, nlv)
       when not is_nil(margin) and not is_nil(nlv) do
    zero = Decimal.new("0")

    if Decimal.compare(nlv, zero) == :gt do
      ltv = margin |> Decimal.div(nlv) |> Decimal.round(4)
      put_change(changeset, :loan_to_value, ltv)
    else
      changeset
    end
  end

  defp maybe_compute_ltv(changeset, _, _), do: changeset
end
