#!/usr/bin/env python3
"""
Fetch dividend and price data from Yahoo Finance via yfinance.

Usage:
    python3 tools/yfinance_fetch.py dividends KESKOB.HE
    python3 tools/yfinance_fetch.py dividends --all          # fetch for all symbols from DB
    python3 tools/yfinance_fetch.py history KESKOB.HE
    python3 tools/yfinance_fetch.py profile KESKOB.HE

Output goes to csv_data/dividends/, csv_data/history/, csv_data/profiles/
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

try:
    import yfinance as yf
except ImportError:
    print("Error: yfinance not installed. Run: pip3 install -r tools/requirements.txt")
    sys.exit(1)

# IB exchange -> Yahoo Finance suffix mapping
# Yahoo suffixes: .F = Frankfurt floor, .DE = Xetra, .HE = Helsinki, etc.
EXCHANGE_SUFFIX = {
    "HEX": ".HE",       # Helsinki
    "SFB": ".ST",        # Stockholm
    "OSE": ".OL",        # Oslo / Oslo Børs
    "TSE": ".TO",        # Toronto
    "TSEJ": ".T",        # Tokyo
    "SBF": ".PA",        # Paris (Euronext)
    "FWB": ".F",         # Frankfurt (floor trading)
    "FWB2": ".F",        # Frankfurt (FWB2 = Xetra in IB, but .F works better on Yahoo)
    "IBIS": ".DE",       # Xetra (electronic)
    "LSE": ".L",         # London
    "SEHK": ".HK",       # Hong Kong
    "NYSE": "",          # US exchanges - no suffix
    "NASDAQ": "",
    "ARCA": "",
    "AMEX": "",
}

PROJECT_ROOT = Path(__file__).parent.parent


# IB symbol overrides for symbols that don't follow standard conversion
# (ib_symbol, exchange) -> yahoo_symbol
SYMBOL_OVERRIDES = {
    # Oslo: IB uses "o" suffix for some Norwegian stocks
    ("EQNRo", "OSE"): "EQNR.OL",
    ("FROo", "OSE"): "FRO.OL",
    ("NHYo", "OSE"): "NHY.OL",
    ("YARo", "OSE"): "YAR.OL",
    # Hong Kong: Yahoo needs zero-padded 4-digit codes
    ("11", "SEHK"): "0011.HK",
    ("669", "SEHK"): "0669.HK",
    ("700", "SEHK"): "0700.HK",
    ("916", "SEHK"): "0916.HK",
    # Toronto REITs: IB uses ".UN", Yahoo uses "-UN"
    ("SGR.UN", "TSE"): "SGR-UN.TO",
    ("AD.UN", "TSE"): "AD-UN.TO",
    ("AP.UN", "TSE"): "AP-UN.TO",
    # Preferred shares: IB uses "PRF"/"PRA"/"PRB", Yahoo uses "-PF"/"-PA"/"-PB"
    ("RNR PRF", "NYSE"): "RNR-PF",
    ("CIM PRA", "NYSE"): "CIM-PA",
    ("CIM PRB", "NYSE"): "CIM-PB",
    # Helsinki: IB uses short codes, Yahoo uses full names with .HE suffix
    ("KEK", "HEX"): "KESKOB.HE",      # Kesko B shares
    ("FOT", "HEX"): "FORTUM.HE",      # Fortum
    ("04Q", "HEX"): "NDA-FI.HE",      # Nordea Bank (IB uses Frankfurt code on HEX)
    ("N2S", "HEX"): "MANTA.HE",       # Mandatum
    ("RPL", "HEX"): "UPM.HE",         # UPM-Kymmene
    ("OUTA", "HEX"): "OUT1V.HE",      # Outokumpu
    ("OFK", "HEX"): "ORNBV.HE",       # Orion B shares
    ("NEF", "HEX"): "NESTE.HE",       # Neste
    ("TLS", "HEX"): "TELIA1.HE",      # Telia Company (Helsinki listing)
    ("2A41", "HEX"): "AKTIA.HE",      # Aktia Bank
    ("STEAVh", "HEX"): "STEAV.HE",    # Stora Enso A shares (h = share class suffix)
    ("TOKMAh", "HEX"): "TOKMAN.HE",   # Tokmanni (h = share class suffix)
    ("TTEB", "HEX"): "TIETO.HE",      # TietoEVRY
    # Frankfurt / FWB2: prefer primary listing exchange on Yahoo
    ("RAUA", "FWB"): "RAUTE.HE",      # Raute, primary listing Helsinki
    ("TELIA1", "FWB"): "TELIA1.HE",   # Telia, Helsinki listing has dividend data
    ("BEW", "FWB2"): "BEW.F",         # Diversified Royalty Corp (Frankfurt)
    ("GKE", "FWB2"): "GKE.F",         # Hisense Home Appliances (Frankfurt)
    ("CVZ", "FWB2"): "CVZ.F",         # Vermilion Energy (Frankfurt)
    # Golden Ocean: merged with CMB.TECH Aug 2025, delisted from NASDAQ
    ("GOGL", "NASDAQ"): "GOGL",        # may no longer have data post-merger
    # Portman Ridge Finance: rebranded to BCP Investment Corp, ticker changed
    ("PTMN", "NASDAQ"): "PTMN",        # still on Yahoo under old ticker
}


def get_yahoo_symbol(ib_symbol, exchange):
    """Convert IB symbol + exchange to Yahoo Finance ticker.

    Handles several IB-specific conventions:
    - Oslo "o" suffix (EQNRo -> EQNR)
    - Helsinki "h" suffix for share classes (STEAVh -> STEAV)
    - Hong Kong numeric codes need zero-padding to 4 digits
    - Toronto .UN REITs use -UN on Yahoo (SGR.UN -> SGR-UN)
    - US preferred shares use -P{letter} on Yahoo (CIM PRA -> CIM-PA)
    """
    # Check overrides first
    key = (ib_symbol, exchange)
    if key in SYMBOL_OVERRIDES:
        return SYMBOL_OVERRIDES[key]

    suffix = EXCHANGE_SUFFIX.get(exchange, "")
    # Clean up IB quirks: spaces become hyphens
    symbol = ib_symbol.replace(" ", "-")

    # Strip trailing "o" for Oslo stocks (IB convention for odd lots/share class)
    if exchange == "OSE" and symbol.endswith("o") and len(symbol) > 1:
        symbol = symbol[:-1]

    # Strip trailing "h" for Helsinki share classes (e.g., STEAVh, TOKMAh)
    if exchange == "HEX" and symbol.endswith("h") and len(symbol) > 1:
        symbol = symbol[:-1]

    # Hong Kong: zero-pad numeric codes to 4 digits (700 -> 0700)
    if exchange == "SEHK" and symbol.isdigit():
        symbol = symbol.zfill(4)

    # Toronto REITs: .UN -> -UN (Yahoo Finance convention)
    if exchange == "TSE" and ".UN" in symbol:
        symbol = symbol.replace(".UN", "-UN")

    # US preferred shares: "PRx" -> "-Px" (IB "CIM-PRA" -> Yahoo "CIM-PA")
    if exchange in ("NYSE", "NASDAQ", "AMEX", "ARCA"):
        m = re.match(r"^(.+)-PR([A-Z])$", symbol)
        if m:
            symbol = f"{m.group(1)}-P{m.group(2)}"

    # Some IB symbols already have exchange suffix (e.g., 8750.T)
    if "." in symbol and any(symbol.endswith(s) for s in EXCHANGE_SUFFIX.values() if s):
        return symbol
    return f"{symbol}{suffix}"


def get_all_symbols_from_db():
    """Get all unique symbol/exchange pairs from the database via mix."""
    try:
        result = subprocess.run(
            ["mix", "run", "-e", """
import Ecto.Query
Dividendsomatic.Repo.all(
  from h in Dividendsomatic.Portfolio.Holding,
  select: {h.symbol, h.listing_exchange, h.isin},
  distinct: true
) |> Enum.each(fn {s, e, isin} -> IO.puts(s <> "\\t" <> (e || "") <> "\\t" <> (isin || "")) end)
"""],
            capture_output=True, text=True, cwd=str(PROJECT_ROOT)
        )
        symbols = []
        for line in result.stdout.strip().split("\n"):
            if "\t" in line and not line.startswith("["):
                parts = line.split("\t")
                if len(parts) >= 2:
                    symbols.append({
                        "symbol": parts[0],
                        "exchange": parts[1],
                        "isin": parts[2] if len(parts) > 2 else None,
                    })
        return symbols
    except Exception as e:
        print(f"Error fetching symbols from DB: {e}")
        return []


def fetch_dividends(yahoo_symbol, ib_symbol, exchange, isin=None):
    """Fetch dividend history for a symbol."""
    print(f"  Fetching dividends for {yahoo_symbol}...")
    try:
        ticker = yf.Ticker(yahoo_symbol)
        divs = ticker.dividends
        if divs is None or divs.empty:
            print(f"  No dividend data for {yahoo_symbol}")
            return None

        records = []
        for date, amount in divs.items():
            records.append({
                "symbol": ib_symbol,
                "yahoo_symbol": yahoo_symbol,
                "exchange": exchange,
                "isin": isin,
                "ex_date": date.strftime("%Y-%m-%d"),
                "amount": round(float(amount), 6),
                "currency": ticker.info.get("currency", "USD"),
            })

        return records
    except Exception as e:
        print(f"  Error fetching {yahoo_symbol}: {e}")
        return None


def fetch_history(yahoo_symbol, ib_symbol, exchange, period="max"):
    """Fetch price history for a symbol."""
    print(f"  Fetching history for {yahoo_symbol}...")
    try:
        ticker = yf.Ticker(yahoo_symbol)
        hist = ticker.history(period=period, repair=True)
        if hist is None or hist.empty:
            print(f"  No history for {yahoo_symbol}")
            return None

        records = []
        for date, row in hist.iterrows():
            records.append({
                "symbol": ib_symbol,
                "yahoo_symbol": yahoo_symbol,
                "date": date.strftime("%Y-%m-%d"),
                "open": round(float(row["Open"]), 4),
                "high": round(float(row["High"]), 4),
                "low": round(float(row["Low"]), 4),
                "close": round(float(row["Close"]), 4),
                "volume": int(row["Volume"]),
            })

        return records
    except Exception as e:
        print(f"  Error fetching {yahoo_symbol}: {e}")
        return None


def fetch_profile(yahoo_symbol, ib_symbol, exchange, isin=None):
    """Fetch company profile for a symbol."""
    print(f"  Fetching profile for {yahoo_symbol}...")
    try:
        ticker = yf.Ticker(yahoo_symbol)
        info = ticker.info
        if not info:
            print(f"  No profile for {yahoo_symbol}")
            return None

        return {
            "symbol": ib_symbol,
            "yahoo_symbol": yahoo_symbol,
            "exchange": exchange,
            "isin": isin,
            "name": info.get("longName") or info.get("shortName"),
            "sector": info.get("sector"),
            "industry": info.get("industry"),
            "country": info.get("country"),
            "currency": info.get("currency"),
            "market_cap": info.get("marketCap"),
            "dividend_rate": info.get("dividendRate"),
            "dividend_yield": info.get("dividendYield"),
            "ex_dividend_date": info.get("exDividendDate"),
            "payout_ratio": info.get("payoutRatio"),
            "trailing_pe": info.get("trailingPE"),
            "forward_pe": info.get("forwardPE"),
            "price": info.get("currentPrice") or info.get("regularMarketPrice"),
            "fifty_two_week_high": info.get("fiftyTwoWeekHigh"),
            "fifty_two_week_low": info.get("fiftyTwoWeekLow"),
        }
    except Exception as e:
        print(f"  Error fetching {yahoo_symbol}: {e}")
        return None


def save_json(data, output_dir, filename):
    """Save data as JSON file."""
    out_path = PROJECT_ROOT / "csv_data" / output_dir
    out_path.mkdir(parents=True, exist_ok=True)
    filepath = out_path / f"{filename}.json"
    with open(filepath, "w") as f:
        json.dump(data, f, indent=2, default=str)
    print(f"  Saved: {filepath}")


def cmd_dividends(args):
    """Handle dividends command."""
    if args.symbol in ("--all", "all", None):
        symbols = get_all_symbols_from_db()
        if not symbols:
            print("No symbols found in database")
            return
        print(f"Fetching dividends for {len(symbols)} symbols...")
        for entry in symbols:
            yahoo = get_yahoo_symbol(entry["symbol"], entry["exchange"])
            records = fetch_dividends(yahoo, entry["symbol"], entry["exchange"], entry.get("isin"))
            if records:
                safe_name = yahoo.replace("/", "_")
                save_json(records, "dividends", safe_name)
    else:
        yahoo = args.symbol
        records = fetch_dividends(yahoo, yahoo, "")
        if records:
            safe_name = yahoo.replace("/", "_")
            save_json(records, "dividends", safe_name)


def cmd_history(args):
    """Handle history command."""
    yahoo = args.symbol
    records = fetch_history(yahoo, yahoo, "")
    if records:
        safe_name = yahoo.replace("/", "_")
        save_json(records, "history", safe_name)


def cmd_profile(args):
    """Handle profile command."""
    yahoo = args.symbol
    record = fetch_profile(yahoo, yahoo, "")
    if record:
        safe_name = yahoo.replace("/", "_")
        save_json(record, "profiles", safe_name)


def main():
    parser = argparse.ArgumentParser(description="Fetch data from Yahoo Finance")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    div_parser = subparsers.add_parser("dividends", help="Fetch dividend history")
    div_parser.add_argument("symbol", nargs="?", default="--all",
                            help="Yahoo Finance symbol (omit for all DB symbols)")

    hist_parser = subparsers.add_parser("history", help="Fetch price history")
    hist_parser.add_argument("symbol", help="Yahoo Finance symbol")

    prof_parser = subparsers.add_parser("profile", help="Fetch company profile")
    prof_parser.add_argument("symbol", help="Yahoo Finance symbol")

    args = parser.parse_args()

    if args.command == "dividends":
        cmd_dividends(args)
    elif args.command == "history":
        cmd_history(args)
    elif args.command == "profile":
        cmd_profile(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
