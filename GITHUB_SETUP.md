# GitHub Setup Instructions

## 1. Create GitHub Repository

1. Visit https://github.com/new
2. Repository name: `dividendsomatic`
3. Description: "Portfolio and dividend tracking system for Interactive Brokers CSV statements"
4. Public repository
5. Do NOT initialize with README (we already have one)
6. Click "Create repository"

## 2. Push to GitHub

```bash
cd /Users/juha/Library/CloudStorage/Dropbox/Projektit/Elixir/dividendsomatic

# Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/dividendsomatic.git

# Push
git branch -M main
git push -u origin main
```

## 3. Create Issues

After pushing, create these issues on GitHub:

### Issue 1: Gmail Auto-Import with Oban
**Labels:** enhancement, automation

**Description:**
Implement automatic daily CSV import from Gmail using Oban worker.

**Tasks:**
- [ ] Create Oban worker for Gmail polling
- [ ] Use Gmail MCP to search for "Activity Flex" emails
- [ ] Extract CSV attachments
- [ ] Import to database automatically
- [ ] Schedule daily at 6 AM
- [ ] Add error handling and notifications

**Files to create:**
- `lib/dividendsomatic/workers/gmail_import_worker.ex`
- Update `config/config.exs` with Oban cron

---

### Issue 2: Portfolio Charts with Contex
**Labels:** enhancement, visualization

**Description:**
Add interactive charts to visualize portfolio performance.

**Tasks:**
- [ ] Add Contex dependency
- [ ] Line chart: Portfolio value over time
- [ ] Pie chart: Holdings by asset type
- [ ] Bar chart: P&L by symbol
- [ ] Make charts responsive with DaisyUI cards

**Files to create:**
- `lib/dividendsomatic_web/live/portfolio_live/charts_component.ex`
- Update `mix.exs` with `:contex`

---

### Issue 3: Dividend Tracking
**Labels:** enhancement, feature

**Description:**
Track dividends and project future dividend income.

**Tasks:**
- [ ] Create `dividends` table (symbol, ex_date, pay_date, amount)
- [ ] Add dividend import from CSV or manual entry
- [ ] Calculate projected annual dividend income
- [ ] Show upcoming dividends calendar
- [ ] Historical dividend view

**Files to create:**
- `priv/repo/migrations/*_create_dividends.exs`
- `lib/dividendsomatic/portfolio/dividend.ex`
- Update Portfolio context

---

### Issue 4: Deploy to Production
**Labels:** deployment, infrastructure

**Description:**
Deploy to Fly.io or similar platform.

**Tasks:**
- [ ] Switch from SQLite to PostgreSQL
- [ ] Create Dockerfile
- [ ] Configure environment variables
- [ ] Set up CI/CD with GitHub Actions
- [ ] Deploy to Fly.io
- [ ] Configure custom domain (optional)

---

### Issue 5: Testing Suite
**Labels:** testing, quality

**Description:**
Add comprehensive test coverage.

**Tasks:**
- [ ] Context tests (Portfolio)
- [ ] LiveView tests
- [ ] CSV parser tests
- [ ] Integration tests
- [ ] Set up GitHub Actions for CI

---

### Issue 6: Multi-Currency Support
**Labels:** enhancement, feature

**Description:**
Better handling of multiple currencies with conversion.

**Tasks:**
- [ ] Add currency conversion rates
- [ ] Display total value in base currency (EUR)
- [ ] Currency selector in UI
- [ ] Historical conversion rates

---

### Issue 7: Performance Optimization
**Labels:** performance, optimization

**Description:**
Optimize queries and add caching.

**Tasks:**
- [ ] Add database indexes
- [ ] Cache summary calculations
- [ ] Optimize N+1 queries
- [ ] Add pagination for large holdings

