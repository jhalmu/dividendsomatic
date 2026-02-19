defmodule Dividendsomatic.Portfolio.CorporateAction do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields [:action_type, :date]
  @optional_fields [:instrument_id, :description, :quantity, :amount, :raw_data]

  schema "corporate_actions" do
    belongs_to :instrument, Dividendsomatic.Portfolio.Instrument
    field :action_type, :string
    field :date, :date
    field :description, :string
    field :quantity, :decimal
    field :amount, :decimal
    field :raw_data, :map, default: %{}

    timestamps()
  end

  def changeset(corporate_action, attrs) do
    corporate_action
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:instrument_id)
  end
end
