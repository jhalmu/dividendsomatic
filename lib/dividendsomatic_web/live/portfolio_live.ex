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
    case MarketSentiment.get_fear_greed_for_date(snapshot.date) do
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
             socket.assigns.current_snapshot.date == date do
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
      date = socket.assigns.current_snapshot.date
      prev_snapshot = Portfolio.get_previous_snapshot(date)
      {:noreply, navigate_to_snapshot(socket, prev_snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "next"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.date
      next_snapshot = Portfolio.get_next_snapshot(date)
      {:noreply, navigate_to_snapshot(socket, next_snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "back3"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.date
      snapshot = Portfolio.get_snapshot_back(date, 3) || Portfolio.get_first_snapshot()
      {:noreply, navigate_to_snapshot(socket, snapshot)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate", %{"direction" => "forward3"}, socket) do
    if socket.assigns.current_snapshot do
      date = socket.assigns.current_snapshot.date
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

  def handle_event("slider_navigate", %{"position" => pos_str}, socket) do
    case Integer.parse(pos_str) do
      {pos, _} ->
        snapshot = Portfolio.get_snapshot_at_position(pos)
        {:noreply, navigate_to_snapshot(socket, snapshot)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("pnl_year", %{"year" => "all"}, socket) do
    {:noreply, socket |> assign(:pnl_year, nil) |> assign_pnl_summary()}
  end

  def handle_event("pnl_year", %{"year" => year}, socket) do
    {:noreply, socket |> assign(:pnl_year, String.to_integer(year)) |> assign_pnl_summary()}
  end

  def handle_event("pnl_show_all", _params, socket) do
    {:noreply, assign(socket, :pnl_show_all, !socket.assigns.pnl_show_all)}
  end

  def handle_event("chart_year", %{"year" => "all"}, socket) do
    n = length(socket.assigns.all_chart_data)

    socket =
      socket
      |> assign(:chart_year, nil)
      |> assign(:chart_start, 1)
      |> assign(:chart_end, n)
      |> assign_chart_range()

    {:noreply, socket}
  end

  def handle_event("chart_year", %{"year" => year_str}, socket) do
    year = String.to_integer(year_str)
    all = socket.assigns.all_chart_data

    # Find first and last index for this year (1-based)
    indices =
      all
      |> Enum.with_index(1)
      |> Enum.filter(fn {point, _idx} -> point.date.year == year end)
      |> Enum.map(fn {_point, idx} -> idx end)

    case indices do
      [] ->
        {:noreply, socket}

      idxs ->
        socket =
          socket
          |> assign(:chart_year, year)
          |> assign(:chart_start, Enum.min(idxs))
          |> assign(:chart_end, Enum.max(idxs))
          |> assign_chart_range()

        {:noreply, socket}
    end
  end

  def handle_event("chart_range", %{"start" => start_str, "end" => end_str}, socket) do
    with {s, _} <- Integer.parse(start_str),
         {e, _} <- Integer.parse(end_str) do
      n = length(socket.assigns.all_chart_data)
      s = max(1, min(s, n))
      e = max(s, min(e, n))

      socket =
        socket
        |> assign(:chart_year, nil)
        |> assign(:chart_start, s)
        |> assign(:chart_end, e)
        |> assign_chart_range()

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
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
          {Calendar.strftime(@current_snapshot.date, "%Y-%m-%d")}
        </div>
        <div class="terminal-nav-date-sub">
          {Calendar.strftime(@current_snapshot.date, "%A")}
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
    date = Date.to_string(snapshot.date)

    socket
    |> assign_snapshot(snapshot)
    |> push_patch(to: "/portfolio/#{date}", replace: true)
  end

  defp assign_snapshot(socket, nil) do
    socket
    |> assign(:current_snapshot, nil)
    |> assign(:positions, [])
    |> assign(:has_prev, false)
    |> assign(:has_next, false)
    |> assign(:total_value, Decimal.new("0"))
    |> assign(:total_pnl, Decimal.new("0"))
    |> assign(:snapshot_position, 0)
    |> assign(:total_snapshots, 0)
    |> assign(:all_chart_data, [])
    |> assign(:chart_data, [])
    |> assign(:chart_start, 1)
    |> assign(:chart_end, 0)
    |> assign(:chart_year, nil)
    |> assign(:chart_available_years, [])
    |> assign(:growth_stats, nil)
    |> assign(:dividend_year, Date.utc_today().year)
    |> assign(:dividend_total, Decimal.new("0"))
    |> assign(:projected_dividends, nil)
    |> assign(:recent_dividends, [])
    |> assign(:dividend_by_month, [])
    |> assign(:sparkline_values, [])
    |> assign(:fear_greed, nil)
    |> assign(:fx_exposure, [])
    |> assign(:cash_flow, [])
    |> assign(:investment_summary, nil)
    |> assign(:pnl_year, nil)
    |> assign(:pnl_show_all, false)
    |> assign(:is_reconstructed, false)
    |> assign(:missing_price_count, 0)
    |> assign(:pnl, %{
      total_pnl: Decimal.new("0"),
      total_trades: 0,
      symbol_count: 0,
      total_gains: Decimal.new("0"),
      total_losses: Decimal.new("0"),
      win_count: 0,
      loss_count: 0,
      top_winners: [],
      top_losers: [],
      all_grouped: [],
      available_years: [],
      has_unconverted: false
    })
  end

  defp assign_snapshot(socket, snapshot) do
    positions = snapshot.positions || []

    total_value =
      Enum.reduce(positions, Decimal.new("0"), fn p, acc ->
        fx = p.fx_rate || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(p.value || Decimal.new("0"), fx))
      end)

    total_pnl =
      Enum.reduce(positions, Decimal.new("0"), fn p, acc ->
        fx = p.fx_rate || Decimal.new("1")
        Decimal.add(acc, Decimal.mult(p.unrealized_pnl || Decimal.new("0"), fx))
      end)

    total_snapshots = Portfolio.count_snapshots()
    snapshot_position = Portfolio.get_snapshot_position(snapshot.date)

    all_chart_data = Portfolio.get_all_chart_data()
    sparkline_values = Enum.map(all_chart_data, & &1.value_float)

    year = snapshot.date.year

    chart_date_range =
      case all_chart_data do
        [first | _] -> {first.date, List.last(all_chart_data).date}
        _ -> nil
      end

    dividend_dashboard = Portfolio.compute_dividend_dashboard(year, chart_date_range)

    chart_available_years =
      all_chart_data
      |> Enum.map(& &1.date.year)
      |> Enum.uniq()
      |> Enum.sort()

    n = length(all_chart_data)

    socket
    |> assign(:current_snapshot, snapshot)
    |> assign(:positions, positions)
    |> assign(:has_prev, Portfolio.has_previous_snapshot?(snapshot.date))
    |> assign(:has_next, Portfolio.has_next_snapshot?(snapshot.date))
    |> assign(:total_value, total_value)
    |> assign(:total_pnl, total_pnl)
    |> assign(:snapshot_position, snapshot_position)
    |> assign(:total_snapshots, total_snapshots)
    |> assign(:all_chart_data, all_chart_data)
    |> assign(:chart_data, all_chart_data)
    |> assign(:chart_start, 1)
    |> assign(:chart_end, n)
    |> assign(:chart_year, nil)
    |> assign(:chart_available_years, chart_available_years)
    |> assign(:growth_stats, Portfolio.get_growth_stats(snapshot))
    |> assign(:dividend_year, year)
    |> assign(:dividend_total, dividend_dashboard.total_for_year)
    |> assign(:projected_dividends, dividend_dashboard.projected_annual)
    |> assign(:recent_dividends, dividend_dashboard.recent_with_income)
    |> assign(:dividend_by_month, dividend_dashboard.by_month_full_range)
    |> assign(:sparkline_values, sparkline_values)
    |> assign(:fear_greed, get_fear_greed_for_snapshot(socket, snapshot))
    |> assign(:fx_exposure, Portfolio.compute_fx_exposure(positions))
    |> assign(:cash_flow, dividend_dashboard.cash_flow_summary)
    |> assign(:pnl_year, nil)
    |> assign(:pnl_show_all, false)
    |> assign_freshness_and_source(snapshot, positions)
    |> assign_pnl_summary()
    |> assign_investment_summary()
  end

  defp assign_chart_range(socket) do
    all = socket.assigns.all_chart_data
    s = socket.assigns.chart_start
    e = socket.assigns.chart_end

    sliced = Enum.slice(all, (s - 1)..(e - 1)//1)

    growth_stats =
      case sliced do
        [first | _] ->
          last = List.last(sliced)
          first_val = Decimal.new("#{first.value_float}")
          last_val = Decimal.new("#{last.value_float}")
          abs_change = Decimal.sub(last_val, first_val)

          pct =
            if Decimal.compare(first_val, Decimal.new("0")) == :gt do
              first_val
              |> Decimal.div(Decimal.new("100"))
              |> then(&Decimal.div(abs_change, &1))
              |> Decimal.round(2)
            else
              Decimal.new("0")
            end

          %{
            first_date: first.date,
            latest_date: last.date,
            first_value: first_val,
            latest_value: last_val,
            absolute_change: abs_change,
            percent_change: pct
          }

        _ ->
          socket.assigns.growth_stats
      end

    socket
    |> assign(:chart_data, sliced)
    |> assign(:growth_stats, growth_stats)
  end

  defp assign_freshness_and_source(socket, snapshot, positions) do
    is_reconstructed = snapshot.data_quality == "reconstructed"
    missing = if is_reconstructed, do: Enum.count(positions, &is_nil(&1.price)), else: 0

    socket
    |> assign(:is_reconstructed, is_reconstructed)
    |> assign(:missing_price_count, missing)
  end

  defp assign_pnl_summary(socket) do
    opts = if socket.assigns.pnl_year, do: [year: socket.assigns.pnl_year], else: []
    assign(socket, :pnl, Portfolio.realized_pnl_summary(opts))
  end

  defp assign_investment_summary(socket) do
    summary = Portfolio.investment_summary()
    unrealized_pnl = socket.assigns.total_pnl
    current_value = socket.assigns.total_value
    total_return = Decimal.add(summary.net_profit, unrealized_pnl)

    investment_summary =
      summary
      |> Map.put(:unrealized_pnl, unrealized_pnl)
      |> Map.put(:current_value, current_value)
      |> Map.put(:total_return, total_return)

    assign(socket, :investment_summary, investment_summary)
  end
end
