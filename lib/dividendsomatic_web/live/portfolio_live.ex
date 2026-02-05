defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view

  alias Dividendsomatic.{MarketSentiment, Portfolio}

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()
    fear_greed = get_fear_greed_data()

    socket =
      socket
      |> assign_snapshot(snapshot)
      |> assign(:fear_greed, fear_greed)

    {:ok, socket}
  end

  defp get_fear_greed_data do
    case MarketSentiment.get_fear_greed_index_cached() do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  end

  @impl true
  def handle_params(%{"date" => date_string}, _uri, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        snapshot = Portfolio.get_snapshot_by_date(date)
        {:noreply, assign_snapshot(socket, snapshot)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("navigate", %{"direction" => "prev"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.report_date
      prev_snapshot = Portfolio.get_previous_snapshot(date)
      {:noreply, assign_snapshot(socket, prev_snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "next"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.report_date
      next_snapshot = Portfolio.get_next_snapshot(date)
      {:noreply, assign_snapshot(socket, next_snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "first"}, socket) do
    first_snapshot = Portfolio.get_first_snapshot()
    {:noreply, assign_snapshot(socket, first_snapshot)}
  end

  def handle_event("navigate", %{"direction" => "last"}, socket) do
    latest_snapshot = Portfolio.get_latest_snapshot()
    {:noreply, assign_snapshot(socket, latest_snapshot)}
  end

  defp assign_snapshot(socket, nil) do
    socket
    |> assign(:current_snapshot, nil)
    |> assign(:holdings, [])
    |> assign(:has_prev, false)
    |> assign(:has_next, false)
    |> assign(:total_value, Decimal.new("0"))
    |> assign(:total_pnl, Decimal.new("0"))
    |> assign(:snapshot_position, 0)
    |> assign(:total_snapshots, 0)
    |> assign(:chart_data, [])
    |> assign(:growth_stats, nil)
    |> assign(:dividends_ytd, Decimal.new("0"))
    |> assign(:projected_dividends, Decimal.new("0"))
    |> assign(:recent_dividends, [])
  end

  defp assign_snapshot(socket, snapshot) do
    holdings = snapshot.holdings || []

    total_value =
      Enum.reduce(holdings, Decimal.new("0"), fn h, acc ->
        Decimal.add(acc, h.position_value || Decimal.new("0"))
      end)

    total_pnl =
      Enum.reduce(holdings, Decimal.new("0"), fn h, acc ->
        Decimal.add(acc, h.fifo_pnl_unrealized || Decimal.new("0"))
      end)

    total_snapshots = Portfolio.count_snapshots()
    snapshot_position = Portfolio.get_snapshot_position(snapshot.report_date)

    socket
    |> assign(:current_snapshot, snapshot)
    |> assign(:holdings, holdings)
    |> assign(:has_prev, Portfolio.has_previous_snapshot?(snapshot.report_date))
    |> assign(:has_next, Portfolio.has_next_snapshot?(snapshot.report_date))
    |> assign(:total_value, total_value)
    |> assign(:total_pnl, total_pnl)
    |> assign(:snapshot_position, snapshot_position)
    |> assign(:total_snapshots, total_snapshots)
    |> assign(:chart_data, Portfolio.get_all_chart_data())
    |> assign(:growth_stats, Portfolio.get_growth_stats())
    |> assign(:dividends_ytd, Portfolio.total_dividends_this_year())
    |> assign(:projected_dividends, Portfolio.projected_annual_dividends())
    |> assign(:recent_dividends, Portfolio.list_dividends_this_year() |> Enum.take(5))
  end

  defp format_decimal(nil), do: "0.00"

  defp format_decimal(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp pnl_badge_class(pnl) do
    pnl = pnl || Decimal.new("0")

    cond do
      Decimal.compare(pnl, Decimal.new("0")) == :gt -> "terminal-gain"
      Decimal.compare(pnl, Decimal.new("0")) == :lt -> "terminal-loss"
      true -> ""
    end
  end

  defp format_integer(nil), do: "0"

  defp format_integer(decimal) do
    decimal
    |> Decimal.round(0)
    |> Decimal.to_integer()
    |> Integer.to_string()
    |> add_thousands_separator()
  end

  defp add_thousands_separator(str) do
    str
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
