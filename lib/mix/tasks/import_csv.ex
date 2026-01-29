defmodule Mix.Tasks.Import.Csv do
  @moduledoc """
  Import CSV file into database.
  
  Usage: mix import.csv path/to/file.csv
  """
  use Mix.Task
  
  import Ecto.Query
  alias Dividendsomatic.Portfolio

  @shortdoc "Import portfolio CSV file"
  def run([file_path]) do
    Mix.Task.run("app.start")
    
    case File.read(file_path) do
      {:ok, csv_data} ->
        # Extract report date from CSV
        [first_line | _] = csv_data |> String.split("\n", parts: 3, trim: true) |> Enum.drop(1)
        report_date = extract_date(first_line)
        
        IO.puts("Importing snapshot for #{report_date}...")
        
        case Portfolio.create_snapshot_from_csv(csv_data, report_date) do
          {:ok, {:ok, snapshot}} ->
            count = Dividendsomatic.Repo.one!(
              from h in Dividendsomatic.Portfolio.Holding,
              where: h.portfolio_snapshot_id == ^snapshot.id,
              select: count(h.id)
            )
            IO.puts("✓ Successfully imported #{count} holdings")
          {:error, error} ->
            IO.puts("✗ Error: #{inspect(error)}")
        end
        
      {:error, reason} ->
        IO.puts("Failed to read file: #{reason}")
    end
  end

  def run(_) do
    IO.puts("Usage: mix import.csv path/to/file.csv")
  end

  defp extract_date(line) do
    [date_str | _] = String.split(line, ",", parts: 2)
    date_str = String.trim(date_str, "\"")
    
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end
end
