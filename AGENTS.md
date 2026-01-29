# AGENTS.MD - Dividendsomatic Project Guidelines

This is a Phoenix LiveView application for portfolio tracking.

## Core Principles

### Simplicity First
- **No megalomania**: Build features that are actually needed
- **Complete features**: Finish one thing before starting another
- **Test immediately**: No deferred testing

### Code Quality
- `mix format` before every commit
- Use Context7 MCP for latest library docs
- Follow Elixir conventions (snake_case, pattern matching)

## Project Guidelines

### HTTP Requests
Use `:req` (Req) library - already included
Avoid: `:httpoison`, `:tesla`, `:httpc`

### CSV Parsing
Use `NimbleCSV` - lightweight, fast
Pattern: parse → validate → insert batch

### Session Workflow

#### Starting
1. Read MEMO.md (latest session notes)
2. Check what needs to be done

#### During
- Work systematically
- Test as you go: `mix test`
- Keep changes small and focused

#### Ending
1. Update MEMO.md with timestamp and summary
2. Run `mix test` 
3. Commit with clear message
4. Push to preserve work

## Architecture

### Contexts
- **Portfolio** - Snapshots, holdings, CSV import

### No Scoping
Single-user app, no authentication needed

### Database Design
- Snapshots: One per report date
- Holdings: Many per snapshot
- Keep raw CSV for audit

## Phoenix/LiveView Patterns

### LiveView Components
```elixir
# Use function components
def portfolio_card(assigns) do
  ~H"""
  <div class="card">
    <%= @content %>
  </div>
  """
end
```

### Forms
Use `to_form/2`, access fields with `@form[:field]`

### Navigation
`<.link navigate={...}>` (not deprecated `live_redirect`)

## DaisyUI Usage

Maximize DaisyUI components:
- `btn`, `btn-primary`, `btn-ghost`
- `card`, `card-body`
- `table`, `table-zebra`  
- `stats`, `stat`
- `badge`

Use design tokens from Homesite when needed:
- `[var(--space-md)]` for spacing
- `[var(--text-base)]` for typography

## Testing

```bash
mix test              # Run tests
mix format            # Format code
```

## Git Workflow

```bash
git add .
git commit -m "feat: description"
git push
```

Commit format: `feat:`, `fix:`, `docs:`, `refactor:`

## Key Design Decisions

1. **Snapshot architecture**: Immutable daily records
2. **Raw CSV storage**: Audit trail preservation  
3. **DaisyUI first**: Leverage component library
4. **Arrow navigation**: Simple date browsing
5. **No authentication**: Local single-user app

## File Organization

```
lib/dividendsomatic/
  portfolio/
    snapshot.ex
    holding.ex
  portfolio.ex          # Context

lib/dividendsomatic_web/
  live/
    portfolio_live.ex   # Main LiveView
```

## Remember

- Read Context7 docs before using new library features
- Test after each significant change
- Keep functions small and focused
- Use pattern matching over conditionals
- Commit early, commit often
