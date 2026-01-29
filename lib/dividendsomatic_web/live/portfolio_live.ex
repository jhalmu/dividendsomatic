defmodule DividendsomaticWeb.PortfolioLive do
  use DividendsomaticWeb, :live_view
  
  alias Dividendsomatic.Portfolio

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Portfolio.get_latest_snapshot()
    
    socket =
      socket
      |> assign(:snapshot, snapshot)
      |> assign(:page_title, "Portfolio")
    
    {:ok, socket}
  end

  @impl true
  def handle_event("navigate_previous", _params, socket) do
    current_date = socket.assigns.snapshot.report_date
    
    case Portfolio.get_previous_snapshot(current_date) do
      nil -> {:noreply, socket}
      snapshot -> {:noreply, assign(socket, :snapshot, snapshot)}
    end
  end

  @impl true
  def handle_event("navigate_next", _params, socket) do
    current_date = socket.assigns.snapshot.report_date
    
    case Portfolio.get_next_snapshot(current_date) do
      nil -> {:noreply, socket}
      snapshot -> {:noreply, assign(socket, :snapshot, snapshot)}
    end
  end

  @impl true
  def handle_event("key_down", %{"key" => "ArrowLeft"}, socket) do
    handle_event("navigate_previous", %{}, socket)
  end

  def handle_event("key_down", %{"key" => "ArrowRight"}, socket) do
    handle_event("navigate_next", %{}, socket)
  end

  def handle_event("key_down", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen" phx-window-keydown="key_down">
      <.header>
        Portfolio Snapshot
        <:subtitle>
          <%= if @snapshot do %>
            <%= Calendar.strftime(@snapshot.report_date, "%B %d, %Y") %>
          <% else %>
            No data available
          <% end %>
        </:subtitle>
      </.header>

      <%= if @snapshot do %>
        <div class="mt-[var(--space-lg)]">
          <!-- Navigation -->
          <div class="flex justify-center gap-[var(--space-md)] mb-[var(--space-lg)]">
            <button 
              phx-click="navigate_previous" 
              class="btn btn-circle btn-primary"
              title="Previous day (←)"
            >
              <.icon name="hero-arrow-left" class="w-6 h-6" />
            </button>
            
            <div class="flex items-center gap-[var(--space-sm)] px-[var(--space-md)]">
              <.icon name="hero-calendar" class="w-5 h-5" />
              <span class="font-semibold text-[var(--text-lg)]">
                <%= Calendar.strftime(@snapshot.report_date, "%Y-%m-%d") %>
              </span>
            </div>
            
            <button 
              phx-click="navigate_next" 
              class="btn btn-circle btn-primary"
              title="Next day (→)"
            >
              <.icon name="hero-arrow-right" class="w-6 h-6" />
            </button>
          </div>

          <!-- Summary Cards -->
          <div class="grid grid-cols-1 md:grid-cols-3 gap-[var(--space-md)] mb-[var(--space-lg)]">
            <div class="card card-bordered bg-base-100">
              <div class="card-body">
                <h3 class="card-title text-[var(--text-base)]">Total Holdings</h3>
                <p class="text-[var(--text-2xl)] font-bold">
                  <%= length(@snapshot.holdings) %>
                </p>
              </div>
            </div>

            <div class="card card-bordered bg-base-100">
              <div class="card-body">
                <h3 class="card-title text-[var(--text-base)]">Total Value</h3>
                <p class="text-[var(--text-2xl)] font-bold">
                  <%= format_total_value(@snapshot.holdings) %>
                </p>
              </div>
            </div>

            <div class="card card-bordered bg-base-100">
              <div class="card-body">
                <h3 class="card-title text-[var(--text-base)]">Total P&L</h3>
                <p class={[
                  "text-[var(--text-2xl)] font-bold",
                  pnl_color(@snapshot.holdings)
                ]}>
                  <%= format_total_pnl(@snapshot.holdings) %>
                </p>
              </div>
            </div>
          </div>

          <!-- Holdings Table -->
          <div class="card card-bordered bg-base-100">
            <div class="card-body">
              <h2 class="card-title text-[var(--text-xl)]">Holdings</h2>
              
              <div class="overflow-x-auto">
                <table class="table table-zebra">
                  <thead>
                    <tr>
                      <th>Symbol</th>
                      <th>Description</th>
                      <th class="text-right">Quantity</th>
                      <th class="text-right">Price</th>
                      <th class="text-right">Value</th>
                      <th class="text-right">Cost Basis</th>
                      <th class="text-right">P&L</th>
                      <th class="text-right">% of NAV</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for holding <- @snapshot.holdings do %>
                      <tr>
                        <td class="font-semibold"><%= holding.symbol %></td>
                        <td><%= holding.description %></td>
                        <td class="text-right"><%= Decimal.to_string(holding.quantity) %></td>
                        <td class="text-right">
                          <%= holding.currency_primary %> <%= format_decimal(holding.mark_price, 2) %>
                        </td>
                        <td class="text-right font-semibold">
                          <%= holding.currency_primary %> <%= format_decimal(holding.position_value, 2) %>
                        </td>
                        <td class="text-right">
                          <%= holding.currency_primary %> <%= format_decimal(holding.cost_basis_money, 2) %>
                        </td>
                        <td class={["text-right font-semibold", pnl_text_color(holding.fifo_pnl_unrealized)]}>
                          <%= holding.currency_primary %> <%= format_decimal(holding.fifo_pnl_unrealized, 2) %>
                        </td>
                        <td class="text-right"><%= format_decimal(holding.percent_of_nav, 2) %>%</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <!-- Keyboard shortcuts help -->
          <div class="alert alert-info mt-[var(--space-lg)]">
            <.icon name="hero-information-circle" class="w-6 h-6" />
            <span>Use <kbd class="kbd kbd-sm">←</kbd> and <kbd class="kbd kbd-sm">→</kbd> arrow keys to navigate between dates</span>
          </div>
        </div>
      <% else %>
        <div class="alert alert-warning mt-[var(--space-lg)]">
          <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
          <span>No portfolio data available. Import CSV files to get started.</span>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions
  
  defp format_decimal(nil, _precision), do: "0.00"
  defp format_decimal(decimal, precision) do
    decimal
    |> Decimal.round(precision)
    |> Decimal.to_string(:normal)
    |> String.replace(~r/\.?0+$/, "")
    |> then(fn s ->
      if String.contains?(s, ".") do
        s
      else
        s <> ".00"
      end
    end)
  end

  defp format_total_value(holdings) do
    total =
      Enum.reduce(holdings, Decimal.new("0"), fn holding, acc ->
        Decimal.add(acc, holding.position_value || Decimal.new("0"))
      end)
    
    # Simplified - just show total (mixed currencies)
    format_decimal(total, 2)
  end

  defp format_total_pnl(holdings) do
    total =
      Enum.reduce(holdings, Decimal.new("0"), fn holding, acc ->
        Decimal.add(acc, holding.fifo_pnl_unrealized || Decimal.new("0"))
      end)
    
    format_decimal(total, 2)
  end

  defp pnl_color(holdings) do
    total =
      Enum.reduce(holdings, Decimal.new("0"), fn holding, acc ->
        Decimal.add(acc, holding.fifo_pnl_unrealized || Decimal.new("0"))
      end)
    
    pnl_text_color(total)
  end

  defp pnl_text_color(nil), do: ""
  defp pnl_text_color(pnl) do
    case Decimal.compare(pnl, Decimal.new("0")) do
      :gt -> "text-success"
      :lt -> "text-error"
      :eq -> "text-base-content"
    end
  end
end
