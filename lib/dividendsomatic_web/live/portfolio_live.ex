defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view

  import DividendsomaticWeb.Helpers.FormatHelpers

  alias Dividendsomatic.{MarketSentiment, Portfolio}

  # F&G refresh interval: 30 minutes
  @fg_refresh_interval :timer.minutes(30)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:live_fear_greed, nil)
      |> assign_snapshot(nil)

    if connected?(socket), do: send(self(), :load_data)

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
  def handle_params(%{"date" => date_string}, _uri, %{assigns: %{loading: true}} = socket) do
    # Stash the requested date; :load_data will pick it up
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:noreply, assign(socket, :pending_date, date)}
      _ -> {:noreply, socket}
    end
  end

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

  def handle_event("navigate", %{"direction" => "back_week"}, socket) do
    {:noreply, navigate_by_date_offset(socket, -7)}
  end

  def handle_event("navigate", %{"direction" => "forward_week"}, socket) do
    {:noreply, navigate_by_date_offset(socket, 7)}
  end

  def handle_event("navigate", %{"direction" => "back_month"}, socket) do
    {:noreply, navigate_by_date_offset(socket, -30)}
  end

  def handle_event("navigate", %{"direction" => "forward_month"}, socket) do
    {:noreply, navigate_by_date_offset(socket, 30)}
  end

  def handle_event("navigate", %{"direction" => "back_year"}, socket) do
    {:noreply, navigate_by_date_offset(socket, -365)}
  end

  def handle_event("navigate", %{"direction" => "forward_year"}, socket) do
    {:noreply, navigate_by_date_offset(socket, 365)}
  end

  def handle_event("goto_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        snapshot = Portfolio.get_snapshot_nearest_date(date)
        {:noreply, navigate_to_snapshot(socket, snapshot)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("chart_range_preset", %{"preset" => preset}, socket) do
    all = socket.assigns.all_chart_data
    n = length(all)

    case preset do
      "ALL" ->
        socket =
          socket
          |> assign(:chart_year, nil)
          |> assign(:chart_start, 1)
          |> assign(:chart_end, n)
          |> assign_chart_range()

        {:noreply, socket}

      "YTD" ->
        year_start = Date.new!(Date.utc_today().year, 1, 1)
        {:noreply, apply_chart_date_offset(socket, all, n, year_start)}

      offset_preset ->
        days =
          case offset_preset do
            "1M" -> 30
            "3M" -> 91
            "6M" -> 182
            "1Y" -> 365
            _ -> n
          end

        target = Date.add(Date.utc_today(), -days)
        {:noreply, apply_chart_date_offset(socket, all, n, target)}
    end
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

  def handle_event("switch_tab", _params, %{assigns: %{loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket =
      socket
      |> assign(:active_tab, tab)
      |> lazy_load_tab_data(tab)

    {:noreply, socket}
  end

  def handle_event("toggle_waterfall", _params, socket) do
    if socket.assigns.show_waterfall do
      {:noreply, assign(socket, show_waterfall: false, waterfall_data: [])}
    else
      {:noreply, assign(socket, show_waterfall: true, waterfall_data: Portfolio.waterfall_data())}
    end
  end

  @impl true
  def handle_info(:load_data, socket) do
    snapshot =
      case socket.assigns[:pending_date] do
        nil -> Portfolio.get_latest_snapshot()
        date -> Portfolio.get_snapshot_by_date(date) || Portfolio.get_latest_snapshot()
      end

    live_fg = get_fear_greed_live()

    Process.send_after(self(), :refresh_fear_greed, @fg_refresh_interval)

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:live_fear_greed, live_fg)
      |> assign_snapshot(snapshot)

    {:noreply, socket}
  end

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

  attr :title, :string, required: true
  attr :date, :any, required: true

  defp tab_panel_header(assigns) do
    ~H"""
    <div class="terminal-panel-header">
      <h2>{@title}</h2>
      <span class="terminal-panel-date">{Calendar.strftime(@date, "%Y-%m-%d")}</span>
    </div>
    """
  end

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

  def about_panel(assigns) do
    ~H"""
    <div id="panel-about" class="animate-fade-in" role="tabpanel" aria-labelledby="tab-about">
      <div class="terminal-card p-[var(--space-sm)]">
        <div style="font-family: var(--font-display); font-size: 1.25rem; font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; margin-bottom: var(--space-xs);">
          dividends-o-matic
        </div>
        <p style="font-family: var(--font-mono); font-size: 0.75rem; color: var(--terminal-muted); margin-bottom: var(--space-sm); line-height: 1.6;">
          Portfolio and dividend tracking dashboard. Data is based on combined real data for testing purposes.
        </p>
        <ul style="font-family: var(--font-mono); font-size: 0.6875rem; color: var(--terminal-dim); line-height: 1.8; list-style: none; padding: 0; margin-bottom: var(--space-sm);">
          <li>&#x25B8; Multi-format CSV import with unified portfolio history</li>
          <li>&#x25B8; Dividend analytics, projections, and per-symbol breakdown</li>
          <li>&#x25B8; Market data with multi-provider fallback chains</li>
        </ul>
        <div class="flex items-center gap-[var(--space-xs)]">
          <a
            href="https://github.com/jhalmu/dividendsomatic/issues"
            target="_blank"
            rel="noopener noreferrer"
            class="btn btn-sm btn-outline"
          >
            GitHub Issues
          </a>
          <a
            href="https://bsky.app/profile/jhalmu.bsky.social"
            target="_blank"
            rel="noopener noreferrer"
            class="btn btn-sm btn-outline"
          >
            Bluesky
          </a>
        </div>
      </div>
    </div>
    """
  end

  defp lazy_load_tab_data(socket, "overview") do
    if socket.assigns[:overview_loaded] do
      socket
    else
      socket
      |> assign(:overview_loaded, true)
      |> assign(:fx_exposure, Portfolio.compute_fx_exposure(socket.assigns.positions))
      |> assign(:concentration, Portfolio.compute_concentration(socket.assigns.positions))
    end
  end

  defp lazy_load_tab_data(socket, "holdings") do
    if socket.assigns[:holdings_loaded] do
      socket
    else
      socket
      |> assign(:holdings_loaded, true)
      |> assign(:fx_exposure, Portfolio.compute_fx_exposure(socket.assigns.positions))
      |> assign(:concentration, Portfolio.compute_concentration(socket.assigns.positions))
      |> assign(:sector_breakdown, Portfolio.compute_sector_breakdown(socket.assigns.positions))
    end
  end

  defp lazy_load_tab_data(socket, "income") do
    if socket.assigns[:income_loaded] do
      socket
    else
      socket
      |> assign(:income_loaded, true)
      |> assign(:margin_interest, Portfolio.total_actual_margin_interest())
    end
  end

  defp lazy_load_tab_data(socket, "summary") do
    if socket.assigns[:summary_loaded] do
      socket
    else
      socket
      |> assign(:summary_loaded, true)
      |> assign(:fx_exposure, Portfolio.compute_fx_exposure(socket.assigns.positions))
      |> assign_pnl_summary()
      |> assign_investment_summary()
      |> assign_margin_equity()
    end
  end

  defp lazy_load_tab_data(socket, _tab), do: socket

  defp navigate_by_date_offset(socket, days) do
    if socket.assigns.current_snapshot do
      target = Date.add(socket.assigns.current_snapshot.date, days)
      snapshot = Portfolio.get_snapshot_nearest_date(target)
      navigate_to_snapshot(socket, snapshot)
    else
      socket
    end
  end

  defp apply_chart_date_offset(socket, all, n, target_date) do
    start_idx =
      all
      |> Enum.with_index(1)
      |> Enum.find(fn {point, _idx} -> Date.compare(point.date, target_date) != :lt end)
      |> case do
        {_point, idx} -> idx
        nil -> 1
      end

    socket
    |> assign(:chart_year, nil)
    |> assign(:chart_start, start_idx)
    |> assign(:chart_end, n)
    |> assign_chart_range()
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
    |> assign(:costs_this_year, Decimal.new("0"))
    |> assign(:costs_summary, %{by_type: %{}, total: Decimal.new("0"), count: 0})
    |> assign(:realized_pnl_total, Decimal.new("0"))
    |> assign(:total_return, Decimal.new("0"))
    |> assign(:fear_greed, nil)
    |> assign(:fx_exposure, [])
    |> assign(:investment_summary, nil)
    |> assign(:show_waterfall, false)
    |> assign(:waterfall_data, [])
    |> assign(:pnl_year, nil)
    |> assign(:pnl_show_all, false)
    |> assign(:active_tab, "overview")
    |> assign(:per_symbol_dividends, %{})
    |> assign(:dividend_summary_totals, %{})
    |> assign(:margin_equity, nil)
    |> assign(:concentration, %{
      top_1: Decimal.new("0"),
      top_3: Decimal.new("0"),
      hhi: Decimal.new("0"),
      count: 0
    })
    |> assign(:sector_breakdown, [])
    |> assign(:margin_interest, Decimal.new("0"))
    |> assign(:overview_loaded, false)
    |> assign(:holdings_loaded, false)
    |> assign(:income_loaded, false)
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

    all_chart_data = Portfolio.get_all_chart_data()
    total_snapshots = length(all_chart_data)

    snapshot_position =
      Enum.count(all_chart_data, &(Date.compare(&1.date, snapshot.date) != :gt))

    sparkline_values = Enum.map(all_chart_data, & &1.value_float)

    year = snapshot.date.year

    chart_date_range =
      case all_chart_data do
        [first | _] -> {first.date, List.last(all_chart_data).date}
        _ -> nil
      end

    dividend_dashboard = Portfolio.compute_dividend_dashboard(year, chart_date_range, positions)

    chart_available_years =
      all_chart_data
      |> Enum.map(& &1.date.year)
      |> Enum.uniq()
      |> Enum.sort()

    n = length(all_chart_data)

    socket
    |> assign(:current_snapshot, snapshot)
    |> assign(:positions, positions)
    |> assign(:has_prev, snapshot_position > 1)
    |> assign(:has_next, snapshot_position < total_snapshots)
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
    |> assign(:per_symbol_dividends, dividend_dashboard.per_symbol)
    |> assign(
      :dividend_summary_totals,
      compute_dividend_summary_totals(dividend_dashboard.per_symbol)
    )
    |> assign(:sparkline_values, sparkline_values)
    |> assign(:costs_this_year, Portfolio.total_costs_for_year(year))
    |> assign(:costs_summary, Portfolio.costs_summary())
    |> assign_realized_and_total_return(year, dividend_dashboard.total_for_year)
    |> assign(:fear_greed, get_fear_greed_for_snapshot(socket, snapshot))
    |> assign(:fx_exposure, [])
    |> assign(:show_waterfall, false)
    |> assign(:waterfall_data, [])
    |> assign(:pnl_year, nil)
    |> assign(:pnl_show_all, false)
    |> assign(:pnl, %{winners: [], losers: [], total_realized: Decimal.new("0")})
    |> assign(:investment_summary, nil)
    |> assign(:summary_loaded, false)
    |> assign(:overview_loaded, false)
    |> assign(:holdings_loaded, false)
    |> assign(:income_loaded, false)
    |> assign(:margin_equity, nil)
    |> assign(:concentration, %{
      top_1: Decimal.new("0"),
      top_3: Decimal.new("0"),
      hhi: Decimal.new("0"),
      count: 0
    })
    |> assign(:sector_breakdown, [])
    |> assign(:margin_interest, Decimal.new("0"))
    |> assign_new(:active_tab, fn -> "overview" end)
    |> maybe_load_tab_data()
  end

  defp maybe_load_tab_data(%{assigns: %{active_tab: "overview"}} = socket) do
    socket
    |> assign(:overview_loaded, true)
    |> assign(:fx_exposure, Portfolio.compute_fx_exposure(socket.assigns.positions))
    |> assign(:concentration, Portfolio.compute_concentration(socket.assigns.positions))
  end

  defp maybe_load_tab_data(%{assigns: %{active_tab: "holdings"}} = socket) do
    socket
    |> assign(:holdings_loaded, true)
    |> assign(:fx_exposure, Portfolio.compute_fx_exposure(socket.assigns.positions))
    |> assign(:concentration, Portfolio.compute_concentration(socket.assigns.positions))
    |> assign(:sector_breakdown, Portfolio.compute_sector_breakdown(socket.assigns.positions))
  end

  defp maybe_load_tab_data(%{assigns: %{active_tab: "income"}} = socket) do
    socket
    |> assign(:income_loaded, true)
    |> assign(:margin_interest, Portfolio.total_actual_margin_interest())
  end

  defp maybe_load_tab_data(%{assigns: %{active_tab: "summary"}} = socket) do
    socket
    |> assign(:summary_loaded, true)
    |> assign(:fx_exposure, Portfolio.compute_fx_exposure(socket.assigns.positions))
    |> assign_pnl_summary()
    |> assign_investment_summary()
    |> assign_margin_equity()
  end

  defp maybe_load_tab_data(socket), do: socket

  defp compute_dividend_summary_totals(per_symbol) when map_size(per_symbol) == 0, do: %{}

  defp compute_dividend_summary_totals(per_symbol) do
    zero = Decimal.new("0")

    monthly_payers =
      Enum.filter(per_symbol, fn {_sym, data} -> data.payment_frequency == :monthly end)

    {monthly_sum, proj_sum, remaining_sum} =
      Enum.reduce(per_symbol, {zero, zero, zero}, fn {_sym, data},
                                                     {monthly_acc, proj_acc, rem_acc} ->
        {
          Decimal.add(monthly_acc, data.est_monthly || zero),
          Decimal.add(proj_acc, data.projected_annual || zero),
          Decimal.add(rem_acc, data.est_remaining || zero)
        }
      end)

    {mp_monthly, mp_annual, mp_remaining} =
      Enum.reduce(monthly_payers, {zero, zero, zero}, fn {_sym, data}, {m_acc, a_acc, r_acc} ->
        {
          Decimal.add(m_acc, data.est_monthly || zero),
          Decimal.add(a_acc, data.projected_annual || zero),
          Decimal.add(r_acc, data.est_remaining || zero)
        }
      end)

    %{
      est_monthly: monthly_sum,
      projected_annual: proj_sum,
      est_remaining: remaining_sum,
      monthly_payers_est_monthly: mp_monthly,
      monthly_payers_annual: mp_annual,
      monthly_payers_remaining: mp_remaining,
      monthly_payers_count: length(monthly_payers)
    }
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

    chart_json = serialize_portfolio_chart(sliced, socket.assigns.current_snapshot.date)

    socket
    |> assign(:chart_data, sliced)
    |> assign(:growth_stats, growth_stats)
    |> push_event("update-chart-portfolio-apex-chart", %{
      series: chart_json.series,
      options: %{annotations: chart_json.annotations}
    })
  end

  defp assign_realized_and_total_return(socket, year, dividend_total) do
    realized = Portfolio.total_realized_pnl(year)
    total_return = Decimal.add(realized, dividend_total)

    socket
    |> assign(:realized_pnl_total, realized)
    |> assign(:total_return, total_return)
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

  defp assign_margin_equity(socket) do
    assign(socket, :margin_equity, Portfolio.margin_equity_summary())
  end

  # --- ApexCharts Data Serialization ---

  @doc false
  def serialize_portfolio_chart(chart_data, current_date) do
    value_series =
      Enum.map(chart_data, fn point ->
        ts = date_to_unix_ms(point.date)
        [ts, Float.round(point.value_float, 0)]
      end)

    annotations = %{
      xaxis: [
        %{
          x: date_to_unix_ms(current_date),
          strokeDashArray: 3,
          borderColor: "#D8DEE9",
          opacity: 0.25,
          label: %{
            text: "Current",
            style: %{
              color: "#D8DEE9",
              background: "rgba(14, 18, 27, 0.9)",
              fontSize: "10px",
              fontFamily: "IBM Plex Mono"
            }
          }
        }
      ]
    }

    %{
      series: [
        %{name: "Portfolio Value", type: "area", data: value_series}
      ],
      annotations: annotations
    }
  end

  @doc false
  def serialize_dividend_chart(dividend_by_month) do
    categories = Enum.map(dividend_by_month, fn m -> m.month end)

    monthly_data =
      Enum.map(dividend_by_month, fn m ->
        Float.round(Decimal.to_float(m.total), 2)
      end)

    # Compute cumulative from monthly totals
    cumulative_data =
      dividend_by_month
      |> Enum.scan(0.0, fn m, acc -> Float.round(acc + Decimal.to_float(m.total), 2) end)

    %{
      series: [
        %{name: "Monthly", type: "bar", data: monthly_data},
        %{name: "Cumulative", type: "line", data: cumulative_data}
      ],
      categories: categories
    }
  end

  @doc false
  def build_portfolio_apex_config(%{series: series, annotations: annotations}) do
    %{
      chart: %{
        type: "area",
        height: 320,
        toolbar: %{show: false},
        zoom: %{enabled: true},
        fontFamily: "'IBM Plex Mono', monospace",
        background: "transparent",
        animations: %{
          enabled: true,
          easing: "easeinout",
          speed: 600,
          dynamicAnimation: %{enabled: true, speed: 350}
        }
      },
      series: series,
      stroke: %{
        width: 1.5,
        curve: "smooth"
      },
      colors: ["#5EADF7"],
      fill: %{
        type: "gradient",
        gradient: %{
          shadeIntensity: 1,
          opacityFrom: 0.08,
          opacityTo: 0.01,
          stops: [0, 85, 100]
        }
      },
      xaxis: %{
        type: "datetime",
        labels: %{
          style: %{colors: "#4C5772", fontSize: "10px"}
        },
        axisBorder: %{show: false},
        axisTicks: %{show: false}
      },
      yaxis: %{
        labels: %{
          style: %{colors: "#4C5772", fontSize: "10px"}
        }
      },
      grid: %{
        borderColor: "rgba(76, 87, 114, 0.12)",
        strokeDashArray: 3,
        xaxis: %{lines: %{show: false}}
      },
      tooltip: %{
        theme: "dark",
        shared: true,
        intersect: false,
        x: %{format: "dd MMM yyyy"},
        style: %{fontSize: "12px"}
      },
      legend: %{show: false},
      annotations: annotations,
      dataLabels: %{enabled: false}
    }
  end

  @doc false
  def build_dividend_apex_config(%{series: series, categories: categories}) do
    %{
      chart: %{
        type: "bar",
        height: 260,
        toolbar: %{show: false},
        fontFamily: "'IBM Plex Mono', monospace",
        background: "transparent",
        animations: %{
          enabled: true,
          easing: "easeinout",
          speed: 600
        }
      },
      series: series,
      plotOptions: %{
        bar: %{
          borderRadius: 4,
          borderRadiusApplication: "end",
          columnWidth: "60%"
        }
      },
      stroke: %{
        width: [0, 2.5],
        curve: "smooth"
      },
      colors: ["#FBBF24", "#F59E0B"],
      fill: %{opacity: [0.85, 1]},
      xaxis: %{
        categories: categories,
        labels: %{
          style: %{colors: "#4C5772", fontSize: "10px"},
          rotate: -45,
          rotateAlways: false
        },
        axisBorder: %{show: false},
        axisTicks: %{show: false}
      },
      yaxis: [
        %{
          title: %{text: ""},
          labels: %{
            style: %{colors: "#4C5772", fontSize: "10px"}
          }
        },
        %{
          opposite: true,
          title: %{text: ""},
          labels: %{
            style: %{colors: "#4C5772", fontSize: "10px"}
          }
        }
      ],
      grid: %{
        borderColor: "rgba(76, 87, 114, 0.12)",
        strokeDashArray: 3,
        xaxis: %{lines: %{show: false}}
      },
      tooltip: %{
        theme: "dark",
        shared: true,
        intersect: false,
        style: %{fontSize: "12px"}
      },
      legend: %{show: false},
      dataLabels: %{enabled: false}
    }
  end

  @doc false
  def build_fx_donut_config(fx_data, _id_suffix \\ "") do
    labels = Enum.map(fx_data, & &1.currency)
    series = Enum.map(fx_data, fn fx -> Decimal.to_float(fx.pct) end)

    colors = [
      "#5EADF7",
      "#FBBF24",
      "#34D399",
      "#F87171",
      "#A78BFA",
      "#FB923C"
    ]

    %{
      chart: %{
        type: "donut",
        height: 220,
        background: "transparent",
        fontFamily: "'IBM Plex Mono', monospace"
      },
      series: series,
      labels: labels,
      colors: Enum.take(colors, length(labels)),
      stroke: %{width: 1, colors: ["var(--terminal-bg)"]},
      legend: %{
        position: "bottom",
        labels: %{colors: "#7E8BA3"},
        fontSize: "11px",
        fontFamily: "'IBM Plex Mono', monospace"
      },
      dataLabels: %{
        enabled: true,
        formatter: "PERCENT_FORMATTER",
        style: %{fontSize: "11px", fontFamily: "'IBM Plex Mono', monospace"}
      },
      tooltip: %{
        theme: "dark",
        style: %{fontSize: "12px"}
      },
      plotOptions: %{
        pie: %{
          donut: %{
            size: "60%",
            labels: %{show: false}
          }
        }
      }
    }
  end

  defp format_cost_type("commission"), do: "Commission"
  defp format_cost_type("withholding_tax"), do: "Withholding Tax"
  defp format_cost_type("foreign_tax"), do: "Foreign Tax"
  defp format_cost_type("loan_interest"), do: "Loan Interest"
  defp format_cost_type("capital_interest"), do: "Capital Interest"
  defp format_cost_type(other), do: String.capitalize(other)

  defp fear_greed_color(nil), do: "yellow"

  defp fear_greed_color(data) do
    value = data["value"] || 50

    cond do
      value <= 25 -> "red"
      value <= 45 -> "orange"
      value <= 55 -> "yellow"
      value <= 75 -> "emerald"
      true -> "green"
    end
  end

  defp date_to_unix_ms(date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.to_unix(:millisecond)
  end
end
