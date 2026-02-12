# Script for populating the database with mock data for development.
#
#     mix run priv/repo/seeds.exs
#
# Reset and seed:
#
#     mix ecto.reset && mix run priv/repo/seeds.exs

alias Dividendsomatic.Repo
alias Dividendsomatic.Portfolio.{PortfolioSnapshot, Holding, SoldPosition}

# Skip seeding if real data already exists (e.g., from CSV import)
if Repo.exists?(PortfolioSnapshot) do
  IO.puts("Skipping seeds: portfolio data already exists.")
else
  # --- Configuration ---

  # Portfolio of 7 European/US stocks, realistic for an IB account
  stocks = [
    %{
      symbol: "ASML",
      description: "ASML Holding NV",
      currency: "EUR",
      exchange: "AEB",
      asset_class: "STK",
      isin: "NL0010273215",
      base_price: Decimal.new("680.00"),
      quantity: Decimal.new("10"),
      cost_basis_price: Decimal.new("620.00"),
      nav_weight: 38.0,
      volatility: 0.015,
      # Buy events: {day_index, additional_qty, purchase_price}
      buy_events: [{20, 5, "700.00"}, {45, 3, "720.00"}]
    },
    %{
      symbol: "NOVO B",
      description: "Novo Nordisk A/S",
      currency: "DKK",
      exchange: "CSE",
      asset_class: "STK",
      isin: "DK0062498333",
      base_price: Decimal.new("850.00"),
      quantity: Decimal.new("30"),
      cost_basis_price: Decimal.new("780.00"),
      nav_weight: 22.0,
      volatility: 0.018,
      buy_events: [{15, 10, "820.00"}]
    },
    %{
      symbol: "MSFT",
      description: "Microsoft Corporation",
      currency: "USD",
      exchange: "NASDAQ",
      asset_class: "STK",
      isin: "US5949181045",
      base_price: Decimal.new("420.00"),
      quantity: Decimal.new("15"),
      cost_basis_price: Decimal.new("380.00"),
      nav_weight: 15.0,
      volatility: 0.012,
      buy_events: [{30, 5, "415.00"}, {50, 5, "435.00"}]
    },
    %{
      symbol: "SAP",
      description: "SAP SE",
      currency: "EUR",
      exchange: "IBIS",
      asset_class: "STK",
      isin: "DE0007164600",
      base_price: Decimal.new("195.00"),
      quantity: Decimal.new("50"),
      cost_basis_price: Decimal.new("170.00"),
      nav_weight: 10.0,
      volatility: 0.013,
      buy_events: []
    },
    %{
      symbol: "NESN",
      description: "Nestle SA",
      currency: "CHF",
      exchange: "SWX",
      asset_class: "STK",
      isin: "CH0038863350",
      base_price: Decimal.new("95.00"),
      quantity: Decimal.new("60"),
      cost_basis_price: Decimal.new("105.00"),
      nav_weight: 7.0,
      volatility: 0.008,
      buy_events: []
    },
    %{
      symbol: "OR",
      description: "L'Oreal SA",
      currency: "EUR",
      exchange: "SBF",
      asset_class: "STK",
      isin: "FR0000120321",
      base_price: Decimal.new("410.00"),
      quantity: Decimal.new("10"),
      cost_basis_price: Decimal.new("370.00"),
      nav_weight: 5.0,
      volatility: 0.011,
      buy_events: [{35, 5, "425.00"}]
    },
    %{
      symbol: "EQNR",
      description: "Equinor ASA",
      currency: "NOK",
      exchange: "OSE",
      asset_class: "STK",
      isin: "NO0010096985",
      base_price: Decimal.new("290.00"),
      quantity: Decimal.new("50"),
      cost_basis_price: Decimal.new("260.00"),
      nav_weight: 3.0,
      volatility: 0.020,
      buy_events: [{25, 15, "285.00"}, {40, 15, "300.00"}]
    }
  ]

  # Generate 65 trading days (~3 months) of snapshots
  # Start from ~3 months ago, skip weekends
  start_date = Date.add(Date.utc_today(), -90)

  trading_days =
    Stream.iterate(start_date, &Date.add(&1, 1))
    |> Stream.reject(fn date -> Date.day_of_week(date) in [6, 7] end)
    |> Enum.take(65)

  # Seed the random number generator for reproducible data
  :rand.seed(:exsss, {42, 42, 42})

  # Generate price series with random walk + slight upward drift
  generate_prices = fn base_price, volatility, num_days ->
    base = Decimal.to_float(base_price)

    {prices, _} =
      Enum.map_reduce(1..num_days, base, fn _i, prev ->
        # Random walk: slight upward bias + noise
        change = prev * (0.0003 + volatility * :rand.normal())
        new_price = max(prev + change, prev * 0.85)
        {new_price, new_price}
      end)

    prices
  end

  # Pre-generate all price series
  price_series =
    Enum.map(stocks, fn stock ->
      prices = generate_prices.(stock.base_price, stock.volatility, length(trading_days))
      {stock.symbol, prices}
    end)
    |> Map.new()

  # Pre-compute quantity and cost basis per stock per day (applying buy events)
  # Returns a map: %{"ASML" => [{qty, cost_basis_price}, ...], ...}
  position_history =
    Enum.map(stocks, fn stock ->
      buy_events = Map.get(stock, :buy_events, [])

      history =
        Enum.map(0..(length(trading_days) - 1), fn day_idx ->
          # Start with initial position
          init_qty = Decimal.to_float(stock.quantity)
          init_cost = Decimal.to_float(stock.cost_basis_price)

          # Apply all buy events up to this day
          {qty, avg_cost} =
            Enum.reduce(buy_events, {init_qty, init_cost}, fn {event_day, add_qty, price_str},
                                                              {q, c} ->
              if day_idx >= event_day do
                add_q = add_qty + 0.0
                buy_price = String.to_float(price_str <> "")
                # Weighted average cost basis
                new_qty = q + add_q
                new_cost = (q * c + add_q * buy_price) / new_qty
                {new_qty, new_cost}
              else
                {q, c}
              end
            end)

          {Decimal.from_float(qty) |> Decimal.round(0),
           Decimal.from_float(avg_cost) |> Decimal.round(2)}
        end)

      {stock.symbol, history}
    end)
    |> Map.new()

  IO.puts("Seeding #{length(trading_days)} trading days with #{length(stocks)} stocks each...")
  IO.puts("Buy events will create step changes in cost basis over time.")

  # --- Create Snapshots + Holdings ---

  Enum.each(Enum.with_index(trading_days), fn {date, day_idx} ->
    # Create snapshot
    {:ok, snapshot} =
      %PortfolioSnapshot{}
      |> PortfolioSnapshot.changeset(%{report_date: date})
      |> Repo.insert()

    # Create holdings for this day
    Enum.each(stocks, fn stock ->
      prices = Map.get(price_series, stock.symbol)
      current_price = Enum.at(prices, day_idx)
      mark_price = Decimal.from_float(current_price) |> Decimal.round(2)

      # Get quantity and cost basis for this day (with buy events applied)
      {quantity, cost_basis_price} = Enum.at(Map.get(position_history, stock.symbol), day_idx)

      position_value = Decimal.mult(quantity, mark_price) |> Decimal.round(2)
      cost_basis_money = Decimal.mult(quantity, cost_basis_price) |> Decimal.round(2)
      pnl = Decimal.sub(position_value, cost_basis_money) |> Decimal.round(2)

      %Holding{}
      |> Holding.changeset(%{
        portfolio_snapshot_id: snapshot.id,
        report_date: date,
        currency_primary: stock.currency,
        symbol: stock.symbol,
        description: stock.description,
        sub_category: "Common Stock",
        quantity: quantity,
        mark_price: mark_price,
        position_value: position_value,
        cost_basis_price: cost_basis_price,
        cost_basis_money: cost_basis_money,
        open_price: cost_basis_price,
        percent_of_nav: Decimal.new("#{stock.nav_weight}"),
        fifo_pnl_unrealized: pnl,
        listing_exchange: stock.exchange,
        asset_class: stock.asset_class,
        fx_rate_to_base: Decimal.new("1.00"),
        isin: stock.isin,
        figi: nil
      })
      |> Repo.insert!()
    end)
  end)

  IO.puts(
    "Created #{length(trading_days)} snapshots with #{length(trading_days) * length(stocks)} holdings."
  )

  # --- Create Sold Positions ---

  sold_positions_data = []

  Enum.each(sold_positions_data, fn attrs ->
    %SoldPosition{}
    |> SoldPosition.changeset(attrs)
    |> Repo.insert!()
  end)

  IO.puts("Created #{length(sold_positions_data)} sold position records.")

  IO.puts("\nSeed complete! Start the server with: mix phx.server")

  # End of guard: skip seeding if data already exists
end
