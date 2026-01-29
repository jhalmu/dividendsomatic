# Deployment Guide - Dividendsomatic

Guide for deploying to production (Hetzner Cloud + Docker + Caddy).

## Prerequisites

- Hetzner Cloud account
- Domain name (optional but recommended)
- PostgreSQL database
- Gmail account for CSV imports

## Option 1: Docker Compose (Recommended)

### 1. Server Setup

```bash
# On your Hetzner server
apt update && apt upgrade -y
apt install -y docker.io docker-compose git

# Clone repo
git clone https://github.com/jhalmu/dividendsomatic.git
cd dividendsomatic
```

### 2. Create docker-compose.yml

```yaml
version: '3.8'

services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: dividendsomatic
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: dividendsomatic_prod
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  app:
    build: .
    depends_on:
      - db
    environment:
      DATABASE_URL: postgresql://dividendsomatic:${DB_PASSWORD}@db/dividendsomatic_prod
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      PHX_HOST: ${DOMAIN}
      PORT: 4000
    ports:
      - "4000:4000"
    restart: unless-stopped

  caddy:
    image: caddy:2-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

volumes:
  postgres_data:
  caddy_data:
  caddy_config:
```

### 3. Create Dockerfile

```dockerfile
FROM hexpm/elixir:1.15.0-erlang-26.0-alpine-3.18.0 AS build

# Install build dependencies
RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy assets
COPY assets assets
RUN cd assets && npm install

# Copy rest of application
COPY config config
COPY lib lib
COPY priv priv

# Compile assets
RUN mix assets.deploy

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.18 AS app

RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

# Copy release from build stage
COPY --from=build /app/_build/prod/rel/dividendsomatic ./

ENV HOME=/app

CMD ["bin/dividendsomatic", "start"]
```

### 4. Create Caddyfile

```
{$DOMAIN:localhost} {
    reverse_proxy app:4000
}
```

### 5. Environment Variables

Create `.env` file:

```bash
# Generate with: mix phx.gen.secret
SECRET_KEY_BASE=your_secret_key_here

# Your domain or IP
DOMAIN=dividendsomatic.example.com

# Database password
DB_PASSWORD=your_secure_password_here
```

### 6. Deploy

```bash
# Load environment variables
set -a; source .env; set +a

# Build and start
docker-compose up -d

# Run migrations
docker-compose exec app bin/dividendsomatic eval "Dividendsomatic.Release.migrate"
```

## Option 2: Manual Deployment

### 1. PostgreSQL Setup

```bash
# On Ubuntu/Debian
apt install postgresql postgresql-contrib

sudo -u postgres psql
CREATE DATABASE dividendsomatic_prod;
CREATE USER dividendsomatic WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE dividendsomatic_prod TO dividendsomatic;
\q
```

### 2. Application Setup

```bash
# Install Elixir
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
dpkg -i erlang-solutions_2.0_all.deb
apt update
apt install esl-erlang elixir

# Clone and build
git clone https://github.com/jhalmu/dividendsomatic.git
cd dividendsomatic

# Setup
mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Run migrations
_build/prod/rel/dividendsomatic/bin/dividendsomatic eval "Dividendsomatic.Release.migrate"

# Start
_build/prod/rel/dividendsomatic/bin/dividendsomatic start
```

### 3. Systemd Service

Create `/etc/systemd/system/dividendsomatic.service`:

```ini
[Unit]
Description=Dividendsomatic Phoenix App
After=network.target postgresql.service

[Service]
Type=simple
User=dividendsomatic
WorkingDirectory=/opt/dividendsomatic
Environment=PORT=4000
Environment=MIX_ENV=prod
Environment=DATABASE_URL=postgresql://dividendsomatic:password@localhost/dividendsomatic_prod
Environment=SECRET_KEY_BASE=your_secret_key
ExecStart=/opt/dividendsomatic/_build/prod/rel/dividendsomatic/bin/dividendsomatic start
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
systemctl daemon-reload
systemctl enable dividendsomatic
systemctl start dividendsomatic
```

## Configuration

### Environment Variables

Required:
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY_BASE` - Phoenix secret (generate with `mix phx.gen.secret`)
- `PHX_HOST` - Your domain name

Optional:
- `PORT` - Port to listen on (default: 4000)
- `POOL_SIZE` - Database pool size (default: 10)

### Release Configuration

Update `config/runtime.exs` for production settings.

## Gmail Integration

After deployment, configure Gmail MCP:

1. Enable Gmail API in Google Cloud Console
2. Create OAuth credentials
3. Set environment variables:
   ```bash
   GMAIL_CLIENT_ID=your_client_id
   GMAIL_CLIENT_SECRET=your_client_secret
   ```

## Monitoring

### Health Check

```bash
curl https://your-domain.com/
```

### Logs

```bash
# Docker
docker-compose logs -f app

# Systemd
journalctl -u dividendsomatic -f

# Application logs
tail -f /app/log/prod.log
```

### Database

```bash
# Docker
docker-compose exec db psql -U dividendsomatic dividendsomatic_prod

# Manual
sudo -u postgres psql dividendsomatic_prod
```

## Backup

### Database Backup

```bash
# Docker
docker-compose exec db pg_dump -U dividendsomatic dividendsomatic_prod > backup.sql

# Manual
pg_dump -U dividendsomatic dividendsomatic_prod > backup.sql
```

### Restore

```bash
# Docker
docker-compose exec -T db psql -U dividendsomatic dividendsomatic_prod < backup.sql

# Manual
psql -U dividendsomatic dividendsomatic_prod < backup.sql
```

## Updating

```bash
# Pull latest code
git pull origin main

# Docker
docker-compose down
docker-compose build
docker-compose up -d
docker-compose exec app bin/dividendsomatic eval "Dividendsomatic.Release.migrate"

# Manual
mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
_build/prod/rel/dividendsomatic/bin/dividendsomatic eval "Dividendsomatic.Release.migrate"
systemctl restart dividendsomatic
```

## SSL/HTTPS

Caddy handles SSL automatically with Let's Encrypt. Just:
1. Point your domain to the server IP
2. Wait for DNS propagation
3. Caddy will automatically get SSL certificate

## Troubleshooting

### Port conflicts
```bash
lsof -i :4000
kill -9 <PID>
```

### Database connection issues
```bash
# Check PostgreSQL is running
systemctl status postgresql

# Check connectivity
psql $DATABASE_URL
```

### Oban jobs not running
```bash
# Check Oban status in IEx
bin/dividendsomatic remote
Oban.check_queue(queue: :default)
```

## Security Checklist

- [ ] Change default passwords
- [ ] Use environment variables for secrets
- [ ] Enable firewall (ufw)
- [ ] Set up SSL/HTTPS
- [ ] Regular backups
- [ ] Keep dependencies updated
- [ ] Monitor logs

## Performance Tuning

- Increase database pool size for high traffic
- Add Redis for caching (optional)
- Use CDN for assets
- Enable gzip compression in Caddy
- Optimize database indexes

---

For more details, see:
- [Phoenix Deployment Guide](https://hexdocs.pm/phoenix/deployment.html)
- [Oban Deployment](https://hexdocs.pm/oban/Oban.html#module-deployment)
