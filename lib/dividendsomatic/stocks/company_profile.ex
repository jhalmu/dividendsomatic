defmodule Dividendsomatic.Stocks.CompanyProfile do
  @moduledoc """
  Schema for cached company profiles.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "company_profiles" do
    field :symbol, :string
    field :name, :string
    field :country, :string
    field :currency, :string
    field :exchange, :string
    field :ipo_date, :date
    field :market_cap, :decimal
    field :sector, :string
    field :industry, :string
    field :logo_url, :string
    field :web_url, :string
    field :fetched_at, :utc_datetime

    timestamps()
  end

  @required_fields [:symbol, :fetched_at]
  @optional_fields [
    :name,
    :country,
    :currency,
    :exchange,
    :ipo_date,
    :market_cap,
    :sector,
    :industry,
    :logo_url,
    :web_url
  ]

  @doc false
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:symbol)
  end
end
