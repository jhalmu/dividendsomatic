defmodule Dividendsomatic.MarketSentiment do
  @moduledoc """
  Fetches market sentiment data including CNN Fear & Greed Index.

  Uses CNN's stock market Fear & Greed Index (equity-focused).
  Stores historical values in the database for per-snapshot display.
  """

  import Ecto.Query
  require Logger

  alias Dividendsomatic.MarketSentiment.FearGreedRecord
  alias Dividendsomatic.Repo

  @cnn_fg_url "https://production.dataviz.cnn.io/index/fearandgreed/graphdata"
  @cnn_headers [
    {"user-agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"},
    {"accept", "application/json"},
    {"referer", "https://edition.cnn.com/markets/fear-and-greed"}
  ]

  @doc """
  Fetches the current Fear & Greed Index from CNN.

  Returns a map with:
  - `value` - Numeric value (0-100)
  - `classification` - Text classification ("Extreme Fear", "Fear", "Neutral", "Greed", "Extreme Greed")
  - `timestamp` - When the data was last updated
  - `color` - Suggested display color
  """
  def get_fear_greed_index do
    # CNN endpoint returns current + historical when given a start date
    start_date = Date.to_iso8601(Date.add(Date.utc_today(), -1))
    url = "#{@cnn_fg_url}/#{start_date}"

    case Req.get(url, headers: @cnn_headers) do
      {:ok, %{status: 200, body: %{"fear_and_greed" => fg}}} when is_map(fg) ->
        value = round(fg["score"])
        classification = classify_value(value)

        {:ok,
         %{
           value: value,
           classification: classification,
           timestamp: DateTime.utc_now(),
           color: get_color(value)
         }}

      {:ok, %{status: status, body: body}} ->
        Logger.error("CNN F&G API failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("CNN F&G request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches historical F&G data from CNN and stores in DB.
  Fetches from `start_date` (default: 2 years ago) to today.
  """
  def fetch_and_store_history(start_date \\ nil) do
    start_date = start_date || Date.to_iso8601(Date.add(Date.utc_today(), -730))
    url = "#{@cnn_fg_url}/#{start_date}"

    case Req.get(url, headers: @cnn_headers) do
      {:ok, %{status: 200, body: %{"fear_and_greed_historical" => %{"data" => data_list}}}} ->
        results =
          Enum.map(data_list, fn point ->
            value = round(point["y"])
            # CNN timestamps are milliseconds
            date = DateTime.from_unix!(round(point["x"] / 1000)) |> DateTime.to_date()

            %FearGreedRecord{}
            |> FearGreedRecord.changeset(%{
              date: date,
              value: value,
              classification: point["rating"] || classify_value(value)
            })
            |> Repo.insert(on_conflict: :nothing, conflict_target: :date)
          end)

        new_count =
          Enum.count(results, fn
            {:ok, %{id: id}} -> id != nil
            _ -> false
          end)

        Logger.info(
          "CNN F&G history: #{new_count} new records stored (#{length(data_list)} fetched)"
        )

        {:ok, new_count}

      {:ok, %{status: status, body: body}} ->
        Logger.error("CNN F&G history API failed: #{status} - #{inspect(body)}")
        {:error, :api_error}

      {:error, reason} ->
        Logger.error("CNN F&G history request failed: #{inspect(reason)}")
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

  defp classify_value(value) when value <= 25, do: "Extreme Fear"
  defp classify_value(value) when value <= 45, do: "Fear"
  defp classify_value(value) when value <= 55, do: "Neutral"
  defp classify_value(value) when value <= 75, do: "Greed"
  defp classify_value(_value), do: "Extreme Greed"

  @doc false
  def get_color(value) when value <= 25, do: "red"
  def get_color(value) when value <= 45, do: "orange"
  def get_color(value) when value <= 55, do: "yellow"
  def get_color(value) when value <= 75, do: "emerald"
  def get_color(_value), do: "green"
end
