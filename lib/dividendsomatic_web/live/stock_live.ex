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
    isin = get_isin(holdings)

    company_note =
      if isin, do: Stocks.get_or_init_company_note(isin, %{symbol: symbol}), else: nil

    holding_stats = compute_holding_stats(holdings)

    # Filter dividends to ownership period only
    owned_dividends = filter_dividends_to_ownership(all_dividends, holdings)
    dividends_with_income = compute_dividends_with_income(owned_dividends, holdings)
    total_dividend_income = sum_dividend_income(dividends_with_income)

    # Price chart data from holdings history (oldest first)
    price_chart_data = build_price_chart_data(holdings)

    socket =
      socket
      |> assign(:symbol, symbol)
      |> assign(:holdings_history, holdings)
      |> assign(:dividends_with_income, dividends_with_income)
      |> assign(:total_dividend_income, total_dividend_income)
      |> assign(:company_profile, company_profile)
      |> assign(:quote_data, quote_data)
      |> assign(:isin, isin)
      |> assign(:company_note, company_note)
      |> assign(:holding_stats, holding_stats)
      |> assign(:price_chart_data, price_chart_data)
      |> assign(:external_links, build_external_links(symbol, holdings, company_profile))

    {:ok, socket}
  end

  defp filter_dividends_to_ownership(dividends, []), do: dividends

  defp filter_dividends_to_ownership(dividends, holdings) do
    first_date = List.last(holdings).report_date

    Enum.filter(dividends, fn div ->
      Date.compare(div.ex_date, first_date) != :lt
    end)
  end

  defp compute_holding_stats([]), do: nil

  defp compute_holding_stats(holdings) do
    latest = hd(holdings)
    first = List.last(holdings)

    fx = latest.fx_rate_to_base || Decimal.new("1")
    qty = latest.quantity || Decimal.new("0")
    cost_basis = latest.cost_basis_money || Decimal.new("0")
    position_value = latest.position_value || Decimal.new("0")
    unrealized_pnl = latest.fifo_pnl_unrealized || Decimal.new("0")
    nav_pct = latest.percent_of_nav || Decimal.new("0")

    periods = detect_ownership_periods(holdings)
    total_owned_days = Enum.reduce(periods, 0, fn p, acc -> acc + p.days end)

    %{
      quantity: qty,
      avg_cost: latest.cost_basis_price || Decimal.new("0"),
      total_invested: Decimal.mult(cost_basis, fx),
      current_value: Decimal.mult(position_value, fx),
      unrealized_pnl: Decimal.mult(unrealized_pnl, fx),
      percent_of_nav: nav_pct,
      currency: latest.currency_primary || "EUR",
      fx_rate: fx,
      first_date: first.report_date,
      latest_date: latest.report_date,
      ownership_periods: periods,
      total_owned_days: total_owned_days,
      snapshots_count: length(holdings)
    }
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
        start_date: first.report_date,
        end_date: last.report_date,
        days: Date.diff(last.report_date, first.report_date) + 1
      }
    end)
  end

  defp chunk_by_gap(h, []), do: {:cont, [h]}

  defp chunk_by_gap(h, [prev | _] = acc) do
    if Date.diff(h.report_date, prev.report_date) > 14 do
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
        date: h.report_date,
        price: Decimal.to_float(h.mark_price || Decimal.new("0")),
        quantity: Decimal.to_float(h.quantity || Decimal.new("0"))
      }
    end)
  end

  defp compute_dividends_with_income(dividends, holdings) do
    holdings_data =
      Enum.map(holdings, fn h ->
        {h.report_date, h.symbol, h.quantity, h.fx_rate_to_base}
      end)

    Enum.map(dividends, fn div ->
      income = compute_single_dividend_income(div, holdings_data)
      %{dividend: div, income: income}
    end)
  end

  defp compute_single_dividend_income(dividend, holdings_data) do
    matching =
      holdings_data
      |> Enum.filter(fn {_date, symbol, _qty, _fx} -> symbol == dividend.symbol end)
      |> Enum.min_by(
        fn {date, _, _, _} -> abs(Date.diff(date, dividend.ex_date)) end,
        fn -> nil end
      )

    case matching do
      {_date, _symbol, quantity, fx_rate} ->
        qty = quantity || Decimal.new("0")
        fx = fx_rate || Decimal.new("1")
        amount = dividend.amount || Decimal.new("0")
        Decimal.mult(Decimal.mult(amount, qty), fx)

      nil ->
        Decimal.new("0")
    end
  end

  defp sum_dividend_income(dividends_with_income) do
    Enum.reduce(dividends_with_income, Decimal.new("0"), fn entry, acc ->
      Decimal.add(acc, entry.income)
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
    y_lo = Enum.min(prices) * 0.97
    y_hi = Enum.max(prices) * 1.03
    y_range = max(y_hi - y_lo, 0.01)
    y_fn = fn v -> mt + main_h - (v - y_lo) / y_range * main_h end

    area = svg_area(chart_data, x_fn, y_fn, chart_bottom, n)
    line = svg_price_line(chart_data, x_fn, y_fn)
    x_labels = svg_x_labels(chart_data, x_fn, chart_bottom + 15, n)
    y_labels = svg_y_labels(mt, main_h, y_lo, y_range)
    grid = svg_grid(mt, main_h)
    annotation = svg_price_annotation(chart_data, x_fn, y_fn, n, w)

    Phoenix.HTML.raw("""
    <svg width="#{w}" height="#{round(total_h)}" viewBox="0 0 #{w} #{round(total_h)}" xmlns="http://www.w3.org/2000/svg" style="font-family: 'JetBrains Mono', monospace;">
      #{grid}
      #{area}
      #{line}
      #{x_labels}
      #{y_labels}
      #{annotation}
    </svg>
    """)
  end

  defp svg_grid(mt, main_h) do
    ml = 62
    pw = 900 - 62 - 20

    for i <- 0..4 do
      gy = r(mt + main_h - i / 4 * main_h)

      ~s[<line x1="#{ml}" y1="#{gy}" x2="#{ml + pw}" y2="#{gy}" stroke="#1e293b" stroke-width="1"/>]
    end
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

  defp svg_y_labels(mt, main_h, y_lo, y_range) do
    ml = 62

    for i <- 0..4 do
      gy = r(mt + main_h - i / 4 * main_h + 3)
      val = y_lo + i / 4 * y_range

      ~s[<text x="#{ml - 8}" y="#{gy}" fill="#475569" font-size="8" text-anchor="end">#{format_chart_val(val)}</text>]
    end
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
    <svg width="#{w}" height="#{round(total_h)}" viewBox="0 0 #{w} #{round(total_h)}" xmlns="http://www.w3.org/2000/svg" style="font-family: 'JetBrains Mono', monospace;">
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
      holdings != [] -> hd(holdings).listing_exchange
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
