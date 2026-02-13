defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view

  import DividendsomaticWeb.Helpers.FormatHelpers

  alias Dividendsomatic.{MarketSentiment, Portfolio}

  # F&G refresh interval: 30 minutes
  @fg_refresh_interval :timer.minutes(30)

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()
    live_fg = get_fear_greed_live()

    if connected?(socket) do
      Process.send_after(self(), :refresh_fear_greed, @fg_refresh_interval)
    end

    socket =
      socket
      |> assign(:live_fear_greed, live_fg)
      |> assign_snapshot(snapshot)

    {:ok, socket}
  end

  defp get_fear_greed_live do
    case MarketSentiment.get_fear_greed_index_cached() do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  end

  defp get_fear_greed_for_snapshot(socket, snapshot) do
    # Try historical DB data for this date
    case MarketSentiment.get_fear_greed_for_date(snapshot.report_date) do
      nil -> socket.assigns[:live_fear_greed]
      data -> data
    end
  end

  @impl true
  def handle_params(%{"date" => date_string}, _uri, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        # Skip reload if already on this date (from push_patch after navigate event)
        if socket.assigns.current_snapshot &&
             socket.assigns.current_snapshot.report_date == date do
          {:noreply, socket}
        else
          snapshot = Portfolio.get_snapshot_by_date(date)
          {:noreply, assign_snapshot(socket, snapshot)}
        end

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
      {:noreply, navigate_to_snapshot(socket, prev_snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "next"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.report_date
      next_snapshot = Portfolio.get_next_snapshot(date)
      {:noreply, navigate_to_snapshot(socket, next_snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "back3"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.report_date
      snapshot = Portfolio.get_snapshot_back(date, 3) || Portfolio.get_first_snapshot()
      {:noreply, navigate_to_snapshot(socket, snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "forward3"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.report_date
      snapshot = Portfolio.get_snapshot_forward(date, 3) || Portfolio.get_latest_snapshot()
      {:noreply, navigate_to_snapshot(socket, snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "first"}, socket) do
    first_snapshot = Portfolio.get_first_snapshot()
    {:noreply, navigate_to_snapshot(socket, first_snapshot)}
  end

  def handle_event("navigate", %{"direction" => "last"}, socket) do
    latest_snapshot = Portfolio.get_latest_snapshot()
    {:noreply, navigate_to_snapshot(socket, latest_snapshot)}
  end

  @impl true
  def handle_info(:refresh_fear_greed, socket) do
    live_fg = get_fear_greed_live()
    Process.send_after(self(), :refresh_fear_greed, @fg_refresh_interval)

    socket = assign(socket, :live_fear_greed, live_fg)

    # If viewing latest snapshot, update displayed F&G too
    socket =
      if socket.assigns.current_snapshot && !socket.assigns.has_next do
        assign(socket, :fear_greed, live_fg)
      else
        socket
      end

    {:noreply, socket}
  end

  # --- Function Components ---

  attr :current_snapshot, :map, required: true
  attr :has_prev, :boolean, required: true
  attr :has_next, :boolean, required: true
  attr :snapshot_position, :integer, required: true
  attr :total_snapshots, :integer, required: true
  attr :compact, :boolean, default: false

  def nav_bar(assigns) do
    btn_class = if assigns.compact, do: "terminal-nav-btn-compact", else: "terminal-nav-btn"
    sm_class = if assigns.compact, do: "terminal-nav-btn-compact", else: "terminal-nav-btn-sm"
    icon_size = if assigns.compact, do: "w-3 h-3", else: "w-4 h-4"
    sm_icon = if assigns.compact, do: "w-2.5 h-2.5", else: "w-3.5 h-3.5"

    assigns =
      assigns
      |> assign(:btn_class, btn_class)
      |> assign(:sm_class, sm_class)
      |> assign(:icon_size, icon_size)
      |> assign(:sm_icon, sm_icon)

    ~H"""
    <nav
      class={if @compact, do: "terminal-nav-bar-compact", else: "terminal-nav-bar"}
      aria-label="Snapshot navigation"
    >
      <%!-- First --%>
      <button
        phx-click="navigate"
        phx-value-direction="first"
        class={@sm_class}
        disabled={!@has_prev}
        aria-label="First snapshot"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2"
          stroke="currentColor"
          class={@sm_icon}
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M18.75 19.5l-7.5-7.5 7.5-7.5m-6 15L5.25 12l7.5-7.5"
          />
        </svg>
      </button>

      <%!-- Back 3 --%>
      <button
        phx-click="navigate"
        phx-value-direction="back3"
        class={@sm_class}
        disabled={!@has_prev}
        aria-label="Back 3 snapshots"
      >
        <span style="font-family: var(--font-mono); font-size: 0.5rem; opacity: 0.7;">-3</span>
      </button>

      <%!-- Prev --%>
      <button
        phx-click="navigate"
        phx-value-direction="prev"
        class={@btn_class}
        disabled={!@has_prev}
        aria-label="Previous snapshot"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2.5"
          stroke="currentColor"
          class={@icon_size}
          aria-hidden="true"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5L8.25 12l7.5-7.5" />
        </svg>
      </button>

      <%!-- Date --%>
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

      <%!-- Next --%>
      <button
        phx-click="navigate"
        phx-value-direction="next"
        class={@btn_class}
        disabled={!@has_next}
        aria-label="Next snapshot"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2.5"
          stroke="currentColor"
          class={@icon_size}
          aria-hidden="true"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 4.5l7.5 7.5-7.5 7.5" />
        </svg>
      </button>

      <%!-- Forward 3 --%>
      <button
        phx-click="navigate"
        phx-value-direction="forward3"
        class={@sm_class}
        disabled={!@has_next}
        aria-label="Forward 3 snapshots"
      >
        <span style="font-family: var(--font-mono); font-size: 0.5rem; opacity: 0.7;">+3</span>
      </button>

      <%!-- Last --%>
      <button
        phx-click="navigate"
        phx-value-direction="last"
        class={@sm_class}
        disabled={!@has_next}
        aria-label="Latest snapshot"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2"
          stroke="currentColor"
          class={@sm_icon}
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M11.25 4.5l7.5 7.5-7.5 7.5m-6-15l7.5 7.5-7.5 7.5"
          />
        </svg>
      </button>
    </nav>
    """
  end

  defp navigate_to_snapshot(socket, nil), do: socket

  defp navigate_to_snapshot(socket, snapshot) do
    date = Date.to_string(snapshot.report_date)

    socket
    |> assign_snapshot(snapshot)
    |> push_patch(to: "/portfolio/#{date}", replace: true)
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
    |> assign(:dividend_year, Date.utc_today().year)
    |> assign(:dividend_total, Decimal.new("0"))
    |> assign(:projected_dividends, nil)
    |> assign(:recent_dividends, [])
    |> assign(:dividend_by_month, [])
    |> assign(:sparkline_values, [])
    |> assign(:realized_pnl, Decimal.new("0"))
    |> assign(:fear_greed, nil)
    |> assign(:fx_exposure, [])
    |> assign(:sold_positions, [])
    |> assign(:cash_flow, [])
  end

  defp assign_snapshot(socket, snapshot) do
    holdings = snapshot.holdings || []

    total_value =
      Enum.reduce(holdings, Decimal.new("0"), fn h, acc ->
        fx = h.fx_rate_to_base || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(h.position_value || Decimal.new("0"), fx))
      end)

    total_pnl =
      Enum.reduce(holdings, Decimal.new("0"), fn h, acc ->
        fx = h.fx_rate_to_base || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(h.fifo_pnl_unrealized || Decimal.new("0"), fx))
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
    |> assign(:growth_stats, Portfolio.get_growth_stats(snapshot))
    |> assign_dividend_stats()
    |> assign(:recent_dividends, Portfolio.list_dividends_with_income() |> Enum.take(5))
    |> assign(:dividend_by_month, dividends_for_chart(chart_data))
    |> assign(:sparkline_values, sparkline_values)
    |> assign(:realized_pnl, Portfolio.total_realized_pnl())
    |> assign(:fear_greed, get_fear_greed_for_snapshot(socket, snapshot))
    |> assign(:fx_exposure, Portfolio.compute_fx_exposure(holdings))
    |> assign(:sold_positions_grouped, Portfolio.list_sold_positions_grouped())
    |> assign(:sold_positions_count, Portfolio.count_sold_positions())
    |> assign(:cash_flow, Portfolio.dividend_cash_flow_summary())
  end

  defp dividends_for_chart([first | _] = chart_data) do
    last_date = List.last(chart_data).date
    Portfolio.dividends_by_month(first.date, last_date)
  end

  defp dividends_for_chart(_), do: []

  defp assign_dividend_stats(socket) do
    snapshot = socket.assigns.current_snapshot
    year = if snapshot, do: snapshot.report_date.year, else: Date.utc_today().year
    total = Portfolio.total_dividends_for_year(year)
    current_year = Date.utc_today().year

    projected =
      if year == current_year do
        Portfolio.projected_annual_dividends()
      else
        nil
      end

    socket
    |> assign(:dividend_year, year)
    |> assign(:dividend_total, total)
    |> assign(:projected_dividends, projected)
  end
end
