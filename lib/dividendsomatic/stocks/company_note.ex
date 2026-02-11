defmodule Dividendsomatic.Stocks.CompanyNote do
  @moduledoc """
  Schema for user-editable company notes and investment thesis.
  Keyed by ISIN as the primary identifier.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "company_notes" do
    field :isin, :string
    field :symbol, :string
    field :name, :string
    field :asset_type, :string, default: "stock"
    field :notes_markdown, :string
    field :thesis, :string
    field :tags, {:array, :string}, default: []
    field :watchlist, :boolean, default: false

    timestamps()
  end

  @required_fields [:isin]
  @optional_fields [:symbol, :name, :asset_type, :notes_markdown, :thesis, :tags, :watchlist]

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:asset_type, ~w(stock etf reit bdc))
    |> unique_constraint(:isin)
  end
end
