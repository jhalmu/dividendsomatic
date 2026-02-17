#!/bin/bash
#
# fetch_flex_email.sh — Extract IBKR Flex CSV attachments from Mail.app
#
# Replicates the Automator "HaePortolioMailit" workflow:
# 1. Tell Mail.app to check for new mail (Google account)
# 2. Wait for sync
# 3. Search Flex mailboxes for messages from last 2 days
#    - "Activity Flex" (Portfolio.csv — daily)
#    - "Dividend Flex" (Dividends.csv — weekly)
#    - "Trades Flex" (Trades.csv — weekly)
#    - "Actions Flex" (Actions.csv — monthly)
# 4. Save .csv attachments to csv_data/
# 5. Skip files that already exist (idempotent)
#
# Usage: bin/fetch_flex_email.sh
# Scheduled via launchd: Mon-Sat 12:00 local (Helsinki)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_DIR="$PROJECT_DIR/csv_data"
LOG_FILE="$PROJECT_DIR/log/fetch_flex.log"

mkdir -p "$CSV_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log "=== Starting fetch_flex_email ==="

# Run AppleScript to fetch CSV attachments from Mail.app
# Write AppleScript to temp file (bash 3.2 heredoc-in-$() bug workaround)
APPLESCRIPT_TMP=$(mktemp /tmp/fetch_flex.XXXXXX)
trap 'rm -f "$APPLESCRIPT_TMP"' EXIT
cat > "$APPLESCRIPT_TMP" <<'APPLESCRIPT'
on run argv
set csvDir to item 1 of argv
set savedCount to 0
set skippedCount to 0
set errorList to {}

tell application "Mail"
    -- Check for new mail on Google account
    try
        repeat with acct in accounts
            if name of acct contains "Google" or name of acct contains "Gmail" then
                check for new mail acct
            end if
        end repeat
    on error errMsg
        set end of errorList to "check_mail:" & errMsg
    end try
end tell

-- Wait for mail sync
delay 30

tell application "Mail"
    -- Search multiple Flex mailboxes for CSV attachments
    set flexMailboxNames to {"Activity Flex", "Dividend Flex", "Trades Flex", "Actions Flex"}
    set allFlexMailboxes to {}

    try
        repeat with acct in accounts
            if name of acct contains "Google" or name of acct contains "Gmail" then
                repeat with mb in mailboxes of acct
                    if name of mb is in flexMailboxNames then
                        set end of allFlexMailboxes to mb
                    end if
                    -- Check under Harraste parent folder
                    try
                        repeat with submb in mailboxes of mb
                            if name of submb is in flexMailboxNames then
                                set end of allFlexMailboxes to submb
                            end if
                        end repeat
                    end try
                end repeat
            end if
        end repeat
    on error errMsg
        set end of errorList to "find_mailbox:" & errMsg
    end try

    if (count of allFlexMailboxes) is 0 then
        return "error:Could not find any Flex mailboxes"
    end if

    -- Get messages from last 2 days across all Flex mailboxes
    set cutoffDate to (current date) - (2 * days)
    set recentMessages to {}

    repeat with flexMailbox in allFlexMailboxes
        try
            set mbMessages to (every message of flexMailbox whose date received > cutoffDate)
            repeat with msg in mbMessages
                set end of recentMessages to msg
            end repeat
        on error errMsg
            set end of errorList to "list_messages:" & errMsg
        end try
    end repeat

    -- Process each message
    repeat with msg in recentMessages
        try
            set attachmentList to every mail attachment of msg
            repeat with att in attachmentList
                set attName to name of att
                if attName ends with ".csv" then
                    set destPath to csvDir & "/" & attName
                    -- Check if file already exists
                    try
                        do shell script "test -f " & quoted form of destPath
                        set skippedCount to skippedCount + 1
                    on error
                        -- File doesn't exist, save it
                        try
                            save att in POSIX file destPath
                            set savedCount to savedCount + 1
                        on error errMsg
                            set end of errorList to "save:" & attName & ":" & errMsg
                        end try
                    end try
                end if
            end repeat
        on error errMsg
            set end of errorList to "msg:" & errMsg
        end try
    end repeat
end tell

-- Return summary
set resultStr to "saved:" & savedCount & ",skipped:" & skippedCount & ",messages:" & (count of recentMessages) & ",mailboxes:" & (count of allFlexMailboxes)
if (count of errorList) > 0 then
    set resultStr to resultStr & ",errors:" & (count of errorList)
    repeat with e in errorList
        set resultStr to resultStr & "|" & e
    end repeat
end if

return resultStr
end run
APPLESCRIPT

RESULT=$(/usr/bin/osascript "$APPLESCRIPT_TMP" "$CSV_DIR")

log "Result: $RESULT"

# Parse result
if [[ "$RESULT" == error:* ]]; then
  log "ERROR: ${RESULT#error:}"
  exit 1
fi

log "=== Completed fetch_flex_email ==="
