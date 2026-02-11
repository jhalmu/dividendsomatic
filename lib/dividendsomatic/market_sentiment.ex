defmodule Dividendsomatic.MarketSentiment do
  @moduledoc """
  Fetches market sentiment data including Fear & Greed Index.

  Uses Alternative.me API which is free and requires no authentication.
  Stores historical values in the database for per-snapshot display.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.MarketSentiment.FearGreedRecord
  alias Dividendsomatic.Repo

  @fear_greed_url "https://api.alternative.me/fng/"

  @doc """
  Fetches the current Fear & Greed Index.

  Returns a map with:
  - `value` - Numeric value (0-100)
  - `classification` - Text classification ("Extreme Fear", "Fear", "Neutral", "Greed", "Extreme Greed")
  - `timestamp` - When the data was last updated
  - `color` - Suggested display color

  ## Examples

      iex> Dividendsomatic.MarketSentiment.get_fear_greed_index()
      {:ok, %{value: 62, classification: "Greed", timestamp: ~U[2026-02-05 12:00:00Z], color: "emerald"}}
  """
  def get_fear_greed_index do
    case Req.get(@fear_greed_url, params: [limit: 1]) do
      {:ok, %{status: 200, body: %{"data" => [data | _]}}} ->
        value = String.to_integer(data["value"])
        classification = data["value_classification"]
        timestamp = parse_timestamp(data["timestamp"])

        {:ok,
         %{
           value: value,
           classification: classification,
           timestamp: timestamp,
           color: get_color(value)
         }}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Fear & Greed API failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("Fear & Greed request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches historical F&G data from the API and stores in DB.
  `days` controls how many days to fetch (max ~365 on free API).
  """
  def fetch_and_store_history(days \\ 365) do
    case Req.get(@fear_greed_url, params: [limit: days]) do
      {:ok, %{status: 200, body: %{"data" => data_list}}} ->
        results =
          Enum.map(data_list, fn data ->
            value = String.to_integer(data["value"])
            timestamp = parse_timestamp(data["timestamp"])
            date = DateTime.to_date(timestamp)

            %FearGreedRecord{}
            |> FearGreedRecord.changeset(%{
              date: date,
              value: value,
              classification: data["value_classification"]
            })
            |> Repo.insert(on_conflict: :nothing, conflict_target: :date)
          end)

        new_count =
          Enum.count(results, fn
            {:ok, %{id: id}} -> id != nil
            _ -> false
          end)

        Logger.info("F&G history: #{new_count} new records stored (#{length(data_list)} fetched)")
        {:ok, new_count}

      {:ok, %{status: status, body: body}} ->
        Logger.error("F&G history API failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("F&G history request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the F&G value for a specific date from the database.
  Returns nil if not found. Falls back to nearest available date within 3 days.
  """
  def get_fear_greed_for_date(date) do
    # Try exact date first
    case Repo.get_by(FearGreedRecord, date: date) do
      %FearGreedRecord{} = record ->
        to_display_map(record)

      nil ->
        # Fall back to nearest date within 3 days
        three_days_before = Date.add(date, -3)
        three_days_after = Date.add(date, 3)

        FearGreedRecord
        |> where([r], r.date >= ^three_days_before and r.date <= ^three_days_after)
        |> order_by([r], asc: fragment("ABS(? - ?)", r.date, ^date))
        |> limit(1)
        |> Repo.one()
        |> case do
          nil -> nil
          record -> to_display_map(record)
        end
    end
  end

  defp to_display_map(%FearGreedRecord{} = record) do
    %{
      value: record.value,
      classification: record.classification,
      timestamp: nil,
      color: get_color(record.value)
    }
  end

  @doc """
  Gets the Fear & Greed Index with caching.

  Caches the result for 1 hour to avoid excessive API calls.
  Falls back to cached value on error.
  """
  def get_fear_greed_index_cached do
    cache_key = :fear_greed_index
    cache_ttl_seconds = 3600

    case :persistent_term.get(cache_key, nil) do
      {cached_value, cached_at} when is_integer(cached_at) ->
        age_seconds = System.system_time(:second) - cached_at

        if age_seconds < cache_ttl_seconds do
          {:ok, cached_value}
        else
          refresh_cache(cache_key)
        end

      nil ->
        refresh_cache(cache_key)
    end
  end

  defp refresh_cache(cache_key) do
    case get_fear_greed_index() do
      {:ok, value} ->
        :persistent_term.put(cache_key, {value, System.system_time(:second)})
        {:ok, value}

      {:error, _reason} = error ->
        case :persistent_term.get(cache_key, nil) do
          {cached_value, _} -> {:ok, cached_value}
          nil -> error
        end
    end
  end

  defp parse_timestamp(timestamp_str) when is_binary(timestamp_str) do
    timestamp_int = String.to_integer(timestamp_str)
    DateTime.from_unix!(timestamp_int)
  end

  @doc false
  def get_color(value) when value <= 25, do: "red"
  def get_color(value) when value <= 45, do: "orange"
  def get_color(value) when value <= 55, do: "yellow"
  def get_color(value) when value <= 75, do: "emerald"
  def get_color(_value), do: "green"
end
