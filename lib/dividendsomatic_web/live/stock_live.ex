defmodule DividendsomaticWeb.StockLive do
  use DividendsomaticWeb, :live_view

  alias Dividendsomatic.{Portfolio, Stocks}

  @impl true
  def mount(%{"symbol" => symbol}, _session, socket) do
    holdings = Portfolio.list_holdings_by_symbol(symbol)
    dividends = Portfolio.list_dividends_by_symbol(symbol)
    company_profile = get_company_profile(symbol)
    quote_data = get_stock_quote(symbol)

    socket =
      socket
      |> assign(:symbol, symbol)
      |> assign(:holdings_history, holdings)
      |> assign(:dividends, dividends)
      |> assign(:company_profile, company_profile)
      |> assign(:quote_data, quote_data)
      |> assign(:external_links, build_external_links(symbol, holdings, company_profile))

    {:ok, socket}
  end

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

  defp format_decimal(nil), do: "0.00"
  defp format_decimal(decimal), do: decimal |> Decimal.round(2) |> Decimal.to_string()
end
