# Deployment Guide

## Fly.io Deployment (Recommended)

### Prerequisites
- Fly.io account: https://fly.io/
- Install flyctl: `brew install flyctl`
- Authenticate: `fly auth login`

### 1. Switch to PostgreSQL

Update `config/runtime.exs`:

```elixir
config :dividendsomatic, Dividendsomatic.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
```

Update `mix.exs`:
```elixir
# Remove: {:ecto_sqlite3, "~> 0.18"}
# Add:
{:ecto_sql, "~> 3.13"},
{:postgrex, "~> 0.17"}
```

### 2. Create Dockerfile

```dockerfile
# Find the latest tags at https://hub.docker.com/_/elixir
ARG ELIXIR_VERSION=1.15.7
ARG OTP_VERSION=26.1.2
ARG DEBIAN_VERSION=bullseye-20231009-slim

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-slim AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git nodejs npm

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy application
COPY config config
COPY lib lib
COPY assets assets
COPY priv priv

# Compile assets
RUN mix assets.deploy

# Compile app
RUN mix compile

# Release
RUN mix release

# Start a new stage
FROM debian:${DEBIAN_VERSION}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales && \
  apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/dividendsomatic ./

USER nobody

CMD ["/app/bin/server"]
```

### 3. Initialize Fly App

```bash
fly launch --name dividendsomatic

# Follow prompts:
# - Region: Choose closest to you
# - PostgreSQL: Yes (create)
# - Redis: No (not needed yet)
```

### 4. Set Secrets

```bash
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set PHX_HOST=dividendsomatic.fly.dev
```

### 5. Deploy

```bash
fly deploy
```

### 6. Run Migrations

```bash
fly ssh console
/app/bin/dividendsomatic eval "Dividendsomatic.Release.migrate"
```

### 7. Access App

```bash
fly open
```

## Environment Variables

Required for production:
- `SECRET_KEY_BASE` - Phoenix secret key
- `DATABASE_URL` - PostgreSQL connection string
- `PHX_HOST` - Your domain
- `POOL_SIZE` - Database pool size (default: 10)

Optional:
- `GMAIL_CLIENT_ID` - For Gmail auto-import
- `GMAIL_CLIENT_SECRET` - For Gmail auto-import

## Health Checks

Add to `config/runtime.exs`:

```elixir
config :dividendsomatic, DividendsomaticWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST"), port: 443],
  http: [
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6]]
  ],
  check_origin: false
```

## Custom Domain

```bash
fly certs add yourdomain.com
fly certs show yourdomain.com
```

Add DNS records as shown.

## Scaling

```bash
# Scale up
fly scale count 2

# Scale memory
fly scale memory 512
```

## Monitoring

View logs:
```bash
fly logs
```

View metrics:
```bash
fly dashboard
```

## Backup Database

```bash
fly postgres backup create -a dividendsomatic-db
fly postgres backup list -a dividendsomatic-db
```

## Rollback

```bash
fly releases
fly releases rollback <version>
```

## Alternative: Heroku

1. Create Heroku app
2. Add PostgreSQL addon
3. Set buildpacks
4. Deploy via git push

See Heroku deployment docs for details.
