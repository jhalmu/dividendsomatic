# TODO - Dividendsomatic

## ✅ Tehty

- [x] Phoenix projekti + LiveView
- [x] SQLite tietokanta
- [x] Portfolio snapshot + holdings schemat
- [x] CSV parser (NimbleCSV)
- [x] Mix task: `mix import.csv`
- [x] LiveView portfolio viewer
- [x] DaisyUI taulukko
- [x] Yhteenveto-kortit (Holdings, Value, P&L)
- [x] Nuolinäppäin navigointi (← →)
- [x] P&L värikoodaus
- [x] Dokumentaatio (README, CLAUDE.md, SESSION_REPORT.md)
- [x] Git repo

## 🚧 Käynnissä

- [ ] GitHub repo luonti
- [ ] GitHub issueita

## 📋 Suunniteltu

### HIGH Priority

#### Gmail Automaatio
- [ ] Konfiguroi Oban SQLite:lle
  - [ ] Vaihda Postgres notifier → SQLite-yhteensopiva
  - [ ] Testaa Oban käynnistyy
- [ ] Aktivoi GmailImportWorker
  - [ ] Testaa Gmail MCP
  - [ ] Lataa CSV liitteet
  - [ ] Parsoi ja tallenna
- [ ] Cron schedule (klo 8 joka aamu)
- [ ] Error handling
- [ ] Email notifikaatiot virheistä

### MEDIUM Priority

#### Grafiikat (Contex)
- [ ] Lisää Contex dependency
- [ ] Portfolio arvo ajan yli (line chart)
  - [ ] Hae kaikki snapshots
  - [ ] Laske total value per päivä
  - [ ] Renderöi chart
- [ ] Holdings jakautuminen (pie chart)
  - [ ] Symboleittain
  - [ ] Valuutoittain
- [ ] P&L trendit (bar chart)
- [ ] Export chartit PNG:nä

#### Osingot
- [ ] Luo `dividends` taulu
  - [ ] holding_id, date, amount, currency
- [ ] Dividend entry form
- [ ] Linkitä dividendit holdingseihin
- [ ] Laske total dividend income
- [ ] Projektoi tulevat osingot
  - [ ] Keskiarvo per osake
  - [ ] Kertaa nykyisellä määrällä
- [ ] Dividend calendar
- [ ] Export dividend reports

#### Deployment
- [ ] Vaihda PostgreSQL tuotantoon
- [ ] Valitse palvelu (Hetzner/Fly.io/Railway)
- [ ] Luo tuotanto-konffi
- [ ] CI/CD pipeline
- [ ] Health checks
- [ ] Database backups
- [ ] SSL/TLS
- [ ] Monitoring (Sentry?)
- [ ] Logging

### LOW Priority

#### UI/UX Parannus
- [ ] DaisyUI theme selector
  - [ ] Light/Dark/Corporate/etc
  - [ ] Tallenna preferenssi
- [ ] Mobiili-responsiivisuus
  - [ ] Taulukko scroll
  - [ ] Stack kortit pystyyn
- [ ] Loading states
  - [ ] Skeleton loaders
  - [ ] Spinner navigoinnissa
- [ ] Better error messages
- [ ] Tooltips sarakkeille
- [ ] Sorting holdings
  - [ ] Symbol, Value, P&L
- [ ] Filtering
  - [ ] Currency
  - [ ] Asset class
- [ ] Search holdings
- [ ] Export CSV/Excel
- [ ] Print-friendly view

#### Testit
- [ ] ExMachina factory setup
- [ ] Context testit
  - [ ] Portfolio.get_latest_snapshot
  - [ ] Portfolio navigation
  - [ ] Portfolio.create_snapshot_from_csv
- [ ] LiveView testit
  - [ ] Render snapshot
  - [ ] Navigation events
  - [ ] Keyboard shortcuts
- [ ] CSV parser testit
  - [ ] Valid CSV
  - [ ] Invalid/malformed CSV
  - [ ] Empty CSV
- [ ] Integration testit
  - [ ] End-to-end CSV import
- [ ] Property-based testit
  - [ ] StreamData
  - [ ] P&L calculations
- [ ] Target: 80%+ coverage

#### Optimoinnit
- [ ] Cache latest snapshot
- [ ] Preload holdings eager
- [ ] Index optimointi
- [ ] DB query profilointi
- [ ] Add pagination (jos >100 holdings)

#### Security
- [ ] Add authentication
  - [ ] Phx.Gen.Auth?
  - [ ] Auth0?
- [ ] Rate limiting
- [ ] CSRF protection (on jo)
- [ ] SQL injection prevention (Ecto hoitaa)
- [ ] XSS prevention

## 💡 Ideoita (Backlog)

- [ ] Multi-user support
- [ ] Portfolio comparison (vs benchmarks)
- [ ] Tax reporting
- [ ] Transaction history
- [ ] Real-time quotes integration
- [ ] Email alerts (big gains/losses)
- [ ] Mobile app (Phoenix LiveView Native?)
- [ ] API endpoints
- [ ] Webhooks
- [ ] Portfolio goals & tracking
- [ ] Risk analysis
- [ ] Sector allocation
- [ ] Currency conversion rates
- [ ] Import from other brokers
- [ ] PDF reports

## 🐛 Bugit

Ei tunnettuja bugeja tällä hetkellä.

## 📝 Muistiinpanot

### Tekninen velka
- Oban disabled (vaatii SQLite notifier)
- Gmail/Worker-tiedostot olemassa mutta ei käytössä
- Ei testejä vielä
- Design tokens vain osittain käytössä

### Päätökset
- SQLite devissä, PostgreSQL tuotannossa
- DaisyUI komponentit (ei custom CSS)
- Kaikki 18 CSV-kenttää tallennettu
- NimbleCSV parseriksi

### Seuraava istunto
1. Luo GitHub repo
2. Kopioi issueita
3. Valitse: Oban konffi TAI Contex grafiikat
