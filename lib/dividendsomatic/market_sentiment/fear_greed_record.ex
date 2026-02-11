defmodule Dividendsomatic.MarketSentiment.FearGreedRecord do
  @moduledoc """
  Schema for historical Fear & Greed Index values.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fear_greed_history" do
    field :date, :date
    field :value, :integer
    field :classification, :string

    timestamps()
  end

  @required_fields [:date, :value, :classification]

  def changeset(record, attrs) do
    record
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:value, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint(:date)
  end
end
