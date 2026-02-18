alias Dividendsomatic.Repo
alias Dividendsomatic.Portfolio.{Dividend, Position}
import Ecto.Query

# Get all total_net non-EUR dividends without fx_rate
divs =
  Dividend
  |> where([d], d.amount_type == "total_net" and d.currency != "EUR" and is_nil(d.fx_rate))
  |> order_by([d], asc: d.ex_date)
  |> Repo.all()

IO.puts("Found #{length(divs)} total_net dividends without fx_rate\n")

# Build positions lookup
positions = Position |> Repo.all()
pos_by_symbol = Enum.group_by(positions, &(&1.symbol))

{updated, skipped} =
  Enum.reduce(divs, {0, 0}, fn d, {ok, skip} ->
    match =
      pos_by_symbol
      |> Map.get(d.symbol, [])
      |> Enum.filter(fn p -> p.currency == d.currency end)
      |> Enum.min_by(fn p -> abs(Date.diff(p.date, d.ex_date)) end, fn -> nil end)

    if match do
      d
      |> Ecto.Changeset.change(%{fx_rate: match.fx_rate})
      |> Repo.update!()

      IO.puts("  OK  #{d.symbol} #{d.ex_date} #{d.currency} → fx=#{match.fx_rate}")
      {ok + 1, skip}
    else
      IO.puts("  SKIP #{d.symbol} #{d.ex_date} #{d.currency} (no matching position)")
      {ok, skip + 1}
    end
  end)

IO.puts("\nBackfill complete: #{updated} updated, #{skipped} skipped")
