defmodule Dividendsomatic.Repo.Migrations.AddDeclaredDividendFields do
  use Ecto.Migration

  def change do
    alter table(:instruments) do
      add :dividend_per_payment, :decimal
      add :payments_per_year, :integer
    end
  end
end
