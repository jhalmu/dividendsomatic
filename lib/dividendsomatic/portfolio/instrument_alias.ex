defmodule Dividendsomatic.Portfolio.InstrumentAlias do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields [:instrument_id, :symbol]
  @optional_fields [:exchange, :valid_from, :valid_to, :source, :is_primary]

  schema "instrument_aliases" do
    belongs_to :instrument, Dividendsomatic.Portfolio.Instrument
    field :symbol, :string
    field :exchange, :string
    field :valid_from, :date
    field :valid_to, :date
    field :source, :string
    field :is_primary, :boolean, default: false

    timestamps()
  end

  def changeset(alias_record, attrs) do
    alias_record
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:instrument_id)
    |> unique_constraint([:instrument_id, :symbol, :exchange])
    |> unique_constraint(:instrument_id,
      name: :instrument_aliases_one_primary_per_instrument,
      message: "already has a primary alias"
    )
  end
end
