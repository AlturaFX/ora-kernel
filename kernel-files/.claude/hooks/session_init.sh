#!/usr/bin/env bash
# SessionStart hook: Clears temporary state for a fresh session.
# Preserves cross-session data (postgres, node specs) but clears
# runtime state (loop detector logs, status files, counters).

# Clean up temp state from prior sessions
if [ -d "/tmp/claude-kernel" ]; then
    # Remove all session directories (each session gets fresh state per Axiom 6)
    find /tmp/claude-kernel -mindepth 1 -maxdepth 1 -type d -mmin +60 -exec rm -rf {} \; 2>/dev/null
fi

exit 0
