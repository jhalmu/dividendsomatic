defmodule Dividendsomatic.Portfolio.LegacyPortfolioSnapshot do
  @moduledoc """
  Legacy schema for reading old portfolio_snapshots data (now legacy_portfolio_snapshots).

  Used only by the data migration task. Will be removed after migration is verified.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "legacy_portfolio_snapshots" do
    field :report_date, :date
    field :raw_csv_data, :string
    field :source, :string

    timestamps()
  end
end
