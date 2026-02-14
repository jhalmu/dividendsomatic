# Session Report — 2026-02-14

## Unified Portfolio History: Schema Redesign

### Context
The portfolio chart used two separate data pipelines:
1. **Runtime reconstruction** from `broker_transactions` (Nordnet era, 2017-2022)
2. **Direct snapshots** from `portfolio_snapshots` + `holdings` (IBKR Flex, 2025+)

This created complexity, a 3-year gap (2022-2025), and made adding new data sources require new reconstruction code each time.

### Solution
One unified history with precomputed totals. The chart reads from ONE query, no runtime reconstruction.

### Changes

| Task | Description |
|------|-------------|
| 1. Migration | New `portfolio_snapshots` and `positions` tables; old tables renamed to `legacy_*` |
| 2. Schemas | New `Position` schema (generic field names), updated `PortfolioSnapshot` (added `source`, `data_quality`, `total_value`, `total_cost`, `metadata`) |
| 3. Data migration task | `mix migrate.to_unified` — copies legacy data to new tables with field mapping |
| 4. Portfolio context | `get_all_chart_data/0` now a simple query (no joins, no reconstruction); all functions updated for new field names |
| 5. CsvParser | `parse/3` outputs Position-compatible fields; dropped fields prefixed with `_` |
| 6. LiveView + chart | All field references updated (`holdings` -> `positions`, `mark_price` -> `price`, etc.) |
| 7. Import pipelines | All mix tasks updated: `Holding` -> `Position`, removed `invalidate_chart_cache` calls |
| 8. Tests | All 447 tests updated and passing, 0 failures, credo clean |

### Field Mapping

| Old (Holding) | New (Position) |
|---------------|----------------|
| `report_date` | `date` |
| `currency_primary` | `currency` |
| `description` | `name` |
| `mark_price` | `price` |
| `position_value` | `value` |
| `cost_basis_money` | `cost_basis` |
| `cost_basis_price` | `cost_price` |
| `fifo_pnl_unrealized` | `unrealized_pnl` |
| `percent_of_nav` | `weight` |
| `listing_exchange` | `exchange` |
| `fx_rate_to_base` | `fx_rate` |
| `raw_csv_data` | `metadata` (JSONB) |

### New Source/Quality Tracking

| Source | `source` | `data_quality` |
|--------|----------|----------------|
| IBKR Flex CSV | `ibkr_flex` | `actual` |
| Nordnet reconstruction | `nordnet` | `reconstructed` |
| 9A sold positions | `trade_history` | `reconstructed` |
| API backfill | `api_backfill` | `estimated` |

### Files Changed (31 files)

**New files:**
- `priv/repo/migrations/20260214141149_unified_portfolio_history.exs`
- `lib/dividendsomatic/portfolio/position.ex`
- `lib/dividendsomatic/portfolio/legacy_portfolio_snapshot.ex`
- `lib/mix/tasks/migrate_to_unified.ex`

**Modified (27 files):**
- `lib/dividendsomatic/portfolio.ex` — Context rewrite
- `lib/dividendsomatic/portfolio/csv_parser.ex` — New field names
- `lib/dividendsomatic/portfolio/portfolio_snapshot.ex` — New schema fields
- `lib/dividendsomatic/portfolio/holding.ex` — Points to legacy_holdings
- `lib/dividendsomatic/portfolio/processors/sold_position_processor.ex`
- `lib/dividendsomatic/stocks/symbol_mapper.ex`
- `lib/dividendsomatic_web/live/portfolio_live.ex`
- `lib/dividendsomatic_web/live/portfolio_live.html.heex`
- `lib/dividendsomatic_web/live/stock_live.ex`
- `lib/dividendsomatic_web/components/portfolio_chart.ex`
- `lib/mix/tasks/backfill_nordnet_snapshots.ex`
- `lib/mix/tasks/backfill_isin.ex`
- `lib/mix/tasks/import_csv.ex`
- `lib/mix/tasks/import_reimport.ex`
- `lib/mix/tasks/import_ibkr.ex`
- `lib/mix/tasks/import_nordnet.ex`
- `lib/mix/tasks/fetch_historical_prices.ex`
- `test/dividendsomatic/schema_test.exs`
- `test/dividendsomatic/portfolio_test.exs`
- `test/dividendsomatic/portfolio_fx_test.exs`
- `test/dividendsomatic/portfolio/csv_parser_test.exs`
- `test/dividendsomatic/data_ingestion_test.exs`
- `test/dividendsomatic/import_csv_test.exs`
- `test/dividendsomatic_web/live/portfolio_live_test.exs`
- `test/dividendsomatic_web/live/data_gaps_live_test.exs`
- `config/config.exs`
- `bin/fetch_flex_email.sh`

### Verification
- `mix test`: 447 tests, 0 failures
- `mix credo --strict`: 0 issues
- `mix compile --warnings-as-errors`: clean

### Next Steps
1. Run `mix ecto.migrate` + `mix migrate.to_unified` on dev database
2. Verify chart renders correctly at localhost:4000
3. Materialize Nordnet reconstruction data (mix task)
4. Materialize 9A sold positions as chart data
5. Drop `legacy_*` tables after verification period
