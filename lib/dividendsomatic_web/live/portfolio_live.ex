defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view

  alias Dividendsomatic.{MarketSentiment, Portfolio}

  # F&G refresh interval: 30 minutes
  @fg_refresh_interval :timer.minutes(30)

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()
    fear_greed = get_fear_greed_data()

    if connected?(socket) do
      Process.send_after(self(), :refresh_fear_greed, @fg_refresh_interval)
    end

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

  @impl true
  def handle_info(:refresh_fear_greed, socket) do
    fear_greed = get_fear_greed_data()
    Process.send_after(self(), :refresh_fear_greed, @fg_refresh_interval)
    {:noreply, assign(socket, :fear_greed, fear_greed)}
  end

  # --- Function Components ---

  attr :current_snapshot, :map, required: true
  attr :has_prev, :boolean, required: true
  attr :has_next, :boolean, required: true
  attr :snapshot_position, :integer, required: true
  attr :total_snapshots, :integer, required: true
  attr :compact, :boolean, default: false

  def nav_bar(assigns) do
    ~H"""
    <nav
      class={if @compact, do: "terminal-nav-bar-compact", else: "terminal-nav-bar"}
      aria-label="Snapshot navigation"
    >
      <%= unless @compact do %>
        <button
          phx-click="navigate"
          phx-value-direction="first"
          class="terminal-nav-btn-sm"
          disabled={!@has_prev}
          aria-label="First snapshot"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="w-3.5 h-3.5"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M18.75 19.5l-7.5-7.5 7.5-7.5m-6 15L5.25 12l7.5-7.5"
            />
          </svg>
        </button>
      <% end %>

      <button
        phx-click="navigate"
        phx-value-direction="prev"
        class={if @compact, do: "terminal-nav-btn-compact", else: "terminal-nav-btn"}
        disabled={!@has_prev}
        aria-label="Previous snapshot"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2.5"
          stroke="currentColor"
          class={if @compact, do: "w-3 h-3", else: "w-4 h-4"}
          aria-hidden="true"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
        </svg>
      </button>

      <%= if @compact do %>
        <svg
          class="terminal-rose-flourish"
          width="60"
          height="8"
          viewBox="0 0 60 8"
          aria-hidden="true"
        >
          <path
            d="M0 4 Q15 1, 30 4 Q45 7, 60 4"
            stroke="#ffffff"
            stroke-width="0.4"
            fill="none"
            opacity="0.15"
          />
          <circle cx="30" cy="4" r="1" fill="#ffffff" opacity="0.12" />
        </svg>
      <% end %>

      <div class={if @compact, do: "terminal-nav-date-compact", else: "terminal-nav-date"}>
        <div class={if @compact, do: "terminal-nav-date-main-compact", else: "terminal-nav-date-main"}>
          {Calendar.strftime(@current_snapshot.report_date, "%Y-%m-%d")}
        </div>
        <div class="terminal-nav-date-sub">
          {Calendar.strftime(@current_snapshot.report_date, "%A")}
          <span class="mx-1.5 opacity-30">|</span>
          {@snapshot_position}/{@total_snapshots}
        </div>
      </div>

      <%= if @compact do %>
        <svg
          class="terminal-rose-flourish"
          width="60"
          height="8"
          viewBox="0 0 60 8"
          aria-hidden="true"
        >
          <path
            d="M60 4 Q45 1, 30 4 Q15 7, 0 4"
            stroke="#ffffff"
            stroke-width="0.4"
            fill="none"
            opacity="0.15"
          />
          <circle cx="30" cy="4" r="1" fill="#ffffff" opacity="0.12" />
        </svg>
      <% end %>

      <button
        phx-click="navigate"
        phx-value-direction="next"
        class={if @compact, do: "terminal-nav-btn-compact", else: "terminal-nav-btn"}
        disabled={!@has_next}
        aria-label="Next snapshot"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2.5"
          stroke="currentColor"
          class={if @compact, do: "w-3 h-3", else: "w-4 h-4"}
          aria-hidden="true"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
        </svg>
      </button>

      <%= unless @compact do %>
        <button
          phx-click="navigate"
          phx-value-direction="last"
          class="terminal-nav-btn-sm"
          disabled={!@has_next}
          aria-label="Latest snapshot"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="w-3.5 h-3.5"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M11.25 4.5l7.5 7.5-7.5 7.5m-6-15l7.5 7.5-7.5 7.5"
            />
          </svg>
        </button>
      <% end %>
    </nav>
    """
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
    |> assign(:dividend_by_month, [])
    |> assign(:sparkline_values, [])
    |> assign(:realized_pnl, Decimal.new("0"))
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

    chart_data = Portfolio.get_all_chart_data()
    sparkline_values = Enum.map(chart_data, & &1.value_float)

    socket
    |> assign(:current_snapshot, snapshot)
    |> assign(:holdings, holdings)
    |> assign(:has_prev, Portfolio.has_previous_snapshot?(snapshot.report_date))
    |> assign(:has_next, Portfolio.has_next_snapshot?(snapshot.report_date))
    |> assign(:total_value, total_value)
    |> assign(:total_pnl, total_pnl)
    |> assign(:snapshot_position, snapshot_position)
    |> assign(:total_snapshots, total_snapshots)
    |> assign(:chart_data, chart_data)
    |> assign(:growth_stats, Portfolio.get_growth_stats())
    |> assign(:dividends_ytd, Portfolio.total_dividends_this_year())
    |> assign(:projected_dividends, Portfolio.projected_annual_dividends())
    |> assign(:recent_dividends, Portfolio.list_dividends_this_year() |> Enum.take(5))
    |> assign(:dividend_by_month, Portfolio.dividends_by_month())
    |> assign(:sparkline_values, sparkline_values)
    |> assign(:realized_pnl, Portfolio.total_realized_pnl())
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

  defp pnl_positive?(pnl) do
    Decimal.compare(pnl || Decimal.new("0"), Decimal.new("0")) != :lt
  end
end
