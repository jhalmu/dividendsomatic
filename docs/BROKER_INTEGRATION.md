# Broker API Integration Analysis

Research conducted 2026-02-12. Evaluating IBKR API integration options for headless production deployment on Hetzner VPS.

**Verdict: Do NOT integrate IBKR Client Portal API.** CSV import remains the primary data source. Monitor IBKR OAuth 2.0 availability for individual accounts.

---

## Table of Contents

- [IBKR API Variants](#ibkr-api-variants)
- [Client Portal API Authentication Flow](#client-portal-api-authentication-flow)
- [Security Red Flags](#security-red-flags-12-identified)
- [CSV Pipeline vs API Comparison](#csv-pipeline-vs-api-comparison)
- [Elixir ibkr_api Package](#elixir-ibkr_api-hex-package)
- [User's Python Implementations](#existing-python-implementations)
- [Nordnet API](#nordnet-api)
- [Multi-Broker Adapter Architecture](#multi-broker-adapter-architecture)
- [Verdict & Recommendations](#verdict--recommendations)
- [Sources](#sources)

---

## IBKR API Variants

| API | Protocol | Auth | Gateway Required | Headless Server |
|-----|----------|------|------------------|-----------------|
| **TWS API** | TCP socket | Local TWS/IB Gateway | Yes (Java desktop) | Possible but fragile |
| **Client Portal API** | REST/HTTP | Session cookie via browser | Yes (Java gateway) | Not officially supported |
| **Web API (new)** | REST/HTTP | OAuth 2.0 | No | Yes - but commercial/institutional only |
| **FIX Protocol** | FIX | N/A | N/A | For professional traders and institutions |

### TWS API (Trader Workstation API)

- TCP socket-based, not HTTP
- Requires TWS desktop or IB Gateway running locally
- More complex but feature-rich and high-throughput
- Supports Python, Java, C++, C#, VB.NET
- Designed for large data volumes and scalability

### Client Portal API v1.0 (REST/HTTP)

- RESTful HTTP endpoints over HTTPS
- Lightweight, no desktop software required (except optional Gateway)
- OAuth 1.0a, OAuth 2.0, SSO, or Client Portal Gateway for authentication
- Suitable for smaller operations, not high-throughput trading
- Two separate sessions: read-only portal session + optional brokerage session
- This is what the existing Python implementations use

### Web API (New - OAuth 2.0)

- IBKR is merging their APIs into a unified "IBKR Web API" with OAuth 2.0
- Currently commercial/institutional only
- When available for individual accounts, headless auth becomes possible

---

## Client Portal API Authentication Flow

```
User Credentials -> Java Gateway (localhost:5055) -> SSO/OAuth -> IBKR Servers
```

### Step 1: Gateway Authentication

- Java-based Client Portal Gateway runs locally on port 5055 (user's config: port 5056)
- Users login via browser to `https://localhost:5055` with IBKR credentials
- Two-factor authentication is MANDATORY
- Cannot be logged into the same account elsewhere (mutual exclusivity)

### Step 2: Brokerage Session Authorization

- Call `/iserver/auth/ssodh/init` endpoint to initialize trading permissions
- Separate from the read-only portal session
- Allows portfolio data access without trading permissions

### Step 3: Session Maintenance

- Call `/tickle` endpoint periodically to prevent session timeout
- Sessions persist for 24 hours
- Re-authentication via `/iserver/ssodh/init` if timeout occurs

### Available Endpoints

**Portfolio & Account:**
- `/portfolio/accounts` - Account information
- `/portfolio/subaccounts` - List of subaccounts
- `/portfolio/summary` - Cash, liquidation value, buying power
- `/portfolio/allocation` - Asset allocation
- `/portfolio/positions/` - Current holdings with P&L

**Market Data:**
- `/iserver/secdef/search` - Symbol search
- `/iserver/contract/{contractId}/info` - Contract details
- `/iserver/marketdata/snapshot` - Live quotes
- `/iserver/marketdata/history` - Historical data

**Trading (Require Brokerage Session):**
- `/iserver/accounts` - All accounts
- `/iserver/orders` - View pending orders
- `/iserver/account/{accountId}/orders` - Place orders

---

## Security Red Flags (12 Identified)

### Authentication Concerns (1-7)

1. **Authentication requires manual browser login** - The Client Portal Gateway requires a human to log in via browser on the same machine. No supported way to automate this for a headless production server.

2. **IBeam (headless workaround) is risky** - Third-party tool injects credentials programmatically but is not endorsed by Interactive Brokers, exposes credentials, requires TOTP automation, and provides no guarantee of uninterrupted operation.

3. **SSL certificate is expired** - IBKR's default JKS certificate chain is expired and they stated "new certificates will not be provided." Users must generate their own.

4. **`verify=False` pattern** - Both Python implementations disable SSL verification. Acceptable for localhost only, but a security smell.

5. **Session mutual exclusivity** - If the API is logged in, you can't use the same account in TWS or the web portal simultaneously. Blocks normal trading workflow.

6. **No API keys** - Unlike typical REST APIs, no persistent tokens. Session-based only, sessions expire and require human re-login.

7. **Gateway must run on same machine as API consumer** - IBKR explicitly says running the gateway on a separate machine is "not a supported practice."

### Architecture Concerns (8-12)

8. **Java dependency** - Gateway requires Java 8+ running as a separate process. On Hetzner VPS this means running Java alongside the Elixir release.

9. **Elixir library immaturity** - 8 stars, single maintainer, 19 commits. No production validation. The examples repo (CamonZ/ib_ex_examples) is empty.

10. **No dividend endpoint** - IBKR's Client Portal API has no dedicated dividend data endpoint. Dividend data is embedded in position/ledger data or requires external sources (which we already have via Finnhub/yfinance).

11. **WebSocket limit** - Only ~5 concurrent market data subscriptions per session.

12. **Session timeout** - Sessions die after inactivity, requiring re-authentication (which needs a human).

### Positive Security Aspects

- Connection from Gateway to IBKR servers is encrypted (HTTPS)
- Two-factor authentication is mandatory
- Mutual account-exclusivity prevents concurrent sessions
- Local-only authentication (no credential transmission over network)

---

## CSV Pipeline vs API Comparison

| Aspect | CSV Import (current) | IBKR Client Portal API |
|--------|---------------------|----------------------|
| **Runs headless** | Yes (Gmail auto-fetch) | No (manual login required) |
| **Data richness** | Full holding detail (20+ fields) | Partial (position + P&L) |
| **Dividend data** | Yes (separate CSV + yfinance) | No dedicated endpoint |
| **Historical snapshots** | Yes (immutable daily) | No (live data only) |
| **Security** | No credentials stored | Gateway + session cookies |
| **Reliability** | High (file-based) | Fragile (session expires) |
| **Real-time** | No (daily batch) | Yes |
| **Complexity** | Low | High (Java gateway + auth) |

---

## Elixir `ibkr_api` Hex Package

### Overview

- **Target API:** Interactive Brokers' Client Portal API (not TWS or Web API)
- **Gateway Requirement:** Must run IBKR's Client Portal Gateway locally (Java 8 Update 192+)
- **Local-only Communication:** All API calls must be from the same machine running the gateway

### Library Maturity

| Metric | Status |
|--------|--------|
| **Version** | 1.0.3 (released July 13, 2025) |
| **Total Downloads** | 2,299 (all-time) |
| **Weekly Downloads** | 12 |
| **Stars** | 8 (very low adoption) |
| **Forks** | 1 |
| **Total Commits** | 19 |
| **Maintainer** | mikaak (single maintainer) |
| **License** | MIT |

### Authentication

- Session-based cookies (not credential-based)
- `IbkrApi.ClientPortal.Auth.ping_server()` - Test connectivity
- `IbkrApi.ClientPortal.Auth.check_auth_status()` - Verify active session
- `IbkrApi.ClientPortal.Auth.reauthenticate()` - Restore expired sessions

### Architecture

**Dual-Channel Design:**
1. **REST API** (Synchronous) - Domain modules -> IbkrApi.HTTP -> Finch -> IBKR Gateway
2. **WebSocket** (Asynchronous Streaming) - WebSockex behavior, heartbeat every 10 seconds

**Modules:**
- `IbkrApi.ClientPortal.Portfolio` - Account summaries, positions, P&L, ledger data
- `IbkrApi.ClientPortal.Order` - Order placement, modification, cancellation
- `IbkrApi.ClientPortal.Contract` - Contract info, security definitions
- `IbkrApi.ClientPortal.MarketData` - Historical bars, live market snapshots
- `IbkrApi.ClientPortal.Trade` - Trade executions and history

### Dependencies

Core: finch, jason, websockex, hammer (rate limiting v7)
Requires Elixir 1.15+ / OTP 24+

### Known Limitations

1. WebSocket stream limit: ~5 concurrent market data subscriptions
2. Heartbeat required every 10 seconds or connection drops
3. Local gateway only: remote authentication impossible
4. Session timeouts require browser re-login
5. Historical data requests capped at 50 simultaneous
6. Pacing violations if <15 seconds between identical requests

---

## Existing Python Implementations

### `jhalmu/backend` (FastAPI + DuckDB)

- FastAPI web app with DuckDB persistence
- Mock API mode for development (`USE_MOCK` env var)
- Endpoints: dashboard, dividends, stock detail, symbol search
- **Real IBKR integration not implemented** (mock mode only)
- No dividend fetching from IBKR (no endpoint)
- Hardcoded EUR/USD rate (needs external FX)
- Uses `verify=False` for SSL

### `jhalmu/interactive-brokers-web-api` (Java Gateway Wrapper)

- Docker-based: Java Client Portal Gateway + Flask webapp
- Gateway on port 5056 with `conf.yaml` configuration
- Flask wrapper with portfolio, orders, watchlists, scanner endpoints
- CORS allows all origins (dangerous if exposed)
- **NOT production-ready:** missing error handling, logging, monitoring, health checks, credential rotation, rate limiting

---

## Nordnet API

### nExt API

- REST API + SSL socket feed
- Requires SSH public key registration on Nordnet's platform
- No test environment available (must contact Nordnet Trading Support)
- Available for Nordic markets (Sweden, Norway, Denmark, Finland)
- Focused on trading, limited portfolio reporting
- No Elixir library exists
- Java client, JavaScript, and Python examples available on GitHub
- Documentation last updated January 23, 2026

### Recommendation

Nordnet data can be imported via CSV export. Create a `NordnetCsvParser` alongside the existing IBKR `CsvParser`. The `DataIngestion` behaviour already supports multiple adapters.

---

## Multi-Broker Adapter Architecture

The existing adapter pattern in `lib/dividendsomatic/data_ingestion.ex` is the right foundation:

```
DataIngestion behaviour
  |-- CsvDirectory adapter (IBKR CSV files) [EXISTS]
  |-- GmailAdapter (IBKR email attachments) [EXISTS]
  |-- IbkrApiAdapter (future, if auth solved)
  |-- NordnetAdapter (future, CSV or API)
  |-- GenericCsvAdapter (any broker CSV export)
```

The behaviour defines three callbacks:

```elixir
@callback list_available(opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
@callback fetch_data(source_ref :: term()) :: {:ok, String.t()} | {:error, term()}
@callback source_name() :: String.t()
```

### Phased Approach

**Now (no API needed):**
- Nordnet data via CSV export + `NordnetCsvParser`
- The existing adapter pattern supports this natively

**Later (when IBKR solves headless auth):**
- IBKR unified Web API with OAuth 2.0 for individual accounts
- At that point, an `IbkrApiAdapter` makes sense

---

## Verdict & Recommendations

### Do NOT Integrate

The IBKR Client Portal API authentication model is fundamentally incompatible with a headless server on Hetzner. The security risks of workarounds (IBeam, credential injection) outweigh the benefits:

1. CSV import already works and provides richer data
2. Gmail auto-fetch gives near-real-time updates without API complexity
3. No dividend endpoint means we'd still need external sources
4. The Elixir library is too immature for production trust

### What the API Can Do Well

- Real-time portfolio positions and P&L
- Account balance/summary/allocation
- Historical market data
- Order placement and management
- Contract search and details

### What the API Cannot Do (for this use case)

- Run unattended on a headless production server (Hetzner)
- Provide dividend history/calendar data
- Replace CSV import (CSV has more detailed data per holding)
- Work alongside normal TWS trading sessions

### Next Steps

1. **Add Nordnet CSV parser** - New module alongside existing IBKR CSV parser
2. **Generalize identifier strategy** - Ensure ISIN-based lookup works across brokers
3. **Monitor IBKR OAuth 2.0** - Track when it becomes available for individual accounts
4. **Keep Python repos as reference/exploration tools** - Not as production dependencies

---

## Sources

### IBKR API Documentation

- [IBKR Trading API Solutions](https://www.interactivebrokers.com/en/trading/ib-api.php)
- [IBKR Web API v1.0 Documentation](https://www.interactivebrokers.com/campus/ibkr-api-page/cpapi-v1/)
- [IBKR Web API Documentation](https://www.interactivebrokers.com/campus/ibkr-api-page/webapi-doc/)
- [Web API Reference](https://www.interactivebrokers.com/campus/ibkr-api-page/webapi-ref/)
- [Client Portal API Documentation](https://interactivebrokers.github.io/cpwebapi/)
- [What is IBKR's Client Portal API?](https://www.interactivebrokers.com/campus/trading-lessons/what-is-ibkrs-client-portal-api/)
- [Launching and Authenticating the Gateway](https://www.interactivebrokers.com/campus/trading-lessons/launching-and-authenticating-the-gateway/)
- [Authenticating with IBKR Client Portal REST API](https://www.interactivebrokers.com/campus/traders-insight/authenticating-with-the-ibkr-client-portal-rest-api/)
- [Interactive Brokers Python API Guide](https://www.interactivebrokers.com/campus/ibkr-quant-news/interactive-brokers-python-api-native-a-step-by-step-guide/)
- [IBKR Client Portal API Gateway Setup](https://datawookie.dev/blog/2022/05/interactive-brokers-client-portal-api-gateway/)

### Elixir Libraries

- [ibkr_api v1.0.3 HexDocs](https://hexdocs.pm/ibkr_api/readme.html)
- [ibkr_api Getting Started Guide](https://hexdocs.pm/ibkr_api/getting_started.html)
- [ibkr_api Architecture Documentation](https://hexdocs.pm/ibkr_api/architecture.html)
- [ibkr_api GitHub Repository](https://github.com/MikaAK/ibkr_api)
- [ibkr_api Hex.pm Package](https://hex.pm/packages/ibkr_api)

### Tools and Third-Party

- [IBeam - Gateway Authentication Tool](https://github.com/Voyz/ibeam)

### Nordnet

- [Nordnet API Documentation](https://www.nordnet.se/externalapi/docs/api)
- [Nordnet GitHub](https://github.com/nordnet)
- [Nordnet nExt API v2 Examples](https://github.com/nordnet/next-api-v2-examples)

### User's Repositories

- [jhalmu/backend](https://github.com/jhalmu/backend) - Python FastAPI + DuckDB backend
- [jhalmu/interactive-brokers-web-api](https://github.com/jhalmu/interactive-brokers-web-api) - Java Gateway + Flask wrapper
