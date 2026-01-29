# Git Push Instructions

## 1. Create GitHub Repository

Visit: https://github.com/new

**Settings:**
- Repository name: `dividendsomatic`
- Description: `Portfolio and dividend tracking for Interactive Brokers CSV`
- Visibility: **Public**
- ❌ Do NOT initialize with README (already exists)
- ❌ Do NOT add .gitignore (already exists)
- ❌ Do NOT add license (yet)

Click **Create repository**

## 2. Connect Local Repo to GitHub

```bash
cd /Users/juha/Library/CloudStorage/Dropbox/Projektit/Elixir/dividendsomatic

# Add remote (replace <YOUR_USERNAME> with your GitHub username)
git remote add origin git@github.com:<YOUR_USERNAME>/dividendsomatic.git

# Verify remote
git remote -v

# Push to GitHub
git branch -M main
git push -u origin main
```

## 3. Create GitHub Issues

After pushing, visit your repository and create issues from `GITHUB_ISSUES.md`:

### Close completed issues immediately:
- ✅ #1 - Project Setup
- ✅ #2 - Database Schema
- ✅ #3 - Portfolio Context
- ✅ #4 - CSV Import
- ✅ #5 - LiveView Portfolio Viewer

### Create as open issues:
- #6 - Gmail Integration (Priority: HIGH)
- #7 - Oban Background Jobs (Priority: HIGH)
- #8 - Charts & Visualizations (Priority: MEDIUM)
- #9 - Dividend Tracking (Priority: MEDIUM)
- #10 - Enhanced UI Features (Priority: LOW)
- #11 - Authentication (Priority: LOW)
- #12 - Testing (Priority: MEDIUM)
- #13 - Production Deployment (Priority: HIGH)
- #14 - Documentation (Priority: MEDIUM)

## 4. Example: Creating Issue #6

**Title:** Gmail Integration

**Description:**
```markdown
Automate CSV imports from Gmail "Activity Flex" emails.

**Tasks:**
- [ ] Gmail MCP server integration
- [ ] Search for "Activity Flex" emails
- [ ] Download CSV attachments
- [ ] Parse filename for date
- [ ] Auto-import to database
- [ ] Error handling (duplicate dates, missing files)

**Priority:** HIGH
**Estimated:** 3-4 hours
```

**Labels:** `enhancement`, `high-priority`

## 5. Verify Push

Visit: https://github.com/<YOUR_USERNAME>/dividendsomatic

You should see:
- ✅ README.md rendered
- ✅ All code files
- ✅ Documentation files
- ✅ Proper .gitignore
- ❌ NO .db files
- ❌ NO .csv files

## Alternative: Using GitHub CLI

If you have `gh` CLI installed and authenticated:

```bash
cd /Users/juha/Library/CloudStorage/Dropbox/Projektit/Elixir/dividendsomatic

# Create repo and push
gh repo create dividendsomatic --public --source=. --remote=origin --push

# Create issues from file (manual for now)
# Visit repository to create issues manually
```

## Troubleshooting

### "Permission denied (publickey)"
```bash
# Check SSH keys
ssh -T git@github.com

# If fails, add SSH key to GitHub:
cat ~/.ssh/id_ed25519.pub
# Copy output and add to GitHub: Settings > SSH and GPG keys
```

### "Remote already exists"
```bash
# Remove old remote
git remote remove origin

# Add correct remote
git remote add origin git@github.com:<YOUR_USERNAME>/dividendsomatic.git
```

### "Branch 'main' does not exist"
```bash
# Check current branch
git branch

# Rename if needed
git branch -M main
```
