#!/bin/bash
#
# fetch_flex_email.sh — Extract IBKR Flex CSV attachments from Mail.app
#
# Replicates the Automator "HaePortolioMailit" workflow:
# 1. Tell Mail.app to check for new mail (Google account)
# 2. Wait for sync
# 3. Search "Activity Flex" mailbox for messages from last 2 days
# 4. Save .csv attachments to csv_data/
# 5. Skip files that already exist (idempotent)
#
# Usage: bin/fetch_flex_email.sh
# Scheduled via launchd: Mon-Fri 09:30 UTC (11:30 EET)

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
RESULT=$(/usr/bin/osascript - "$CSV_DIR" <<'APPLESCRIPT'
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
    -- Find the Activity Flex mailbox
    set flexMailbox to missing value
    try
        repeat with acct in accounts
            if name of acct contains "Google" or name of acct contains "Gmail" then
                repeat with mb in mailboxes of acct
                    if name of mb is "Activity Flex" then
                        set flexMailbox to mb
                        exit repeat
                    end if
                    -- Check under Harraste parent folder
                    try
                        repeat with submb in mailboxes of mb
                            if name of submb is "Activity Flex" then
                                set flexMailbox to submb
                                exit repeat
                            end if
                        end repeat
                    end try
                    if flexMailbox is not missing value then exit repeat
                end repeat
                if flexMailbox is not missing value then exit repeat
            end if
        end repeat
    on error errMsg
        set end of errorList to "find_mailbox:" & errMsg
    end try

    if flexMailbox is missing value then
        return "error:Could not find Activity Flex mailbox"
    end if

    -- Get messages from last 2 days
    set cutoffDate to (current date) - (2 * days)

    try
        set recentMessages to (every message of flexMailbox whose date received > cutoffDate)
    on error errMsg
        return "error:Could not list messages: " & errMsg
    end try

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
set resultStr to "saved:" & savedCount & ",skipped:" & skippedCount & ",messages:" & (count of recentMessages)
if (count of errorList) > 0 then
    set resultStr to resultStr & ",errors:" & (count of errorList)
    repeat with e in errorList
        set resultStr to resultStr & "|" & e
    end repeat
end if

return resultStr
end run
APPLESCRIPT
)

log "Result: $RESULT"

# Parse result
if [[ "$RESULT" == error:* ]]; then
  log "ERROR: ${RESULT#error:}"
  exit 1
fi

log "=== Completed fetch_flex_email ==="
