alias Dividendsomatic.Repo
alias Dividendsomatic.Portfolio.Dividend

divs = Dividend |> Repo.all()
by_symbol = Enum.group_by(divs, & &1.symbol)

# Find total_net records that have a matching per_share within ±30 days (same symbol)
duplicates =
  by_symbol
  |> Enum.flat_map(fn {_sym, records} ->
    ps = Enum.filter(records, & &1.amount_type == "per_share")
    tn = Enum.filter(records, & &1.amount_type == "total_net")

    for t <- tn,
        Enum.any?(ps, fn p -> abs(Date.diff(p.ex_date, t.ex_date)) <= 30 end),
        do: t
  end)

IO.puts("Found #{length(duplicates)} duplicate total_net records to delete.\n")

# Show what we're deleting
duplicates
|> Enum.sort_by(fn d -> {d.symbol, d.ex_date} end)
|> Enum.group_by(& &1.symbol)
|> Enum.each(fn {sym, records} ->
  IO.puts("#{sym}: #{length(records)} records")
  for r <- Enum.take(records, 3) do
    IO.puts("  #{r.ex_date} $#{r.amount} #{r.currency} (#{r.source})")
  end
  if length(records) > 3, do: IO.puts("  ... +#{length(records) - 3} more")
end)

# Delete them
IO.puts("\nDeleting #{length(duplicates)} records...")

for d <- duplicates do
  Repo.delete!(d)
end

# Verify
remaining_tn = Dividend |> Repo.all() |> Enum.filter(& &1.amount_type == "total_net")
IO.puts("\nDone. Remaining total_net records: #{length(remaining_tn)}")
for r <- Enum.sort_by(remaining_tn, fn d -> {d.symbol, d.ex_date} end) do
  IO.puts("  #{r.symbol} #{r.ex_date} $#{r.amount} #{r.currency} (#{r.source})")
end
