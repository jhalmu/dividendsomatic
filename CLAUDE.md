# CLAUDE.md - Dividendsomatic

## Projektin kuvaus
Portfolio ja osinko-seurantajärjestelmä Interactive Brokers CSV-tiedostoille.

## Tekniset valinnat
- **Phoenix 1.8.1** + **LiveView 1.1.0**
- **SQLite** (dev), **PostgreSQL** (prod)
- **DaisyUI** (UI components)
- **NimbleCSV** (CSV parsing)
- **Tailwind CSS v4** design tokens

## Tärkeät komennot

```bash
# CSV lataus
mix import.csv path/to/file.csv

# Kehitys
mix phx.server         # localhost:4000
mix ecto.reset         # Resetoi tietokanta
mix compile            # Tarkista virheet

# Testaus (tulee myöhemmin)
mix test
```

## Tietokantarakenne

**portfolio_snapshots**
- report_date (unique, primary navigation key)
- raw_csv_data (backup)

**holdings** (18 CSV-kenttää)
- Symbol, Description, Quantity, MarkPrice
- PositionValue, CostBasisPrice, FifoPnlUnrealized
- jne. (kaikki Interactive Brokers CSV kentät)

## Context Pattern

```elixir
Portfolio.get_latest_snapshot()
Portfolio.get_snapshot_by_date(date)
Portfolio.get_previous_snapshot(date)  # nuoli ←
Portfolio.get_next_snapshot(date)      # nuoli →
```

## DaisyUI komponentit (käytä näitä)

```heex
<!-- Taulukko -->
<table class="table table-zebra">
  <thead><tr><th>Symbol</th></tr></thead>
  <tbody>
    <tr><td>KESKOB</td></tr>
  </tbody>
</table>

<!-- Navigointi -->
<button class="btn btn-circle">
  <.icon name="hero-arrow-left" />
</button>

<!-- Kortti -->
<div class="card card-bordered">
  <div class="card-body">Content</div>
</div>
```

## Design Tokens (homesite:sta)

```css
gap-[var(--space-md)]       /* 16-32px responsive */
text-[var(--text-base)]      /* 16-20px responsive */
p-[var(--space-sm)]          /* 8-16px padding */
```

## Seuraavat tehtävät

1. **LiveView näkymä** (PRIORITEETTI)
   - Näytä uusin snapshot
   - Taulukko holdings-listalle  
   - Nuolinäppäimet (← →)
   
2. **Automatisointi**
   - Oban worker
   - Gmail MCP integraatio
   - Päivittäinen CSV lataus

3. **Grafiikat**
   - Contex kirjasto
   - Portfolio arvo ajan yli

4. **Osingot**
   - Erillinen osinko-taulu
   - Laskuri tuleville osingoille

## Tiedostorakenne

```
lib/
  dividendsomatic/
    portfolio.ex           # Context
    portfolio/
      portfolio_snapshot.ex
      holding.ex
  dividendsomatic_web/
    live/
      portfolio_live.ex    # TODO: LiveView
  mix/
    tasks/
      import_csv.ex        # CSV import

priv/
  repo/
    migrations/
      *_create_portfolio_system.exs
```

## Muistutukset

- KAIKKI 18 CSV-kenttää mukaan (käyttäjän vaatimus)
- DaisyUI komponentit (ei custom CSS)
- Design tokens homesite:sta
- NimbleCSV parseriksi (ei String.split)
- Foreign key: `portfolio_snapshot_id`
