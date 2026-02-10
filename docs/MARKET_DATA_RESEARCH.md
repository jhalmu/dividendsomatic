# Market Data Provider Research

Research on financial market data APIs for Dividendsomatic portfolio tracker. Focus: international stock coverage for Finnish, Japanese, Hong Kong, and Chinese markets.

---

## 1. Current Setup (Finnhub)

**What we have**: Finnhub.io integration via REST API + Req HTTP client
- Stock quotes with 15-minute cache TTL (`lib/dividendsomatic/stocks.ex`)
- Company profiles with 7-day cache TTL
- Free tier: 60 API calls/minute
- Config: `FINNHUB_API_KEY` env var

**Strengths**:
- Generous free tier (60 calls/min ~ 86,400/day)
- Partnership with Nordic IR for Finnish/Scandinavian stocks
- Real-time US market data
- Company fundamentals and economic data
- Well-documented REST API

**Limitations**:
- Limited historical data on free tier
- Asian market coverage varies by exchange
- No dedicated dividend tracking API (only earnings calendar)
- Rate limiting at scale (60/min = 1/sec effective)

---

## 2. Provider Comparison

### Finnhub (Current)
- **Free tier**: 60 requests/minute
- **Exchanges**: Global, 60+ (including Nordic via partnership)
- **Real-time**: Yes (US), 15-min delayed (some international)
- **Historical**: Limited on free tier
- **Dividends**: Basic earnings calendar only
- **Elixir lib**: None (use Req)
- **Best for**: Real-time quotes, company profiles
- **Website**: https://finnhub.io/

### Alpha Vantage
- **Free tier**: 25 requests/day, 5/minute (very restrictive)
- **Exchanges**: 20+ global (NYSE, NASDAQ, LSE, major EU/Asia)
- **Real-time**: Premium only for US, 15-min delayed free
- **Historical**: 20+ years, excellent
- **Dividends**: Included in adjusted price series
- **Elixir lib**: None (use Req)
- **Best for**: Historical analysis, backtesting
- **Website**: https://www.alphavantage.co/

### Twelve Data
- **Free tier**: 800 API credits/day (8 per request = ~100 requests)
- **Exchanges**: 90+ international
- **Real-time**: Yes (1-second updates on premium)
- **Historical**: Good, varies by exchange
- **Dividends**: Available
- **WebSocket**: Yes, for streaming
- **Elixir lib**: None (use Req)
- **Pricing**: Starting $29/month for international
- **Best for**: Asian markets (dedicated TSE, HKEX pages), WebSocket streaming
- **Website**: https://twelvedata.com/

### EODHD (EOD Historical Data)
- **Free tier**: 20 requests/day (past year only)
- **Exchanges**: 60+, 150,000+ tickers worldwide
- **Real-time**: Yes
- **Historical**: 30+ years (best in class)
- **Dividends**: Excellent, 30 years of data
- **Elixir lib**: None (use Req)
- **Pricing**: $19.99-$59.99/month (consumer), $399+/month (commercial)
- **Best for**: Historical data, dividend tracking, fundamental analysis
- **Website**: https://eodhd.com/

### MarketStack
- **Free tier**: 100 requests/month (very restrictive)
- **Exchanges**: 70+, 170,000+ tickers
- **Real-time**: Professional tier only
- **Historical**: 30 years on premium
- **Dividends**: Limited
- **Pricing**: $10k-$500k/month (enterprise pricing)
- **Best for**: Not recommended (expensive, restrictive free tier)
- **Website**: https://marketstack.com/

### Polygon.io
- **Free tier**: 5 calls/minute
- **Exchanges**: **US ONLY** - not suitable for international portfolio
- **Best for**: US high-frequency trading only
- **Website**: https://polygon.io/

### Yahoo Finance (yfinance)
- **Free tier**: Unlimited* (unofficial, scraping-based)
- **Exchanges**: Global
- **Historical**: Excellent
- **Dividends**: Good
- **CAUTION**: No official API. Reliability issues reported 2024-2025 (429 errors, IP bans). Against TOS for commercial use. yfinance library often returns errors.
- **Best for**: Not recommended for production use
- **Website**: https://finance.yahoo.com/

### IEX Cloud
- **Status**: Service closed August 31, 2024 - **No longer available**

### OpenBB
- **Free tier**: Open source platform (31,000+ GitHub stars)
- **Exchanges**: Aggregates 350+ datasets from 100+ providers
- **Best for**: Research/analysis workstation, not direct API integration
- **Website**: https://openbb.co/

---

## 3. Market Coverage Matrix

| Market | Finnhub | Alpha V. | Twelve | EODHD | MarketStack |
|--------|---------|----------|--------|-------|-------------|
| **Finnish (Nasdaq Helsinki)** | Yes (Nordic IR) | Yes | Yes | Yes | Yes |
| **Japanese (TSE)** | Yes | Yes | Yes (dedicated) | Yes | Yes |
| **Hong Kong (HKEX)** | Yes | Yes | Yes | Yes | Yes |
| **Chinese (SSE/SZSE)** | Partial | Yes | Yes | Yes | Yes |
| **US (NYSE/NASDAQ)** | Yes (best) | Yes | Yes | Yes | Yes |

### Finnish Stocks (Nasdaq Helsinki)
Tickers: KESKOB, NESTE, UPM, AKTIA, FORTUM, NOKISEUR, etc.

**Best option**: Finnhub (current) - has direct partnership with Nordic IR, making it the best free option for Helsinki Exchange data.

**Alternative**: Nasdaq Nordic also offers a Python library (`nasdaqnordic_query`) for querying Finnish stocks directly. Free tier: 100 calls/year (testing only).

### Japanese Stocks (Tokyo Stock Exchange)
**Best option**: Twelve Data has dedicated Tokyo Stock Exchange support pages.
**Alternative**: Finnhub covers TSE but with less detail.
**Yahoo Finance suffix**: `.T` (e.g., `7203.T` for Toyota)

### Hong Kong Stocks (HKEX)
**Best option**: EODHD or Twelve Data for comprehensive coverage.
**Alternative**: LSEG has 2,000+ eligible HK equities with CN-HK mutual market access.
**Yahoo Finance suffix**: `.HK` (e.g., `0700.HK` for Tencent)

### Chinese Stocks (Shanghai/Shenzhen)
**Best option**: EODHD supports both SSE and SZSE.
**Alternative**: LSEG has dedicated Chinese coverage.
**Yahoo Finance suffixes**: `.SS` (Shanghai), `.SZ` (Shenzhen)

---

## 4. Free Tier Comparison

| Provider | Rate Limit | Daily Capacity | Monthly Capacity | Quality |
|----------|-----------|----------------|------------------|---------|
| **Finnhub** | 60/min | ~86,400 | ~2.6M | Very good |
| **Twelve Data** | 800 credits/day | ~100 req | ~3,000 | Good |
| **Alpha Vantage** | 5/min, 25/day | 25 | ~750 | Poor |
| **EODHD** | 20/day | 20 | ~600 | Poor |
| **MarketStack** | 100/month | ~3 | 100 | Very poor |

**For our portfolio** (~10-15 stocks, daily refresh): Finnhub free tier is more than sufficient. Even with 15 stocks refreshed every 15 minutes during market hours, that's only ~60 calls/hour.

---

## 5. Dividend Data Quality

| Provider | History | Quality | Notes |
|----------|---------|---------|-------|
| **EODHD** | 30 years | Excellent | Best for dividend-focused apps |
| **Alpha Vantage** | 20+ years | Good | Via adjusted price series |
| **Twelve Data** | Varies | Good | Available for supported markets |
| **Finnhub** | Limited | Basic | Earnings calendar only, not dedicated |
| **MarketStack** | Limited | Poor | Not a focus |

**For dividend tracking**: EODHD is the clear winner. $20/month gets 30 years of dividend history across global markets. This is the main gap in our current Finnhub setup.

---

## 6. Recommendation

### Multi-Provider Strategy

1. **Primary (real-time quotes)**: Keep **Finnhub**
   - Already integrated and working
   - Best free tier for our needs
   - Good Nordic/Finnish coverage via Nordic IR partnership
   - Real-time US data

2. **Historical + Dividends**: Add **EODHD** ($20/month)
   - 30 years historical data
   - Excellent dividend tracking
   - Good for portfolio backtesting and analytics
   - Fills the main gap in Finnhub

3. **Asian Markets Fallback**: **Twelve Data** (if needed)
   - 800 credits/day free tier
   - Dedicated TSE and HKEX support
   - WebSocket streaming for real-time
   - Only add if Finnhub proves insufficient for specific Asian tickers

### Implementation Approach

Build a `MarketData` context with provider adapters (same behavioural pattern as `DataIngestion`):

```elixir
defmodule Dividendsomatic.MarketData do
  @callback get_quote(symbol :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_history(symbol :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback get_dividends(symbol :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback get_company_profile(symbol :: String.t()) :: {:ok, map()} | {:error, term()}
end
```

Adapters:
- `lib/dividendsomatic/market_data/finnhub.ex` (migrate from current `stocks.ex`)
- `lib/dividendsomatic/market_data/eodhd.ex` (new)
- `lib/dividendsomatic/market_data/twelve_data.ex` (future, if needed)

The context routes requests to the appropriate provider based on exchange/market or user configuration.

---

## 7. External Link Resources

### Yahoo Finance
**URL**: `https://finance.yahoo.com/quote/{TICKER}`

Exchange suffixes:
- Helsinki (HEX): `.HE` → `https://finance.yahoo.com/quote/KESKOB.HE`
- Tokyo (TSE): `.T` → `https://finance.yahoo.com/quote/7203.T`
- Hong Kong (HKEX): `.HK` → `https://finance.yahoo.com/quote/0700.HK`
- Shanghai (SSE): `.SS` → `https://finance.yahoo.com/quote/600519.SS`
- Shenzhen (SZSE): `.SZ` → `https://finance.yahoo.com/quote/000858.SZ`
- US (NYSE/NASDAQ): no suffix → `https://finance.yahoo.com/quote/AAPL`

Chart URL: `https://finance.yahoo.com/chart/{TICKER}/`

### SeekingAlpha
**URL**: `https://seekingalpha.com/symbol/{TICKER}`
- US stocks only (NYSE, NASDAQ)
- Example: `https://seekingalpha.com/symbol/AAPL`

### Nordnet
**URL**: `https://www.nordnet.fi/markkina/osakkeet/{ISIN}`
- Finnish platform, uses ISIN for stock lookup
- ISINs available from our Holding schema (field: `isin`)
- Example: `https://www.nordnet.fi/markkina/osakkeet/FI0009000202` (Kesko)

### Google Finance
**URL**: `https://www.google.com/finance/quote/{TICKER}:{EXCHANGE}`
- Universal, works for any market
- Example: `https://www.google.com/finance/quote/KESKOB:HEL`

---

## Sources

- [Finnhub Stock APIs](https://finnhub.io/)
- [Finnhub + Nordic IR Partnership](https://www.sttinfo.fi/tiedote/69889152/)
- [Alpha Vantage Documentation](https://www.alphavantage.co/documentation/)
- [Twelve Data API](https://twelvedata.com/)
- [EOD Historical Data](https://eodhd.com/)
- [MarketStack](https://marketstack.com/)
- [Polygon.io](https://polygon.io/)
- [OpenBB Platform](https://openbb.co/)
- [Nasdaq Nordic Query Library](https://github.com/samlinz/nasdaqnordic_query)
- [IEX Cloud Shutdown Analysis](https://www.alphavantage.co/iexcloud_shutdown_analysis_and_migration/)
