#!/usr/bin/env python3
"""
Extract dividend and tax data from Lynx/IBKR PDF reports.

Requires: pip install pdfplumber

Usage:
    python scripts/extract_lynx_pdfs.py
    python scripts/extract_lynx_pdfs.py --input csv_data/archive/Lynx/
    python scripts/extract_lynx_pdfs.py --output data_revisited/lynx/
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

try:
    import pdfplumber
except ImportError:
    print("Error: pdfplumber not installed. Run: pip install pdfplumber")
    sys.exit(1)


def extract_dividends_pdf(pdf_path):
    """Extract dividend records from dividends_U*.pdf files."""
    records = []
    print(f"  Extracting dividends from {os.path.basename(pdf_path)}...")

    with pdfplumber.open(pdf_path) as pdf:
        for page_num, page in enumerate(pdf.pages):
            tables = page.extract_tables()
            for table in tables:
                for row in table:
                    if row and len(row) >= 5:
                        record = parse_dividend_row(row)
                        if record:
                            records.append(record)

            # Also try text extraction for non-tabular data
            text = page.extract_text()
            if text:
                text_records = parse_dividend_text(text)
                records.extend(text_records)

            if (page_num + 1) % 50 == 0:
                print(f"    Processed {page_num + 1}/{len(pdf.pages)} pages...")

    # Deduplicate
    seen = set()
    unique = []
    for r in records:
        key = (r.get("symbol", ""), r.get("date", ""), r.get("amount", ""))
        if key not in seen:
            seen.add(key)
            unique.append(r)

    print(f"  Found {len(unique)} unique dividend records")
    return unique


def parse_dividend_row(row):
    """Parse a single row from a dividend table."""
    try:
        # Typical format: Symbol | Date | Description | Amount | Currency
        cleaned = [str(cell).strip() if cell else "" for cell in row]

        # Look for rows with a date pattern and amount
        date_pattern = re.compile(r"\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4}|\d{2}\.\d{2}\.\d{4}")
        amount_pattern = re.compile(r"-?[\d,]+\.?\d*")

        date_str = None
        amount_str = None
        symbol = None

        for cell in cleaned:
            if not date_str and date_pattern.search(cell):
                date_str = date_pattern.search(cell).group()
            if not amount_str and amount_pattern.fullmatch(cell.replace(",", "")):
                amount_str = cell.replace(",", "")

        # First non-empty cell that looks like a symbol
        for cell in cleaned:
            if cell and len(cell) <= 10 and cell.isalpha():
                symbol = cell
                break

        if date_str and amount_str:
            try:
                amount = float(amount_str)
                if abs(amount) > 0:
                    return {
                        "symbol": symbol or "UNKNOWN",
                        "date": normalize_date(date_str),
                        "amount": abs(amount),
                        "raw_amount": amount,
                        "source": "lynx_pdf",
                    }
            except ValueError:
                pass
    except Exception:
        pass
    return None


def parse_dividend_text(text):
    """Parse dividends from raw text (fallback for non-tabular pages)."""
    records = []
    # Match lines like: SYMBOL 2024-01-15 Cash Dividend 123.45 USD
    pattern = re.compile(
        r"([A-Z]{1,10})\s+"
        r"(\d{4}-\d{2}-\d{2})\s+"
        r".*?(?:dividend|payment).*?"
        r"([\d,]+\.?\d*)\s+"
        r"([A-Z]{3})",
        re.IGNORECASE,
    )

    for match in pattern.finditer(text):
        try:
            amount = float(match.group(3).replace(",", ""))
            if amount > 0:
                records.append(
                    {
                        "symbol": match.group(1),
                        "date": match.group(2),
                        "amount": amount,
                        "currency": match.group(4),
                        "source": "lynx_pdf_text",
                    }
                )
        except ValueError:
            pass

    return records


def extract_9a_trades(pdf_path):
    """Extract trade data from 9A tax report PDFs."""
    records = []
    print(f"  Extracting 9A trades from {os.path.basename(pdf_path)}...")

    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page_num, page in enumerate(pdf.pages):
                tables = page.extract_tables()
                for table in tables:
                    for row in table:
                        record = parse_9a_trade_row(row)
                        if record:
                            records.append(record)

                if (page_num + 1) % 100 == 0:
                    print(f"    Processed {page_num + 1}/{len(pdf.pages)} pages...")
    except Exception as e:
        print(f"  Warning: Error processing {os.path.basename(pdf_path)}: {e}")

    print(f"  Found {len(records)} trade records")
    return records


def parse_9a_trade_row(row):
    """Parse a trade row from 9A tax report."""
    if not row or len(row) < 4:
        return None

    try:
        cleaned = [str(cell).strip() if cell else "" for cell in row]
        date_pattern = re.compile(r"\d{4}-\d{2}-\d{2}")
        amount_pattern = re.compile(r"-?[\d,]+\.?\d+")

        dates = []
        amounts = []

        for cell in cleaned:
            for m in date_pattern.finditer(cell):
                dates.append(m.group())
            for m in amount_pattern.finditer(cell.replace(",", "")):
                try:
                    amounts.append(float(m.group()))
                except ValueError:
                    pass

        if len(dates) >= 1 and len(amounts) >= 1:
            symbol = cleaned[0] if cleaned[0] and len(cleaned[0]) <= 15 else None
            if symbol:
                return {
                    "symbol": symbol,
                    "date": dates[0],
                    "amounts": amounts,
                    "source": "9a_pdf",
                }
    except Exception:
        pass
    return None


def extract_16b_summary(pdf_path):
    """Extract annual summary data from 16B tax form PDFs."""
    records = []
    print(f"  Extracting 16B summary from {os.path.basename(pdf_path)}...")

    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages[:5]:  # Summary is usually on first few pages
                text = page.extract_text()
                if text:
                    # Look for total lines
                    for line in text.split("\n"):
                        if any(
                            kw in line.lower()
                            for kw in ["total", "yhteensä", "summa", "net"]
                        ):
                            amounts = re.findall(r"[\d,]+\.?\d*", line)
                            if amounts:
                                records.append(
                                    {
                                        "line": line.strip(),
                                        "amounts": amounts,
                                        "source": "16b_pdf",
                                    }
                                )
    except Exception as e:
        print(f"  Warning: Error processing {os.path.basename(pdf_path)}: {e}")

    print(f"  Found {len(records)} summary lines")
    return records


def extract_costs(pdf_path):
    """Extract cost/commission data from cost overview PDFs."""
    records = []
    print(f"  Extracting costs from {os.path.basename(pdf_path)}...")

    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                tables = page.extract_tables()
                for table in tables:
                    for row in table:
                        if row and len(row) >= 2:
                            cleaned = [
                                str(cell).strip() if cell else "" for cell in row
                            ]
                            amounts = []
                            for cell in cleaned:
                                try:
                                    val = float(cell.replace(",", "").replace(" ", ""))
                                    amounts.append(val)
                                except ValueError:
                                    pass

                            if amounts:
                                records.append(
                                    {
                                        "description": " | ".join(
                                            c for c in cleaned if c
                                        ),
                                        "amounts": amounts,
                                        "source": "cost_pdf",
                                    }
                                )
    except Exception as e:
        print(f"  Warning: Error processing {os.path.basename(pdf_path)}: {e}")

    print(f"  Found {len(records)} cost records")
    return records


def normalize_date(date_str):
    """Normalize date string to ISO format."""
    # DD/MM/YYYY -> YYYY-MM-DD
    m = re.match(r"(\d{2})/(\d{2})/(\d{4})", date_str)
    if m:
        return f"{m.group(3)}-{m.group(2)}-{m.group(1)}"

    # DD.MM.YYYY -> YYYY-MM-DD
    m = re.match(r"(\d{2})\.(\d{2})\.(\d{4})", date_str)
    if m:
        return f"{m.group(3)}-{m.group(2)}-{m.group(1)}"

    return date_str


def save_json(data, output_path):
    """Save data as formatted JSON."""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(data, f, indent=2, default=str)
    print(f"  Saved {len(data)} records to {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Extract data from Lynx/IBKR PDFs")
    parser.add_argument(
        "--input", default="csv_data/archive/Lynx", help="Input directory"
    )
    parser.add_argument(
        "--output", default="data_revisited/lynx", help="Output directory"
    )
    args = parser.parse_args()

    input_dir = Path(args.input)
    output_dir = Path(args.output)

    if not input_dir.exists():
        print(f"Error: Input directory not found: {input_dir}")
        sys.exit(1)

    print(f"=== Lynx PDF Extraction ===")
    print(f"Input:  {input_dir}")
    print(f"Output: {output_dir}\n")

    pdf_files = sorted(input_dir.glob("*.pdf"))
    print(f"Found {len(pdf_files)} PDF files\n")

    all_dividends = []
    all_9a_trades = []
    all_16b_summaries = []
    all_costs = []

    for pdf_path in pdf_files:
        name = pdf_path.name.lower()

        if "dividend" in name:
            records = extract_dividends_pdf(str(pdf_path))
            all_dividends.extend(records)
        elif "9a" in name or "9a_" in name:
            # Skip very large 9A files (>50MB) - they take too long
            size_mb = pdf_path.stat().st_size / (1024 * 1024)
            if size_mb > 50:
                print(
                    f"  Skipping {pdf_path.name} ({size_mb:.0f}MB - too large, use CSV instead)"
                )
            else:
                records = extract_9a_trades(str(pdf_path))
                all_9a_trades.extend(records)
        elif "16b" in name:
            size_mb = pdf_path.stat().st_size / (1024 * 1024)
            if size_mb > 30:
                print(f"  Skipping {pdf_path.name} ({size_mb:.0f}MB - too large)")
            else:
                records = extract_16b_summary(str(pdf_path))
                all_16b_summaries.extend(records)
        elif "kustannus" in name or "cost" in name:
            records = extract_costs(str(pdf_path))
            all_costs.extend(records)
        else:
            print(f"  Skipping {pdf_path.name} (unknown type)")

    # Save results
    print(f"\n=== Results ===")
    if all_dividends:
        save_json(all_dividends, str(output_dir / "dividends.json"))
    if all_9a_trades:
        save_json(all_9a_trades, str(output_dir / "9a_trades.json"))
    if all_16b_summaries:
        save_json(all_16b_summaries, str(output_dir / "16b_summaries.json"))
    if all_costs:
        save_json(all_costs, str(output_dir / "costs.json"))

    print(f"\nTotal: {len(all_dividends)} dividends, {len(all_9a_trades)} trades, "
          f"{len(all_16b_summaries)} summaries, {len(all_costs)} costs")


if __name__ == "__main__":
    main()
