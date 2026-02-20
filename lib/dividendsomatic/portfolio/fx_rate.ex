defmodule Dividendsomatic.Portfolio.FxRate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields [:date, :currency, :rate]
  @optional_fields [:source]

  schema "fx_rates" do
    field :date, :date
    field :currency, :string
    field :rate, :decimal
    field :source, :string

    timestamps()
  end

  def changeset(fx_rate, attrs) do
    fx_rate
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:date, :currency])
  end
end
