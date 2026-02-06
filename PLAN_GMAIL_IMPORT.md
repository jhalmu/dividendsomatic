# Plan: Automated CSV Import

Strategy for automatically importing Interactive Brokers Activity Flex CSV files into Dividendsomatic.

---

## Two Approaches

### Option A: macOS Mail.app (Local-First)

IB sends daily Activity Flex emails to your Gmail. Since you already receive them in Mail.app on this Mac, we can extract attachments locally using AppleScript.

**How it works:**
1. AppleScript searches Mail.app for messages from `noreply@interactivebrokers.com` with "Activity Flex" in subject
2. Extract CSV attachment to a temp directory
3. Feed CSV data to `Portfolio.create_snapshot_from_csv/2`
4. Run on a schedule via Oban or a simple GenServer timer

**Implementation sketch:**

```elixir
defmodule Dividendsomatic.MailApp do
  @applescript """
  tell application "Mail"
    set theMessages to every message of inbox whose ¬
      sender contains "interactivebrokers.com" and ¬
      subject contains "Activity Flex"
    -- extract attachments, save to temp dir
  end tell
  """

  def fetch_recent_csvs(days_back \\ 7) do
    {output, 0} = System.cmd("osascript", ["-e", @applescript])
    parse_attachment_paths(output)
  end
end
```

**Pros:**
- No OAuth setup, no API keys, no Google Cloud Console
- Works immediately on this Mac
- Single-user local app -- perfect fit
- No rate limits or quota concerns

**Cons:**
- macOS only (won't work on Linux server deployment)
- Mail.app must be running and synced
- AppleScript is fragile across macOS updates
- Can't run headless in production

### Option B: Gmail API (Already Implemented)

Full implementation exists in `lib/dividendsomatic/gmail.ex` with Oban worker in `lib/dividendsomatic/workers/gmail_import_worker.ex`.

**Requirements:**
- `GOOGLE_CLIENT_ID` -- from Google Cloud Console
- `GOOGLE_CLIENT_SECRET` -- from Google Cloud Console
- `GOOGLE_REFRESH_TOKEN` -- from OAuth flow

**How it works:**
1. Gmail API searches for IB emails with CSV attachments
2. Downloads and decodes base64url attachment data
3. Extracts report date from email subject
4. Creates snapshot via `Portfolio.create_snapshot_from_csv/2`
5. Oban schedules recurring imports

**Pros:**
- Production-ready, works on any server
- Oban scheduling with retries and error handling
- Already fully implemented and tested

**Cons:**
- OAuth setup is complex (Google Cloud Console project, consent screen, scopes)
- Requires storing refresh token securely
- Google API quotas (generous but exist)

---

## Recommendation

**Phase 1 (Now):** Try Mail.app approach for local development. Quick to build, no OAuth friction.

**Phase 2 (Production):** Use Gmail API when deploying to a server. The implementation already exists.

**Both approaches share** the same downstream code: `Portfolio.create_snapshot_from_csv/2` handles all the actual import logic regardless of where the CSV comes from.

---

## Implementation Priority

1. Create `Dividendsomatic.MailApp` module with AppleScript integration
2. Add a mix task: `mix import.mail` to trigger Mail.app import
3. Test with real emails on this Mac
4. For production: configure Gmail OAuth credentials and enable Oban worker

---

## Related Files

- `lib/dividendsomatic/gmail.ex` -- Gmail API implementation
- `lib/dividendsomatic/workers/gmail_import_worker.ex` -- Oban worker
- `lib/mix/tasks/import_csv.ex` -- Manual CSV import task
- `lib/dividendsomatic/portfolio.ex` -- `create_snapshot_from_csv/2`
