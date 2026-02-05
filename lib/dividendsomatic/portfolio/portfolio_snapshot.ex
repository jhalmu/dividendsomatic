defmodule Dividendsomatic.Portfolio.PortfolioSnapshot do
  @moduledoc """
  Schema representing a daily portfolio snapshot from Interactive Brokers.

  Each snapshot captures the state of all holdings on a specific report date,
  with the original CSV data stored for reference.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_snapshots" do
    field :report_date, :date
    field :raw_csv_data, :string

    has_many :holdings, Dividendsomatic.Portfolio.Holding

    timestamps()
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:report_date, :raw_csv_data])
    |> validate_required([:report_date])
    |> unique_constraint(:report_date)
  end
end
