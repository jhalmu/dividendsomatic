# Deployment Guide - Dividendsomatic

## 🚀 Quick Deploy Options

### Option 1: Fly.io (Recommended)
```bash
# Install flyctl
brew install flyctl  # or: curl -L https://fly.io/install.sh | sh

# Login
fly auth login

# Initialize app
fly launch

# Set secrets
fly secrets set DATABASE_URL=postgres://...
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)

# Deploy
fly deploy

# Check status
fly status
fly logs
```

### Option 2: Railway.app
```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Initialize
railway init

# Add PostgreSQL
railway add -d postgres

# Deploy
railway up

# Set environment
railway variables set SECRET_KEY_BASE=$(mix phx.gen.secret)
```

### Option 3: Gigalixir
```bash
# Install CLI
pip install gigalixir

# Login
gigalixir login

# Create app
gigalixir create

# Add PostgreSQL
gigalixir pg:create --free

# Deploy
git push gigalixir main
```

## 🐘 PostgreSQL Setup

### Migration from SQLite

**1. Update mix.exs:**
```elixir
# Replace:
{:ecto_sqlite3, "~> 0.18"}

# With:
{:postgrex, "~> 0.19"}
```

**2. Update config/runtime.exs:**
```elixir
config :dividendsomatic, Dividendsomatic.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  socket_options: maybe_ipv6
```

**3. Run migration:**
```bash
mix deps.get
MIX_ENV=prod mix ecto.create
MIX_ENV=prod mix ecto.migrate
```

## 🔐 Environment Variables

**Required:**
```bash
SECRET_KEY_BASE=        # Generate with: mix phx.gen.secret
DATABASE_URL=           # PostgreSQL connection string
PHX_HOST=              # Your domain (e.g., dividendsomatic.fly.dev)
```

**Optional:**
```bash
PORT=4000              # Server port
POOL_SIZE=10           # Database pool size
```

## 📦 Build & Release

### Local Production Build
```bash
# Install dependencies
mix deps.get --only prod

# Compile assets
mix assets.deploy

# Create release
MIX_ENV=prod mix release

# Run
_build/prod/rel/dividendsomatic/bin/dividendsomatic start
```

### Docker (Alternative)
```dockerfile
# Dockerfile
FROM hexpm/elixir:1.15-erlang-26-alpine AS build

WORKDIR /app

RUN apk add --no-cache build-base git nodejs npm

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
COPY lib lib
COPY priv priv
COPY assets assets

RUN mix assets.deploy
RUN MIX_ENV=prod mix release

FROM alpine:3.18
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app
COPY --from=build /app/_build/prod/rel/dividendsomatic ./

CMD ["/app/bin/dividendsomatic", "start"]
```

```bash
# Build
docker build -t dividendsomatic .

# Run
docker run -p 4000:4000 \
  -e DATABASE_URL=$DATABASE_URL \
  -e SECRET_KEY_BASE=$SECRET_KEY_BASE \
  dividendsomatic
```

## 🔧 Production Checklist

**Before deploying:**
- [ ] PostgreSQL database ready
- [ ] SECRET_KEY_BASE generated
- [ ] Environment variables set
- [ ] Assets compiled (`mix assets.deploy`)
- [ ] Database migrated
- [ ] Health check endpoint working

**After deploying:**
- [ ] SSL/TLS certificate active
- [ ] Database backed up regularly
- [ ] Monitoring configured
- [ ] Log aggregation set up
- [ ] Error tracking enabled (e.g., Sentry)

## 📊 Monitoring

### Application Metrics
```elixir
# Add to mix.exs
{:telemetry_metrics_prometheus, "~> 1.1"}

# Phoenix Dashboard already included
# Visit: /dev/dashboard (dev) or /admin/dashboard (prod)
```

### Health Check Endpoint
```elixir
# Add to router.ex
get "/health", HealthController, :check

# lib/dividendsomatic_web/controllers/health_controller.ex
defmodule DividendsomaticWeb.HealthController do
  use DividendsomaticWeb, :controller

  def check(conn, _params) do
    # Check database
    case Repo.query("SELECT 1") do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> 
        conn
        |> put_status(503)
        |> json(%{status: "error", message: "database unavailable"})
    end
  end
end
```

## 🔄 CI/CD

### GitHub Actions
```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3
      
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: 1.15
          otp-version: 26
      
      - run: mix deps.get
      - run: mix test
      - run: mix format --check-formatted
```

## 🚨 Troubleshooting

**Common Issues:**

1. **Port already in use:**
   ```bash
   PORT=4001 mix phx.server
   ```

2. **Database connection failed:**
   - Check DATABASE_URL format
   - Verify PostgreSQL is running
   - Test connection: `psql $DATABASE_URL`

3. **Assets not compiling:**
   ```bash
   cd assets && npm install && cd ..
   mix assets.deploy
   ```

4. **Secret key error:**
   ```bash
   export SECRET_KEY_BASE=$(mix phx.gen.secret)
   ```

## 📈 Performance Tips

1. **Database Connection Pool:**
   ```elixir
   # config/runtime.exs
   pool_size: 10  # Adjust based on load
   ```

2. **Asset CDN:**
   - Use CloudFlare or similar
   - Configure in `config/prod.exs`

3. **Caching:**
   - Add Redis for session storage
   - Cache expensive queries

4. **Background Jobs:**
   - Use Oban for CSV imports
   - Schedule during low-traffic hours

## 🛡️ Security

**Production Security:**
- [ ] Force SSL (already configured in endpoint.ex)
- [ ] Rate limiting (add with PlugAttack)
- [ ] CSRF protection (enabled by default)
- [ ] SQL injection protection (Ecto parameterizes)
- [ ] XSS protection (Phoenix.HTML escapes)

**Add rate limiting:**
```elixir
# mix.exs
{:plug_attack, "~> 0.4"}

# endpoint.ex
plug PlugAttack.Storage.Ets,
  clean_period: 60_000

plug PlugAttack,
  throttle: ["by_ip", [period: 60_000, limit: 100]]
```

## 📞 Support

If deployment fails:
1. Check logs: `fly logs` / `railway logs` / `gigalixir logs`
2. Verify environment variables
3. Test locally: `MIX_ENV=prod mix phx.server`
4. Check database connectivity
5. Review Phoenix deployment docs: https://hexdocs.pm/phoenix/deployment.html

---

**Version:** 1.0  
**Last Updated:** 2026-01-29  
**Tested On:** Fly.io, Railway
