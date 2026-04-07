#!/usr/bin/env python3
"""
PreToolUse hook: Throttles excessive TaskGet/TaskList polling by the main agent.
Background agents notify on completion — polling is unnecessary.

Exit 0 = allow, Exit 2 = block with status context.
"""
import json
import os
import sys
import time
from pathlib import Path

MAX_POLLS = 2
WINDOW_SECONDS = 60


def main():
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    # Only throttle the main agent (no agent_id = main agent)
    if hook_input.get("agent_id"):
        sys.exit(0)

    session_id = hook_input.get("session_id", "unknown")
    poll_log = Path(f"/tmp/claude-kernel/{session_id}/poll_log")
    poll_log.parent.mkdir(parents=True, exist_ok=True)

    now = time.time()

    # Load recent poll timestamps
    timestamps = []
    if poll_log.exists():
        for line in poll_log.read_text().strip().split("\n"):
            if line.strip():
                try:
                    ts = float(line.strip())
                    if now - ts < WINDOW_SECONDS:
                        timestamps.append(ts)
                except ValueError:
                    continue

    # Record this poll
    timestamps.append(now)
    poll_log.write_text("\n".join(str(t) for t in timestamps) + "\n")

    # Check threshold
    if len(timestamps) > MAX_POLLS:
        # Gather subagent status for context
        status_dir = Path(f"/tmp/claude-kernel/{session_id}")
        status_lines = []
        if status_dir.exists():
            for agent_dir in status_dir.iterdir():
                if agent_dir.is_dir() and agent_dir.name not in ("main",):
                    status_file = agent_dir / "status.json"
                    if status_file.exists():
                        try:
                            status = json.loads(status_file.read_text())
                            phase = status.get("phase", "unknown")
                            start = status.get("start_time", "unknown")
                            agent_type = status.get("agent_type", "")
                            elapsed = ""
                            if isinstance(start, (int, float)):
                                elapsed = f" ({int(now - start)}s ago)"
                            status_lines.append(
                                f"  - Agent {agent_dir.name[:8]}... [{agent_type}]: {phase}{elapsed}"
                            )
                        except (json.JSONDecodeError, OSError):
                            continue

        context = "\n".join(status_lines) if status_lines else "  No active subagents tracked."

        msg = (
            f"POLLING THROTTLED: You have checked task status {len(timestamps)} times "
            f"in the last {WINDOW_SECONDS} seconds.\n\n"
            f"Current subagent status:\n{context}\n\n"
            "Background agents will notify you automatically when they complete. "
            "Do not poll — continue with other work or wait for notifications."
        )
        print(msg, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
