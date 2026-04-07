#!/usr/bin/env bash
# Idle work cron script — triggers the Kernel to pick up low-risk queued tasks
# during off-hours or idle periods.
#
# Install with crontab:
#   # Every hour during off-hours (7pm-7am) and weekends
#   0 19-23,0-7 * * * /path/to/project/.claude/cron/idle_work.sh /path/to/project
#   0 * * * 0,6 /path/to/project/.claude/cron/idle_work.sh /path/to/project
#
#   # Or simply every 4 hours overnight
#   0 20,0,4 * * * /path/to/project/.claude/cron/idle_work.sh /path/to/project
#
# Usage: idle_work.sh <project_root>

PROJECT_ROOT="${1:-.}"
INBOX="$PROJECT_ROOT/.claude/events/inbox.jsonl"

if [ ! -f "$INBOX" ]; then
    echo "ERROR: Inbox not found at $INBOX" >&2
    echo "Usage: idle_work.sh /path/to/project" >&2
    exit 1
fi

TIMESTAMP=$(date -Iseconds)
ID="idle_work_$(date +%s)"

echo "{\"id\":\"$ID\",\"timestamp\":\"$TIMESTAMP\",\"role\":\"system\",\"content\":\"/idle-work\"}" >> "$INBOX"
