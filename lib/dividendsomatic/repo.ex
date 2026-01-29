defmodule Dividendsomatic.Repo do
  use Ecto.Repo,
    otp_app: :dividendsomatic,
    adapter: Ecto.Adapters.SQLite3
end
