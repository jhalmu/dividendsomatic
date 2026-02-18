defmodule DividendsomaticWeb.StockLive do
  use DividendsomaticWeb, :live_view

  import DividendsomaticWeb.Helpers.FormatHelpers

  alias Dividendsomatic.{Portfolio, Stocks}

  @impl true
  def mount(%{"symbol" => symbol}, _session, socket) do
    holdings = Portfolio.list_holdings_by_symbol(symbol)
    all_dividends = Portfolio.list_dividends_by_symbol(symbol)
    company_profile = get_company_profile(symbol)
    quote_data = get_stock_quote(symbol)
    financial_metrics = get_financial_metrics(symbol)
    isin = get_isin(holdings)

    company_note =
      if isin, do: Stocks.get_or_init_company_note(isin, %{symbol: symbol}), else: nil

    holding_stats = compute_holding_stats(holdings)

    # Filter dividends to ownership period only
    owned_dividends = filter_dividends_to_ownership(all_dividends, holdings)
    dividends_with_income = compute_dividends_with_income(owned_dividends, holdings)
    total_dividend_income = sum_dividend_income(dividends_with_income)

    # Dividend analytics uses ALL dividends (not ownership-filtered)
    # so TTM, yield, frequency reflect the stock's actual dividend pattern
    all_dividends_with_income = compute_dividends_with_income(all_dividends, holdings)

    dividend_analytics =
      compute_dividend_analytics(all_dividends_with_income, quote_data, holding_stats)

    # Dividend payback progress
    payback_data =
      compute_payback_data(holdings, dividends_with_income, holding_stats, dividend_analytics)

    # Price chart data from holdings history (oldest first)
    price_chart_data = build_price_chart_data(holdings)

    sold_for_symbol = Portfolio.list_sold_positions_by_symbol(symbol)

    socket =
      socket
      |> assign(:symbol, symbol)
      |> assign(:holdings_history, holdings)
      |> assign(:dividends_with_income, dividends_with_income)
      |> assign(:total_dividend_income, total_dividend_income)
      |> assign(:dividend_analytics, dividend_analytics)
      |> assign(:company_profile, company_profile)
      |> assign(:quote_data, quote_data)
      |> assign(:financial_metrics, financial_metrics)
      |> assign(:isin, isin)
      |> assign(:company_note, company_note)
      |> assign(:note_saved, false)
      |> assign(:holding_stats, holding_stats)
      |> assign(:price_chart_data, price_chart_data)
      |> assign(:payback_data, payback_data)
      |> assign(:sold_for_symbol, sold_for_symbol)
      |> assign(:external_links, build_external_links(symbol, holdings, company_profile))

    {:ok, socket}
  end

  # --- Event Handlers ---

  @impl true
  def handle_event("save_thesis", %{"value" => value}, socket) do
    save_note(socket, :thesis, value)
  end

  @impl true
  def handle_event("save_notes", %{"value" => value}, socket) do
    save_note(socket, :notes_markdown, value)
  end

  defp save_note(socket, field, value) do
    isin = socket.assigns.isin

    if isin do
      attrs =
        Map.merge(
          %{isin: isin, symbol: socket.assigns.symbol},
          %{field => value}
        )

      case Stocks.upsert_company_note(attrs) do
        {:ok, note} ->
          Process.send_after(self(), :clear_note_saved, 2000)
          {:noreply, socket |> assign(:company_note, note) |> assign(:note_saved, true)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:clear_note_saved, socket) do
    {:noreply, assign(socket, :note_saved, false)}
  end

  # --- Note Helpers ---

  defp note_thesis(nil), do: ""
  defp note_thesis(%{thesis: nil}), do: ""
  defp note_thesis(%{thesis: thesis}), do: thesis

  defp note_markdown(nil), do: ""
  defp note_markdown(%{notes_markdown: nil}), do: ""
  defp note_markdown(%{notes_markdown: notes}), do: notes

  defp thesis_placeholder(%{asset_type: "etf"}),
    do: "Fund composition, asset allocation target, dividend strategy, rebalancing rules"

  defp thesis_placeholder(%{asset_type: "reit"}),
    do: "Dividend frequency, occupancy rate, management quality, leverage"

  defp thesis_placeholder(%{asset_type: "bdc"}),
    do: "Leverage, interest coverage, distribution sustainability"

  defp thesis_placeholder(_),
    do: "Why do you hold this? Growth potential, dividend yield, competitive advantage?"

  # --- Dividend Analytics ---

  defp compute_dividend_analytics([], _quote_data, _holding_stats), do: nil

  defp compute_dividend_analytics(dividends_with_income, quote_data, holding_stats) do
    frequency = detect_dividend_frequency(dividends_with_income)
    annual_per_share = compute_annual_dividend_per_share(dividends_with_income)
    yield = compute_dividend_yield(annual_per_share, quote_data)
    growth_rate = compute_dividend_growth_rate(dividends_with_income)
    yield_on_cost = compute_yield_on_cost(annual_per_share, holding_stats)

    %{
      frequency: frequency,
      annual_per_share: annual_per_share,
      yield: yield,
      yield_on_cost: yield_on_cost,
      growth_rate: growth_rate
    }
  end

  @doc false
  def detect_dividend_frequency(dividends_with_income) when length(dividends_with_income) < 2,
    do: "unknown"

  def detect_dividend_frequency(dividends_with_income) do
    dates =
      dividends_with_income
      |> Enum.map(& &1.dividend.ex_date)
      |> Enum.sort(Date)

    gaps =
      dates
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> Date.diff(b, a) end)

    avg_gap = Enum.sum(gaps) / length(gaps)

    cond do
      avg_gap < 50 -> "monthly"
      avg_gap < 120 -> "quarterly"
      avg_gap < 220 -> "semi-annual"
      avg_gap < 420 -> "annual"
      true -> "irregular"
    end
  end

  defp compute_annual_dividend_per_share(dividends_with_income) do
    # Use last 12 months of dividends to compute trailing annual per-share
    cutoff = Date.add(Date.utc_today(), -365)

    recent =
      Enum.filter(dividends_with_income, fn entry ->
        Date.compare(entry.dividend.ex_date, cutoff) != :lt
      end)

    if recent == [] do
      Decimal.new("0")
    else
      Enum.reduce(recent, Decimal.new("0"), fn entry, acc ->
        Decimal.add(acc, per_share_amount(entry.dividend))
      end)
    end
  end

  defp compute_dividend_yield(_annual_per_share, nil), do: nil

  defp compute_dividend_yield(annual_per_share, quote_data) do
    price = quote_data.current_price

    if price && Decimal.compare(price, Decimal.new("0")) == :gt do
      annual_per_share
      |> Decimal.div(price)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      nil
    end
  end

  defp compute_yield_on_cost(_annual_per_share, nil), do: nil

  defp compute_yield_on_cost(annual_per_share, holding_stats) do
    avg_cost = holding_stats.avg_cost

    if avg_cost && Decimal.compare(avg_cost, Decimal.new("0")) == :gt do
      annual_per_share
      |> Decimal.div(avg_cost)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      nil
    end
  end

  defp compute_dividend_growth_rate(dividends_with_income) when length(dividends_with_income) < 2,
    do: nil

  defp compute_dividend_growth_rate(dividends_with_income) do
    by_year =
      dividends_with_income
      |> Enum.group_by(fn entry -> entry.dividend.ex_date.year end)
      |> Enum.map(fn {year, entries} ->
        total =
          Enum.reduce(entries, Decimal.new("0"), fn e, acc ->
            Decimal.add(acc, per_share_amount(e.dividend))
          end)

        {year, total}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    compute_yoy_growth(by_year)
  end

  defp compute_yoy_growth(by_year) when length(by_year) < 2, do: nil

  defp compute_yoy_growth(by_year) do
    {_prev_year, prev_total} = Enum.at(by_year, -2)
    {_curr_year, curr_total} = Enum.at(by_year, -1)

    if Decimal.compare(prev_total, Decimal.new("0")) == :gt do
      curr_total
      |> Decimal.sub(prev_total)
      |> Decimal.div(prev_total)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(1)
    else
      nil
    end
  end

  # --- Dividend Payback ---

  @doc false
  def compute_payback_data([], _divs, _stats, _analytics), do: nil
  def compute_payback_data(_holdings, _divs, nil, _analytics), do: nil

  def compute_payback_data(holdings, dividends_with_income, holding_stats, dividend_analytics) do
    periods = holding_stats.ownership_periods
    total_invested = holding_stats.total_invested

    period_breakdowns =
      Enum.map(periods, fn period ->
        compute_period_payback(period, holdings, dividends_with_income)
      end)

    total_income =
      Enum.reduce(period_breakdowns, Decimal.new("0"), fn pb, acc ->
        Decimal.add(acc, pb.income)
      end)

    overall_pct =
      if Decimal.compare(total_invested, Decimal.new("0")) == :gt do
        total_income
        |> Decimal.div(total_invested)
        |> Decimal.mult(Decimal.new("100"))
        |> Decimal.round(1)
      else
        Decimal.new("0")
      end

    # Prefer yield_on_cost from analytics (TTM-based, reliable) over
    # annualized partial-year rates which inflate on short holding periods
    {weighted_rate, rate_source} = pick_best_rate(dividend_analytics)

    rule72 =
      if weighted_rate > 0,
        do: compute_rule72(weighted_rate),
        else: nil

    %{
      overall_pct: overall_pct,
      total_income: total_income,
      total_invested: total_invested,
      weighted_rate: weighted_rate,
      rate_source: rate_source,
      rule72: rule72,
      periods: period_breakdowns
    }
  end

  defp pick_best_rate(%{yield_on_cost: yoc}) when not is_nil(yoc) do
    val = Decimal.to_float(yoc)
    if val > 0, do: {Float.round(val, 2), "yield on cost"}, else: {0.0, nil}
  end

  defp pick_best_rate(%{yield: yield}) when not is_nil(yield) do
    val = Decimal.to_float(yield)
    if val > 0, do: {Float.round(val, 2), "current yield"}, else: {0.0, nil}
  end

  defp pick_best_rate(_), do: {0.0, nil}

  defp compute_period_payback(period, holdings, dividends_with_income) do
    period_holdings = filter_holdings_to_period(holdings, period)
    period_divs = filter_dividends_to_period(dividends_with_income, period)

    cost_basis = compute_period_cost_basis(period_holdings)

    income =
      Enum.reduce(period_divs, Decimal.new("0"), fn entry, acc ->
        Decimal.add(acc, entry.income)
      end)

    pct =
      if Decimal.compare(cost_basis, Decimal.new("0")) == :gt do
        income
        |> Decimal.div(cost_basis)
        |> Decimal.mult(Decimal.new("100"))
        |> Decimal.round(1)
      else
        Decimal.new("0")
      end

    %{
      start_date: period.start_date,
      end_date: period.end_date,
      days: period.days,
      cost_basis: cost_basis,
      income: income,
      pct: pct
    }
  end

  defp filter_holdings_to_period(holdings, period) do
    Enum.filter(holdings, fn h ->
      Date.compare(h.date, period.start_date) != :lt &&
        Date.compare(h.date, period.end_date) != :gt
    end)
  end

  defp filter_dividends_to_period(dividends_with_income, period) do
    Enum.filter(dividends_with_income, fn entry ->
      Date.compare(entry.dividend.ex_date, period.start_date) != :lt &&
        Date.compare(entry.dividend.ex_date, period.end_date) != :gt
    end)
  end

  defp compute_period_cost_basis([]), do: Decimal.new("0")

  defp compute_period_cost_basis(holdings) do
    # Use the latest holding in the period for cost basis
    latest = hd(holdings)
    cost = latest.cost_basis || Decimal.new("0")
    fx = latest.fx_rate || Decimal.new("1")
    Decimal.mult(cost, fx)
  end

  defp remaining_payback_years(%{overall_pct: pct, weighted_rate: rate}) when rate > 0 do
    recovered = Decimal.to_float(pct) / 100.0
    remaining_fraction = max(1.0 - recovered, 0.0)

    if remaining_fraction <= 0 do
      "0y"
    else
      # Years = remaining_fraction * (100 / rate)
      years = remaining_fraction * (100.0 / rate)
      format_years(years)
    end
  end

  defp remaining_payback_years(_), do: ""

  defp format_years(years) when years < 1, do: "#{round(years * 12)}m"
  defp format_years(years), do: "#{Float.round(years, 1)}y"

  # --- Rule of 72 ---

  @doc false
  def compute_rule72(rate) when is_number(rate) and rate > 0 do
    # Exact formula: ln(2) / ln(1 + r/100)
    exact_years = :math.log(2) / :math.log(1 + rate / 100)
    # Rule of 72 approximation
    approx_years = 72 / rate

    # Build doubling milestones (1x, 2x, 4x, 8x, 16x)
    milestones =
      for n <- 0..4 do
        multiplier = :math.pow(2, n)
        years = exact_years * n
        %{multiplier: round(multiplier), years: Float.round(years, 1)}
      end

    %{
      rate: Float.round(rate + 0.0, 2),
      exact_years: Float.round(exact_years, 1),
      approx_years: Float.round(approx_years, 1),
      milestones: milestones
    }
  end

  def compute_rule72(_), do: compute_rule72(8.0)

  # --- Dividend Chart ---

  defp render_dividend_chart(dividends_with_income) when length(dividends_with_income) < 2 do
    Phoenix.HTML.raw("")
  end

  defp render_dividend_chart(dividends_with_income) do
    w = 900
    ml = 62
    mr = 20
    pw = w - ml - mr
    mt = 20
    main_h = 140
    chart_bottom = mt + main_h
    total_h = chart_bottom + 25

    # Sort chronologically
    sorted =
      dividends_with_income
      |> Enum.sort_by(& &1.dividend.ex_date, Date)

    n = length(sorted)
    x_fn = fn idx -> ml + idx / max(n - 1, 1) * pw end
    bar_w = max(pw / max(n, 1) * 0.7, 4)

    # Per-share amounts for bar heights
    amounts =
      Enum.map(sorted, fn e -> Decimal.to_float(per_share_amount(e.dividend)) end)

    a_max = Enum.max(amounts) * 1.15
    a_max = max(a_max, 0.01)

    # Cumulative income for line
    cumulative =
      sorted
      |> Enum.scan(Decimal.new("0"), fn e, acc -> Decimal.add(acc, e.income) end)
      |> Enum.map(&Decimal.to_float/1)

    c_max = Enum.max(cumulative) * 1.15
    c_max = max(c_max, 0.01)
    c_fn = fn v -> mt + main_h - v / c_max * main_h end

    # Bars (per-share amount)
    bars =
      sorted
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {e, i} ->
        amt = Decimal.to_float(per_share_amount(e.dividend))
        cx = x_fn.(i)
        bx = cx - bar_w / 2
        bar_h = max(amt / a_max * main_h, 1)
        y = chart_bottom - bar_h

        ~s[<rect x="#{r(bx)}" y="#{r(y)}" width="#{r(bar_w)}" height="#{r(bar_h)}" fill="#10b981" fill-opacity="0.6" rx="1"/>]
      end)

    # Cumulative income line
    line_d =
      cumulative
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {v, i} ->
        x = r(x_fn.(i))
        y = r(c_fn.(v))
        if i == 0, do: "M#{x} #{y}", else: "L#{x} #{y}"
      end)

    line =
      ~s[<path d="#{line_d}" fill="none" stroke="#f97316" stroke-width="1.5" stroke-linejoin="round"/>]

    # Dots on cumulative line
    dots =
      cumulative
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {v, i} ->
        x = r(x_fn.(i))
        y = r(c_fn.(v))
        ~s[<circle cx="#{x}" cy="#{y}" r="2" fill="#f97316"/>]
      end)

    # X labels
    x_labels = svg_div_x_labels(sorted, x_fn, chart_bottom + 15, n)

    # Y labels (per-share amounts on left)
    y_labels =
      for i <- 0..3 do
        gy = r(mt + main_h - i / 3 * main_h + 3)
        val = a_max * i / 3

        ~s[<text x="#{ml - 8}" y="#{gy}" fill="#475569" font-size="8" text-anchor="end">#{format_chart_val(val)}</text>]
      end
      |> Enum.join("\n")

    # Grid
    grid =
      for i <- 0..3 do
        gy = r(mt + main_h - i / 3 * main_h)

        ~s[<line x1="#{ml}" y1="#{gy}" x2="#{ml + pw}" y2="#{gy}" stroke="#1e293b" stroke-width="1"/>]
      end
      |> Enum.join("\n")

    # Annotation: last cumulative value
    last_cum = List.last(cumulative)
    last_x = r(x_fn.(n - 1))
    last_y = r(c_fn.(last_cum))

    {label_x, anchor} =
      if last_x > w - 80, do: {last_x - 8, "end"}, else: {last_x + 8, "start"}

    annotation =
      ~s[<text x="#{label_x}" y="#{last_y - 6}" fill="#f97316" font-size="8" font-weight="600" text-anchor="#{anchor}">#{format_chart_val(last_cum)}</text>]

    Phoenix.HTML.raw("""
    <svg width="100%" viewBox="0 0 #{w} #{round(total_h)}" xmlns="http://www.w3.org/2000/svg" style="font-family: 'JetBrains Mono', monospace;">
      #{grid}
      #{bars}
      #{line}
      #{dots}
      #{x_labels}
      #{y_labels}
      #{annotation}
    </svg>
    """)
  end

  defp svg_div_x_labels(sorted, x_fn, label_y, n) do
    count = min(6, n)
    step = max(div(n - 1, count), 1)

    for i <- 0..count, idx = min(i * step, n - 1), reduce: [] do
      acc ->
        entry = Enum.at(sorted, idx)
        lx = r(x_fn.(idx))
        date_str = Calendar.strftime(entry.dividend.ex_date, "%b %y")

        [
          ~s[<text x="#{lx}" y="#{r(label_y)}" fill="#475569" font-size="8" text-anchor="middle">#{date_str}</text>]
          | acc
        ]
    end
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  # --- Ownership & Holdings ---

  defp filter_dividends_to_ownership(dividends, []), do: dividends

  defp filter_dividends_to_ownership(dividends, holdings) do
    first_date = List.last(holdings).date

    Enum.filter(dividends, fn div ->
      Date.compare(div.ex_date, first_date) != :lt
    end)
  end

  defp compute_holding_stats([]), do: nil

  defp compute_holding_stats(holdings) do
    latest = hd(holdings)
    first = List.last(holdings)

    fx = latest.fx_rate || Decimal.new("1")
    qty = latest.quantity || Decimal.new("0")
    cost_basis = latest.cost_basis || Decimal.new("0")
    position_value = latest.value || Decimal.new("0")
    unrealized_pnl = latest.unrealized_pnl || Decimal.new("0")
    nav_pct = latest.weight || Decimal.new("0")

    periods = detect_ownership_periods(holdings)
    total_owned_days = Enum.reduce(periods, 0, fn p, acc -> acc + p.days end)

    extended = compute_extended_stats(cost_basis, qty, unrealized_pnl, latest)

    %{
      quantity: qty,
      avg_cost: latest.cost_price || Decimal.new("0"),
      total_invested: Decimal.mult(cost_basis, fx),
      current_value: Decimal.mult(position_value, fx),
      unrealized_pnl: Decimal.mult(unrealized_pnl, fx),
      percent_of_nav: nav_pct,
      currency: latest.currency || "EUR",
      fx_rate: fx,
      first_date: first.date,
      latest_date: latest.date,
      ownership_periods: periods,
      total_owned_days: total_owned_days,
      snapshots_count: length(holdings)
    }
    |> Map.merge(extended)
  end

  defp compute_extended_stats(cost_basis, qty, unrealized_pnl, latest) do
    return_pct = compute_return_pct(cost_basis, unrealized_pnl)
    pnl_per_share = compute_pnl_per_share(qty, unrealized_pnl)

    %{
      return_pct: return_pct,
      pnl_per_share: pnl_per_share,
      break_even: latest.cost_price || Decimal.new("0"),
      is_short: Decimal.compare(qty, Decimal.new("0")) == :lt
    }
  end

  defp compute_return_pct(cost_basis, unrealized_pnl) do
    abs_cost = Decimal.abs(cost_basis)

    if Decimal.compare(abs_cost, Decimal.new("0")) == :gt do
      unrealized_pnl
      |> Decimal.div(abs_cost)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
    else
      Decimal.new("0")
    end
  end

  defp compute_pnl_per_share(qty, unrealized_pnl) do
    if Decimal.compare(qty, Decimal.new("0")) != :eq do
      unrealized_pnl |> Decimal.div(qty) |> Decimal.round(2)
    else
      Decimal.new("0")
    end
  end

  # Detect separate ownership periods by finding gaps > 14 days in holdings history
  defp detect_ownership_periods(holdings) do
    holdings
    |> Enum.reverse()
    |> Enum.chunk_while([], &chunk_by_gap/2, &flush_chunk/1)
    |> Enum.map(fn period ->
      first = hd(period)
      last = List.last(period)

      %{
        start_date: first.date,
        end_date: last.date,
        days: Date.diff(last.date, first.date) + 1
      }
    end)
  end

  defp chunk_by_gap(h, []), do: {:cont, [h]}

  defp chunk_by_gap(h, [prev | _] = acc) do
    if Date.diff(h.date, prev.date) > 14 do
      {:cont, Enum.reverse(acc), [h]}
    else
      {:cont, [h | acc]}
    end
  end

  defp flush_chunk([]), do: {:cont, []}
  defp flush_chunk(acc), do: {:cont, Enum.reverse(acc), []}

  defp build_price_chart_data(holdings) do
    holdings
    |> Enum.reverse()
    |> Enum.map(fn h ->
      %{
        date: h.date,
        price: Decimal.to_float(h.price || Decimal.new("0")),
        quantity: Decimal.to_float(h.quantity || Decimal.new("0")),
        cost_basis: Decimal.to_float(h.cost_price || Decimal.new("0"))
      }
    end)
  end

  # Extract per-share value regardless of amount_type
  defp per_share_amount(dividend) do
    amount = dividend.amount || Decimal.new("0")

    if dividend.amount_type == "total_net" do
      cond do
        dividend.gross_rate && Decimal.compare(dividend.gross_rate, Decimal.new("0")) == :gt ->
          dividend.gross_rate

        dividend.quantity_at_record &&
            Decimal.compare(dividend.quantity_at_record, Decimal.new("0")) == :gt ->
          Decimal.div(amount, dividend.quantity_at_record)

        true ->
          Decimal.new("0")
      end
    else
      amount
    end
  end

  defp compute_dividends_with_income(dividends, holdings) do
    holdings_data =
      Enum.map(holdings, fn h ->
        {h.date, h.symbol, h.quantity, h.fx_rate, h.currency}
      end)

    Enum.map(dividends, fn div ->
      {income, matched_qty, fx_uncertain} =
        compute_single_dividend_income(div, holdings_data)

      %{
        dividend: div,
        income: income,
        matched_quantity: matched_qty,
        fx_uncertain: fx_uncertain
      }
    end)
  end

  defp compute_single_dividend_income(dividend, holdings_data) do
    amount = dividend.amount || Decimal.new("0")

    matching =
      holdings_data
      |> Enum.filter(fn {_date, symbol, _qty, _fx, _cur} -> symbol == dividend.symbol end)
      |> Enum.min_by(
        fn {date, _, _, _, _} -> abs(Date.diff(date, dividend.ex_date)) end,
        fn -> nil end
      )

    {matched_qty, holding_fx, holding_currency} =
      case matching do
        {_date, _symbol, quantity, fx_rate, currency} ->
          {quantity || Decimal.new("0"), fx_rate || Decimal.new("1"), currency}

        nil ->
          {Decimal.new("0"), Decimal.new("1"), nil}
      end

    {fx, fx_uncertain} = resolve_dividend_fx(dividend, holding_fx, holding_currency)

    if dividend.amount_type == "total_net" do
      {Decimal.mult(amount, fx), matched_qty, fx_uncertain}
    else
      {Decimal.mult(Decimal.mult(amount, matched_qty), fx), matched_qty, fx_uncertain}
    end
  end

  # Prefer dividend's own fx_rate; fall back to position fx_rate only if currencies match
  defp resolve_dividend_fx(dividend, holding_fx, holding_currency) do
    cond do
      dividend.fx_rate != nil -> {dividend.fx_rate, false}
      dividend.currency == "EUR" -> {Decimal.new("1"), false}
      dividend.currency == holding_currency -> {holding_fx, false}
      true -> {Decimal.new("1"), true}
    end
  end

  defp sum_dividend_income(dividends_with_income) do
    Enum.reduce(dividends_with_income, Decimal.new("0"), fn entry, acc ->
      if entry[:fx_uncertain] do
        acc
      else
        Decimal.add(acc, entry.income)
      end
    end)
  end

  # --- SVG Chart Helpers ---

  defp render_price_chart(chart_data) when length(chart_data) < 2 do
    Phoenix.HTML.raw("")
  end

  defp render_price_chart(chart_data) do
    w = 900
    ml = 62
    mr = 20
    pw = w - ml - mr
    mt = 20
    main_h = 180
    chart_bottom = mt + main_h
    total_h = chart_bottom + 25

    n = length(chart_data)
    x_fn = fn idx -> ml + idx / max(n - 1, 1) * pw end

    prices = Enum.map(chart_data, & &1.price)
    cost_bases = Enum.map(chart_data, & &1.cost_basis)
    all_values = prices ++ Enum.filter(cost_bases, &(&1 > 0))
    y_lo = Enum.min(all_values) * 0.97
    y_hi = Enum.max(all_values) * 1.03
    y_range = max(y_hi - y_lo, 0.01)
    y_fn = fn v -> mt + main_h - (v - y_lo) / y_range * main_h end

    price_lo = Enum.min(prices)
    price_hi = Enum.max(prices)

    area = svg_area(chart_data, x_fn, y_fn, chart_bottom, n)
    line = svg_price_line(chart_data, x_fn, y_fn)
    cost_basis_line = svg_cost_basis_line(chart_data, x_fn, y_fn)
    x_labels = svg_price_x_labels(chart_data, x_fn, chart_bottom + 15, n)
    y_labels = svg_price_y_labels(mt, main_h, y_lo, y_range, price_lo, price_hi)
    grid = svg_price_grid(mt, main_h)
    annotation = svg_price_annotation(chart_data, x_fn, y_fn, n, w)

    Phoenix.HTML.raw("""
    <svg width="100%" viewBox="0 0 #{w} #{round(total_h)}" xmlns="http://www.w3.org/2000/svg" style="font-family: 'JetBrains Mono', monospace;">
      #{grid}
      #{area}
      #{line}
      #{cost_basis_line}
      #{x_labels}
      #{y_labels}
      #{annotation}
    </svg>
    """)
  end

  # Price chart: more grid lines (7 divisions)
  defp svg_price_grid(mt, main_h) do
    ml = 62
    pw = 900 - 62 - 20
    steps = 7

    for i <- 0..steps do
      gy = r(mt + main_h - i / steps * main_h)

      ~s[<line x1="#{ml}" y1="#{gy}" x2="#{ml + pw}" y2="#{gy}" stroke="#1e293b" stroke-width="1"/>]
    end
    |> Enum.join("\n")
  end

  # Price chart: more Y labels (7 divisions) + hi/lo markers
  defp svg_price_y_labels(mt, main_h, y_lo, y_range, price_lo, price_hi) do
    ml = 62
    steps = 7

    grid_labels =
      for i <- 0..steps do
        gy = r(mt + main_h - i / steps * main_h + 3)
        val = y_lo + i / steps * y_range

        ~s[<text x="#{ml - 8}" y="#{gy}" fill="#475569" font-size="8" text-anchor="end">#{format_chart_val(val)}</text>]
      end

    # Add explicit lo/hi labels if they don't overlap with grid lines
    y_fn = fn v -> mt + main_h - (v - y_lo) / y_range * main_h end
    lo_y = r(y_fn.(price_lo) + 3)
    hi_y = r(y_fn.(price_hi) + 3)

    # Check if lo/hi are far enough from nearest grid line to avoid overlap
    grid_ys = for i <- 0..steps, do: mt + main_h - i / steps * main_h
    min_gap = 8

    lo_label =
      if Enum.all?(grid_ys, fn gy -> abs(y_fn.(price_lo) - gy) > min_gap end) do
        ~s[<text x="#{ml - 8}" y="#{lo_y}" fill="#ef4444" font-size="7" font-weight="600" text-anchor="end">#{format_chart_val(price_lo)}</text>]
      else
        ""
      end

    hi_label =
      if Enum.all?(grid_ys, fn gy -> abs(y_fn.(price_hi) - gy) > min_gap end) do
        ~s[<text x="#{ml - 8}" y="#{hi_y}" fill="#10b981" font-size="7" font-weight="600" text-anchor="end">#{format_chart_val(price_hi)}</text>]
      else
        ""
      end

    Enum.join(grid_labels ++ [lo_label, hi_label], "\n")
  end

  # Price chart: more X labels with dd Mmm 'yy format
  defp svg_price_x_labels(chart_data, x_fn, label_y, n) do
    count = min(10, n)
    step = max(div(n - 1, count), 1)

    for i <- 0..count, idx = min(i * step, n - 1), reduce: [] do
      acc ->
        point = Enum.at(chart_data, idx)
        lx = r(x_fn.(idx))
        date_str = Calendar.strftime(point.date, "%d %b '%y")

        [
          ~s[<text x="#{lx}" y="#{r(label_y)}" fill="#475569" font-size="7" text-anchor="middle">#{date_str}</text>]
          | acc
        ]
    end
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp svg_area(chart_data, x_fn, y_fn, bottom_y, n) do
    points =
      chart_data
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        "#{r(x_fn.(i))},#{r(y_fn.(p.price))}"
      end)

    first_x = r(x_fn.(0))
    last_x = r(x_fn.(n - 1))
    d = "M#{first_x},#{bottom_y} L#{Enum.join(points, " L")} L#{last_x},#{bottom_y} Z"
    ~s[<path d="#{d}" fill="#10b981" fill-opacity="0.08"/>]
  end

  defp svg_price_line(chart_data, x_fn, y_fn) do
    d =
      chart_data
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {p, i} ->
        x = r(x_fn.(i))
        y = r(y_fn.(p.price))
        if i == 0, do: "M#{x} #{y}", else: "L#{x} #{y}"
      end)

    ~s[<path d="#{d}" fill="none" stroke="#f97316" stroke-width="0.5" stroke-linejoin="round"/>]
  end

  defp svg_cost_basis_line(chart_data, x_fn, y_fn) do
    has_cost_basis = Enum.any?(chart_data, &(&1.cost_basis > 0))
    do_svg_cost_basis_line(has_cost_basis, chart_data, x_fn, y_fn)
  end

  defp do_svg_cost_basis_line(false, _chart_data, _x_fn, _y_fn), do: ""

  defp do_svg_cost_basis_line(true, chart_data, x_fn, y_fn) do
    d = svg_path_d(chart_data, x_fn, fn p -> y_fn.(p.cost_basis) end)

    ~s[<path d="#{d}" fill="none" stroke="#94a3b8" stroke-width="0.5" stroke-dasharray="4 3" stroke-linejoin="round" data-testid="cost-basis-line"/>]
  end

  defp svg_path_d(chart_data, x_fn, y_val_fn) do
    chart_data
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {p, i} ->
      x = r(x_fn.(i))
      y = r(y_val_fn.(p))
      if i == 0, do: "M#{x} #{y}", else: "L#{x} #{y}"
    end)
  end

  defp svg_x_labels(chart_data, x_fn, label_y, n) do
    count = min(6, n)
    step = max(div(n - 1, count), 1)

    for i <- 0..count, idx = min(i * step, n - 1), reduce: [] do
      acc ->
        point = Enum.at(chart_data, idx)
        lx = r(x_fn.(idx))
        date_str = Calendar.strftime(point.date, "%b %d")

        [
          ~s[<text x="#{lx}" y="#{r(label_y)}" fill="#475569" font-size="8" text-anchor="middle">#{date_str}</text>]
          | acc
        ]
    end
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp svg_price_annotation(chart_data, x_fn, y_fn, n, w) do
    last = List.last(chart_data)
    lx = r(x_fn.(n - 1))
    val_y = r(y_fn.(last.price))
    {label_x, anchor} = if lx > w - 80, do: {lx - 8, "end"}, else: {lx + 8, "start"}

    ~s[<text x="#{label_x}" y="#{val_y - 6}" fill="#f97316" font-size="8" font-weight="600" text-anchor="#{anchor}">#{format_chart_val(last.price)}</text>]
  end

  defp render_quantity_chart(chart_data) when length(chart_data) < 2 do
    Phoenix.HTML.raw("")
  end

  defp render_quantity_chart(chart_data) do
    w = 900
    ml = 62
    mr = 20
    pw = w - ml - mr
    mt = 12
    main_h = 110
    chart_bottom = mt + main_h
    total_h = chart_bottom + 25

    n = length(chart_data)
    x_fn = fn idx -> ml + idx / max(n - 1, 1) * pw end
    bar_w = max(pw / max(n - 1, 1) * 0.85, 2)

    quantities = Enum.map(chart_data, & &1.quantity)
    q_max = Enum.max(quantities) * 1.15
    q_max = max(q_max, 1.0)

    bars =
      chart_data
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {p, i} ->
        cx = x_fn.(i)
        bx = cx - bar_w / 2
        bar_h = max(p.quantity / q_max * main_h, 0)
        y = chart_bottom - bar_h

        ~s[<rect x="#{r(bx)}" y="#{r(y)}" width="#{r(bar_w)}" height="#{r(bar_h)}" fill="#60a5fa" rx="1"/>]
      end)

    x_labels = svg_x_labels(chart_data, x_fn, chart_bottom + 15, n)
    grid = svg_qty_grid(mt, main_h)
    y_labels = svg_qty_y_labels(mt, main_h, q_max)

    last = List.last(chart_data)
    last_x = r(x_fn.(n - 1))
    last_y = r(chart_bottom - last.quantity / q_max * main_h)
    {label_x, anchor} = if last_x > w - 80, do: {last_x - 8, "end"}, else: {last_x + 8, "start"}

    annotation =
      ~s[<text x="#{label_x}" y="#{last_y - 6}" fill="#60a5fa" font-size="8" font-weight="600" text-anchor="#{anchor}">#{round(last.quantity)}</text>]

    Phoenix.HTML.raw("""
    <svg width="100%" viewBox="0 0 #{w} #{round(total_h)}" xmlns="http://www.w3.org/2000/svg" style="font-family: 'JetBrains Mono', monospace;">
      #{grid}
      #{bars}
      #{x_labels}
      #{y_labels}
      #{annotation}
    </svg>
    """)
  end

  defp svg_qty_grid(mt, main_h) do
    ml = 62
    pw = 900 - 62 - 20

    for i <- 0..3 do
      gy = r(mt + main_h - i / 3 * main_h)

      ~s[<line x1="#{ml}" y1="#{gy}" x2="#{ml + pw}" y2="#{gy}" stroke="#1e293b" stroke-width="1"/>]
    end
    |> Enum.join("\n")
  end

  defp svg_qty_y_labels(mt, main_h, q_max) do
    ml = 62

    for i <- 0..3 do
      gy = r(mt + main_h - i / 3 * main_h + 3)
      val = round(q_max * i / 3)

      ~s[<text x="#{ml - 8}" y="#{gy}" fill="#475569" font-size="8" text-anchor="end">#{format_chart_val(val + 0.0)}</text>]
    end
    |> Enum.join("\n")
  end

  defp render_ownership_bar(holding_stats) do
    periods = holding_stats.ownership_periods
    first_date = holding_stats.first_date
    latest_date = holding_stats.latest_date
    total_span = max(Date.diff(latest_date, first_date), 1)
    total_owned = holding_stats.total_owned_days
    period_count = length(periods)

    segments =
      Enum.map(periods, fn period ->
        left = Date.diff(period.start_date, first_date) / total_span * 100
        width = max(period.days / total_span * 100, 1)
        {Float.round(left + 0.0, 1), Float.round(width + 0.0, 1)}
      end)

    duration_text = format_duration(total_owned)
    day_word = if total_owned == 1, do: "day", else: "days"

    period_info =
      if period_count > 1,
        do: "#{total_owned} #{day_word} (#{duration_text}) across #{period_count} periods",
        else: "#{total_owned} #{day_word} (#{duration_text})"

    period_labels =
      if period_count > 1 do
        labels =
          Enum.map_join(periods, "", fn period ->
            ~s[<span>#{Date.to_string(period.start_date)} → #{Date.to_string(period.end_date)} (#{period.days}d)</span>]
          end)

        ~s[<div style="display: flex; flex-wrap: wrap; gap: 8px; font-family: var(--font-mono); font-size: 0.5rem; color: var(--terminal-muted); margin-top: 4px;">#{labels}</div>]
      else
        ""
      end

    Phoenix.HTML.raw("""
    <div style="margin-top: var(--space-xs);">
      <div style="display: flex; justify-content: space-between; font-family: var(--font-mono); font-size: 0.625rem; color: var(--terminal-muted); margin-bottom: 4px;">
        <span>#{Date.to_string(first_date)}</span>
        <span>#{period_info}</span>
        <span>#{Date.to_string(latest_date)}</span>
      </div>
      <div style="width: 100%; height: 8px; background: #1e293b; border-radius: 4px; overflow: hidden; position: relative;">
        #{Enum.map_join(segments, "\n", fn {left, width} -> ~s[<div style="position: absolute; left: #{left}%; width: #{width}%; height: 100%; background: #10b981; border-radius: 2px;"></div>] end)}
      </div>
      #{period_labels}
    </div>
    """)
  end

  defp format_duration(days) do
    years = div(days, 365)
    remaining = rem(days, 365)
    months = div(remaining, 30)

    cond do
      years > 0 and months > 0 -> "#{years}y #{months}m"
      years > 0 -> "#{years}y"
      months > 0 -> "#{months}m"
      true -> "#{days}d"
    end
  end

  defp r(val), do: Float.round(val + 0.0, 1)

  defp format_chart_val(val) when is_number(val) do
    cond do
      val >= 1_000_000 -> "#{Float.round(val / 1_000_000, 1)}M"
      val >= 10_000 -> "#{round(val / 1_000)}K"
      val >= 1_000 -> "#{Float.round(val / 1_000, 1)}K"
      true -> "#{Float.round(val + 0.0, 2)}"
    end
  end

  defp format_chart_val(_), do: "0"

  # --- External Data ---

  defp get_company_profile(symbol) do
    case Stocks.get_company_profile(symbol) do
      {:ok, profile} -> profile
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp get_stock_quote(symbol) do
    case Stocks.get_quote(symbol) do
      {:ok, quote} -> quote
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp get_financial_metrics(symbol) do
    case Stocks.get_financial_metrics(symbol) do
      {:ok, metrics} -> metrics
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # {green_threshold, red_threshold, :higher_is_better | :lower_is_better}
  @metric_thresholds %{
    pe_ratio: {20, 30, :lower_is_better},
    roe: {15, 8, :higher_is_better},
    roa: {10, 5, :higher_is_better},
    net_margin: {20, 5, :higher_is_better},
    operating_margin: {15, 10, :higher_is_better},
    debt_to_equity: {0.5, 1.5, :lower_is_better},
    current_ratio: {1.5, 1.0, :higher_is_better},
    payout_ratio: {60, 80, :lower_is_better},
    fcf_margin: {15, 5, :higher_is_better}
  }

  defp metric_color_class(nil, _metric), do: ""

  defp metric_color_class(value, metric) do
    case Map.get(@metric_thresholds, metric) do
      nil -> ""
      thresholds -> apply_thresholds(Decimal.to_float(value), thresholds)
    end
  end

  defp apply_thresholds(val, {green, red, :higher_is_better}) do
    cond do
      val >= green -> "gain"
      val < red -> "loss"
      true -> ""
    end
  end

  defp apply_thresholds(val, {green, red, :lower_is_better}) do
    cond do
      val < 0 -> "loss"
      val <= green -> "gain"
      val > red -> "loss"
      true -> ""
    end
  end

  defp build_external_links(symbol, holdings, company_profile) do
    exchange = get_exchange(holdings, company_profile)
    isin = get_isin(holdings)

    links = [yahoo_link(symbol, exchange)]

    links =
      if exchange in ["NYSE", "NASDAQ", "ARCA"],
        do: links ++ [seeking_alpha_link(symbol)],
        else: links

    links = if isin && exchange == "HEX", do: links ++ [nordnet_link(isin)], else: links
    links = links ++ [google_finance_link(symbol, exchange)]

    Enum.reject(links, &is_nil/1)
  end

  defp get_exchange(holdings, company_profile) do
    cond do
      company_profile && company_profile.exchange -> company_profile.exchange
      holdings != [] -> hd(holdings).exchange
      true -> nil
    end
  end

  defp get_isin(holdings) do
    case holdings do
      [h | _] -> h.isin
      _ -> nil
    end
  end

  defp price_change_positive?(nil), do: true

  defp price_change_positive?(quote_data) do
    change = quote_data.change || Decimal.new("0")
    Decimal.compare(change, Decimal.new("0")) != :lt
  end

  defp yahoo_link(symbol, "HEX"),
    do: %{
      name: "Yahoo Finance",
      url: "https://finance.yahoo.com/quote/#{symbol}.HE",
      icon: "chart"
    }

  defp yahoo_link(symbol, "TSE"),
    do: %{
      name: "Yahoo Finance",
      url: "https://finance.yahoo.com/quote/#{symbol}.T",
      icon: "chart"
    }

  defp yahoo_link(symbol, "HKEX"),
    do: %{
      name: "Yahoo Finance",
      url: "https://finance.yahoo.com/quote/#{symbol}.HK",
      icon: "chart"
    }

  defp yahoo_link(symbol, _),
    do: %{name: "Yahoo Finance", url: "https://finance.yahoo.com/quote/#{symbol}", icon: "chart"}

  defp seeking_alpha_link(symbol),
    do: %{
      name: "SeekingAlpha",
      url: "https://seekingalpha.com/symbol/#{symbol}",
      icon: "analysis"
    }

  defp nordnet_link(isin),
    do: %{
      name: "Nordnet",
      url: "https://www.nordnet.fi/markkina/osakkeet/#{isin}",
      icon: "broker"
    }

  defp google_finance_link(symbol, exchange) do
    exchange_code =
      case exchange do
        "HEX" -> "HEL"
        "NYSE" -> "NYSE"
        "NASDAQ" -> "NASDAQ"
        "ARCA" -> "NYSEARCA"
        "TSE" -> "TYO"
        "HKEX" -> "HKG"
        _ -> nil
      end

    if exchange_code do
      %{
        name: "Google Finance",
        url: "https://www.google.com/finance/quote/#{symbol}:#{exchange_code}",
        icon: "search"
      }
    else
      nil
    end
  end
end
