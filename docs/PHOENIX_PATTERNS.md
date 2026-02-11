# Phoenix Patterns Reference

Key rules from Phoenix, LiveView, Ecto, and HEEx usage-rules. These are extracted from `deps/phoenix/usage-rules/` and represent framework best practices.

## LiveView

### Streams for Collections

Always use streams for rendering collections of items:

```elixir
# Mount
def mount(_params, _session, socket) do
  {:ok, stream(socket, :items, fetch_items())}
end

# Template
<div id="items" phx-update="stream">
  <div :for={{dom_id, item} <- @streams.items} id={dom_id}>
    <%= item.name %>
  </div>
</div>
```

- Never use `Enum.filter/reject` on streams -- refetch and reset instead
- Every streamed item needs a unique DOM id

### Navigation

Never use deprecated `live_redirect`/`live_patch`:

```elixir
# Template links
<.link navigate={~p"/stocks/#{symbol}"}>View</.link>
<.link patch={~p"/portfolio/#{date}"}>Go to date</.link>

# Programmatic navigation
push_navigate(socket, to: ~p"/stocks/#{symbol}")
push_patch(socket, to: ~p"/portfolio/#{date}")
```

### Forms

Use `to_form/2` -- never access changeset directly in template:

```elixir
# In LiveView
socket = assign(socket, :form, to_form(changeset))

# In template
<.form for={@form} phx-submit="save">
  <.input field={@form[:name]} label="Name" />
</.form>
```

### Push Events

Always push and rebind socket:

```elixir
socket =
  socket
  |> push_event("highlight", %{id: id})
  |> assign(:highlighted, id)
```

## HEEx Templates

### Class Attributes

Use list syntax for conditional classes:

```heex
<div class={["base-class", @active && "active", @error && "text-error"]}>
```

### No `Enum.each` -- Use Comprehensions

```heex
<%!-- WRONG --%>
<% Enum.each(@items, fn item -> %>
  <div><%= item.name %></div>
<% end) %>

<%!-- RIGHT --%>
<div :for={item <- @items}>
  <%= item.name %>
</div>
```

### Unique DOM IDs

Always add unique DOM IDs to key elements for LiveView diffing.

### Attribute Interpolation

```heex
<%!-- Use {expression} for attributes --%>
<div id={"item-#{@id}"} class={@class}>

<%!-- Use <%= %> for body content --%>
<p><%= @content %></p>
```

## Ecto

### Preload Associations

Always preload when accessing associations in templates:

```elixir
def list_snapshots do
  PortfolioSnapshot
  |> order_by([s], desc: s.report_date)
  |> preload(:holdings)
  |> Repo.all()
end
```

### Changeset Field Access

Use `get_field/2`, not direct access:

```elixir
# In changeset validations
amount = get_field(changeset, :amount)
```

### Column Types

Use `:string` for both `:string` and `:text` columns. Ecto treats them the same.

### Don't Cast Programmatic Fields

Fields set programmatically (like `user_id`, `snapshot_id`) should not be in `cast/3`:

```elixir
def changeset(holding, attrs) do
  holding
  |> cast(attrs, [:symbol, :quantity, ...])  # user-provided fields
  |> put_change(:snapshot_id, snapshot_id)   # set programmatically
end
```

## Phoenix Router

Be mindful of scope aliases -- don't create duplicate path prefixes:

```elixir
# The scope already adds /api prefix
scope "/api", MyAppWeb.Api do
  get "/users", UserController, :index  # => /api/users (correct)
end
```

## Testing

### LiveView Tests

Use element selectors, not raw HTML:

```elixir
# Good
assert has_element?(view, "#holdings-table")
assert has_element?(view, ".stat-card", "Total Value")
element(view, "#nav-next") |> render_click()

# Avoid
html = render(view)
assert html =~ "<table"  # fragile
```

### Process Testing

Always use `start_supervised!/1` instead of manual start. Never use `Process.sleep/1` -- use `assert_receive` with timeouts.
