# Quick Start Guide

## 1. Clone & Setup

```bash
# Clone repository (after pushing to GitHub)
git clone https://github.com/YOUR_USERNAME/dividendsomatic.git
cd dividendsomatic

# Install dependencies
mix deps.get
mix deps.compile

# Setup database
mix ecto.create
mix ecto.migrate
```

## 2. Import Test Data

```bash
# Import the example CSV (included in repo)
mix import.csv flex.490027.PortfolioForWww.20260128.20260128.csv

# Expected output:
# Importing snapshot for 2026-01-28...
# ✓ Successfully imported 7 holdings
```

## 3. Start Server

```bash
mix phx.server
```

Visit: http://localhost:4000

## 4. What You'll See

**Portfolio Snapshot Page:**
- Summary cards (Holdings, Total Value, P&L)
- Holdings table with all positions
- Navigation buttons (← →)
- Responsive DaisyUI design

**Try:**
- Click arrow buttons to navigate
- Use keyboard: ← → keys
- View different snapshots (if you have multiple)

## 5. Import Your Own Data

### Get CSV from Interactive Brokers

1. Log in to Interactive Brokers
2. Go to Reports → Flex Queries
3. Create "Activity Flex" query:
   - Format: CSV
   - Sections: Portfolio
   - Include all fields
4. Download CSV file

### Import to App

```bash
mix import.csv path/to/your/flex.csv
```

### View in Browser

Refresh http://localhost:4000

## Common Commands

```bash
# Development
mix phx.server              # Start server
mix format                  # Format code
mix compile                 # Check for errors

# Database
mix ecto.create             # Create database
mix ecto.migrate            # Run migrations
mix ecto.reset              # Drop + recreate + migrate
mix ecto.rollback           # Rollback last migration

# Import
mix import.csv file.csv     # Import CSV

# Testing (coming soon)
mix test                    # Run tests
mix test --trace            # Run with detailed output

# Production
mix release                 # Build release
mix assets.deploy           # Compile assets for prod
```

## Project Structure

```
dividendsomatic/
├── lib/
│   ├── dividendsomatic/              # Business logic
│   │   ├── portfolio.ex              # Main context
│   │   └── portfolio/                # Schemas
│   │
│   ├── dividendsomatic_web/          # Web layer
│   │   ├── live/                     # LiveView modules
│   │   │   └── portfolio_live.ex    # Main UI
│   │   └── router.ex                 # Routes
│   │
│   └── mix/tasks/
│       └── import_csv.ex             # CSV import task
│
├── priv/repo/migrations/             # Database migrations
├── test/                             # Tests
├── config/                           # Configuration
└── assets/                           # Frontend assets
```

## Next Steps

1. **Import More Data**
   - Get historical CSV files
   - Import multiple dates
   - Test navigation

2. **Explore Code**
   - Read API.md for API reference
   - Check DEVELOPMENT.md for patterns
   - Review schemas in lib/dividendsomatic/portfolio/

3. **Contribute**
   - Check GITHUB_SETUP.md for issues
   - Pick an issue to work on
   - Submit PR

4. **Deploy**
   - See DEPLOYMENT.md for Fly.io instructions
   - Switch to PostgreSQL
   - Set environment variables

## Troubleshooting

### Port Already in Use
```bash
lsof -ti:4000 | xargs kill -9
mix phx.server
```

### Database Errors
```bash
mix ecto.reset
mix import.csv file.csv
```

### Compilation Errors
```bash
mix clean
mix deps.clean --all
mix deps.get
mix compile
```

### Assets Not Loading
```bash
cd assets
npm install
cd ..
mix assets.build
```

## Learn More

- **Phoenix:** https://hexdocs.pm/phoenix
- **LiveView:** https://hexdocs.pm/phoenix_live_view
- **Ecto:** https://hexdocs.pm/ecto
- **DaisyUI:** https://daisyui.com

## Support

- GitHub Issues: Report bugs and request features
- Documentation: See README.md, API.md, DEVELOPMENT.md
- Interactive Brokers: https://www.interactivebrokers.com

## License

See LICENSE file
