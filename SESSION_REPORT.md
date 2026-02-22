# Session Report — 2026-02-22 (Production Deployment Infrastructure)

## Overview

Added full production deployment infrastructure: Dockerfile, Docker Compose, GitHub Actions CI/CD, Caddy reverse proxy config, and release tooling. Follows the same pattern as the homesite deployment on Hetzner VPS.

## Changes

### Step 1: Release Infrastructure
- `lib/dividendsomatic/release.ex` — migration module for production releases (no Mix available)
- `rel/overlays/bin/server` — startup script (`PHX_SERVER=true`)
- `rel/overlays/bin/migrate` — migration script for Docker exec

### Step 2: Dockerfile
- Multi-stage build: `hexpm/elixir:1.19.4-erlang-28.2.1` builder → `debian:trixie-slim` runner
- Follows standard Phoenix release template
- Installs hex+rebar, compiles deps, builds assets, creates release
- Runner stage: minimal runtime deps (libstdc++6, openssl, libncurses6, locales, ca-certificates)
- Runs as `nobody` user

### Step 3: Docker Compose (Production)
- `docker-compose.prod.yml` — app + Postgres 17 Alpine
- External `caddy` network (shared with homesite)
- Health check on Postgres before app starts
- All secrets via environment variables from `.env`

### Step 4: .dockerignore
- Excludes tests, CSV data, env files, build artifacts, editor files

### Step 5: Production Config
- Added `force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]` to `config/prod.exs`

### Step 6: GitHub Actions CI/CD
- 5-job pipeline: quality → security → test → build-and-push → deploy
- **quality**: format, compile --warnings-as-errors, credo --strict
- **security**: sobelow, deps.audit
- **test**: PostgreSQL 17 service, mix test
- **build-and-push**: Docker build → GHCR (on main push only)
- **deploy**: SSH to Hetzner, pull, up, migrate, prune (on main push only)

### Step 7: Caddyfile
- Reverse proxy for `dividends-o-matic.com`
- Security headers (HSTS, X-Content-Type-Options, X-Frame-Options, etc.)
- www → non-www redirect
- Access logging with rotation

### Step 8: .env.example
- Template for all required production secrets

## Verification Summary

### Test Suite
- **679 tests, 0 failures** (25 excluded: playwright/external/auth)
- `MIX_ENV=prod mix compile` — clean compilation
- Credo: 34 pre-existing issues (mix task complexity), 0 new issues

### Data Validation (`mix validate.data`)
- Total checked: 2178, Issues found: 679
  - duplicate: 282 (warning) — cross-source ISIN duplicates
  - isin_currency_mismatch: 240 (info) — Canadian stocks traded in USD
  - inconsistent_amount: 154 (info) — ETF distribution variance
  - suspicious_amount: 1 (warning) — OPP $207.45 per share
  - mixed_amount_types: 2 (info) — ORC, RIV have both per_share and total_net
- Portfolio balance: ⚠ WARNING (15.90% gap, margin account)

### GitHub Issues
- No open issues (all #1-#22 closed)

## Files Changed

### New files (9)
- `lib/dividendsomatic/release.ex`
- `rel/overlays/bin/server`
- `rel/overlays/bin/migrate`
- `Dockerfile`
- `.dockerignore`
- `docker-compose.prod.yml`
- `.github/workflows/deploy.yml`
- `Caddyfile`
- `.env.example`

### Modified files (1)
- `config/prod.exs` — added force_ssl

## Server Setup (One-Time, Manual)

1. DNS: Point `dividends-o-matic.com` A record to VPS IP
2. Create `/opt/dividendsomatic` with `.env` and `docker-compose.prod.yml`
3. Ensure `docker network create caddy` exists
4. Add Caddyfile site block to shared Caddy config
5. GitHub Actions secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`
