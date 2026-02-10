defmodule Dividendsomatic.Repo do
  use Ecto.Repo,
    otp_app: :dividendsomatic,
    adapter: Ecto.Adapters.Postgres
end
