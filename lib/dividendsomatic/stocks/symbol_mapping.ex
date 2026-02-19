defmodule Dividendsomatic.Stocks.SymbolMapping do
  @moduledoc """
  Schema for ISIN to Finnhub symbol mappings.

  Caches the resolved mapping between ISIN identifiers and Finnhub-compatible
  ticker symbols. Status tracks resolution state: pending, resolved, unmappable.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "legacy_symbol_mappings" do
    field :isin, :string
    field :finnhub_symbol, :string
    field :security_name, :string
    field :currency, :string
    field :exchange, :string
    field :status, :string, default: "pending"
    field :notes, :string

    timestamps()
  end

  @required_fields [:isin, :status]
  @optional_fields [:finnhub_symbol, :security_name, :currency, :exchange, :notes]

  @doc false
  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(pending resolved unmappable))
    |> unique_constraint(:isin, name: "symbol_mappings_isin_index")
  end
end
