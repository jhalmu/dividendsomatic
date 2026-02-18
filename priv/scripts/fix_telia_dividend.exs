alias Dividendsomatic.Repo
alias Dividendsomatic.Portfolio.Dividend
import Ecto.Query

d =
  Dividend
  |> where([d], d.symbol == "TELIA1" and d.ex_date == ^~D[2023-08-03])
  |> Repo.one!()

IO.puts("Before: #{d.amount} #{d.currency} (source: #{d.source})")

d
|> Ecto.Changeset.change(%{amount: Decimal.new("0.047095"), currency: "EUR"})
|> Repo.update!()

IO.puts("After:  0.047095 EUR — matches other TELIA1 quarterly entries")
