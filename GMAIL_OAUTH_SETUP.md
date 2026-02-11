# Gmail OAuth Setup Guide

How to configure Gmail API access for automatic CSV import from Interactive Brokers email attachments.

## 1. Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (e.g., "Dividendsomatic")
3. Select the project

## 2. Enable Gmail API

1. Go to **APIs & Services > Library**
2. Search for "Gmail API"
3. Click **Enable**

## 3. Create OAuth2 Credentials

1. Go to **APIs & Services > Credentials**
2. Click **Create Credentials > OAuth client ID**
3. If prompted, configure the OAuth consent screen first:
   - User Type: **External** (or Internal if using Google Workspace)
   - App name: "Dividendsomatic"
   - Scopes: `https://www.googleapis.com/auth/gmail.readonly`
4. Application type: **Web application**
5. Authorized redirect URIs: `https://developers.google.com/oauthplayground`
6. Copy the **Client ID** and **Client Secret**

## 4. Get Refresh Token via OAuth Playground

1. Go to [OAuth 2.0 Playground](https://developers.google.com/oauthplayground/)
2. Click the gear icon (top right), check **Use your own OAuth credentials**
3. Enter your Client ID and Client Secret
4. In Step 1, enter scope: `https://www.googleapis.com/auth/gmail.readonly`
5. Click **Authorize APIs** and sign in with your Google account
6. In Step 2, click **Exchange authorization code for tokens**
7. Copy the **Refresh token**

## 5. Set Environment Variables

Add to your `.env` file (or export in shell):

```bash
export GMAIL_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GMAIL_CLIENT_SECRET="your-client-secret"
export GOOGLE_REFRESH_TOKEN="your-refresh-token"
```

For production, set these in your deployment config (e.g., Fly.io secrets).

## 6. Test the Integration

```elixir
# Start the app
iex -S mix phx.server

# Test Gmail connection
Dividendsomatic.Gmail.search_activity_flex_emails(max_results: 5)

# Should return {:ok, [%{id: ..., subject: ...}, ...]}

# Test full import
Dividendsomatic.DataIngestion.import_new_from_source(
  Dividendsomatic.DataIngestion.GmailAdapter
)
```

## How It Works

The Gmail adapter:
1. Searches for emails matching "Activity Flex" in the subject
2. Extracts CSV attachments from matching emails
3. Parses the report date from the CSV content
4. Imports new snapshots (skips dates that already exist)

The Oban cron job runs this automatically on weekdays at 12:00.

## Troubleshooting

- **"Gmail OAuth not configured"**: Environment variables are missing
- **Token expired**: Refresh tokens don't expire unless revoked. If issues persist, repeat Step 4
- **No emails found**: Check that IB emails arrive in your Gmail with "Activity Flex" in the subject
- **Rate limits**: Gmail API has generous limits (250 quota units/user/second), unlikely to hit them
