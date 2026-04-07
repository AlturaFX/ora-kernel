#!/usr/bin/env python3
"""
PostToolUse hook (Bash): Detects repeated failed commands per agent.
Implements Axiom 5 (Entropy — no blind retries).

Detection:
- Same command + nonzero exit appearing 3+ times in last 12 entries → replanning prompt
- A-B oscillation (two commands alternating, both failing) in last 6 → replanning prompt
- Second detection (cumulative) → HITL escalation

Exit 0 = pass, Exit 2 = block with message to model.
"""
import json
import os
import sys
from pathlib import Path

WINDOW_SIZE = 12
REPEAT_THRESHOLD = 3
OSCILLATION_WINDOW = 6

# Commands that legitimately repeat and should not trigger detection
SKIP_COMMANDS = {
    "inotifywait", "tail", "git status", "git diff", "ls", "echo",
    "cat", "head", "pwd", "date", "wc", "sleep",
}


def get_log_dir(hook_input: dict) -> Path:
    session_id = hook_input.get("session_id", "unknown")
    agent_id = hook_input.get("agent_id", "main")
    log_dir = Path(f"/tmp/claude-kernel/{session_id}/{agent_id}")
    log_dir.mkdir(parents=True, exist_ok=True)
    return log_dir


def should_skip(command: str) -> bool:
    """Check if command starts with a skipped prefix."""
    cmd_start = command.strip().split()[0] if command.strip() else ""
    # Also skip multi-word prefixes
    for skip in SKIP_COMMANDS:
        if command.strip().startswith(skip):
            return True
    return cmd_start in SKIP_COMMANDS


def load_recent(log_file: Path, window: int) -> list:
    """Load last N entries from the log file."""
    if not log_file.exists():
        return []
    lines = log_file.read_text().strip().split("\n")
    lines = [l for l in lines if l.strip()]
    entries = []
    for line in lines[-window:]:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return entries


def detect_repeat(entries: list, command: str) -> int:
    """Count how many times this command appears with nonzero exit in recent entries."""
    count = 0
    for e in entries:
        if e.get("command") == command and e.get("failed", False):
            count += 1
    return count


def detect_oscillation(entries: list) -> bool:
    """Detect A-B-A-B-A-B pattern in last 6 entries, both failing."""
    if len(entries) < OSCILLATION_WINDOW:
        return False
    recent = entries[-OSCILLATION_WINDOW:]
    # All must be failures
    if not all(e.get("failed", False) for e in recent):
        return False
    # Check alternating pattern
    cmds = [e.get("command") for e in recent]
    if len(set(cmds)) != 2:
        return False
    cmd_a, cmd_b = cmds[0], cmds[1]
    if cmd_a == cmd_b:
        return False
    for i, cmd in enumerate(cmds):
        expected = cmd_a if i % 2 == 0 else cmd_b
        if cmd != expected:
            return False
    return True


def main():
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    # Only process Bash tool calls
    if hook_input.get("tool_name") != "Bash":
        sys.exit(0)

    tool_input = hook_input.get("tool_input", {})
    tool_response = hook_input.get("tool_response", {})

    command = tool_input.get("command", "")
    stderr = tool_response.get("stderr", "")
    # Determine if command failed: nonzero exit indicated by stderr or interrupted
    # PostToolUse doesn't give exit code directly, but stderr presence is a signal
    # We also check if the response indicates an error
    interrupted = tool_response.get("interrupted", False)

    if not command:
        sys.exit(0)

    if should_skip(command):
        sys.exit(0)

    # Heuristic for failure: stderr is non-empty or command was interrupted
    failed = bool(stderr.strip()) or interrupted

    # Log this command
    log_dir = get_log_dir(hook_input)
    log_file = log_dir / "commands.jsonl"
    escalation_file = log_dir / "escalation_count"

    entry = {
        "command": command,
        "failed": failed,
        "stderr_preview": stderr[:200] if stderr else "",
    }

    with open(log_file, "a") as f:
        f.write(json.dumps(entry) + "\n")

    # Only analyze failures
    if not failed:
        sys.exit(0)

    # Load recent entries for analysis
    entries = load_recent(log_file, WINDOW_SIZE)

    # Check for repeated failures
    repeat_count = detect_repeat(entries, command)
    oscillation = detect_oscillation(entries)

    if repeat_count >= REPEAT_THRESHOLD or oscillation:
        # Check escalation level
        esc_count = 0
        if escalation_file.exists():
            try:
                esc_count = int(escalation_file.read_text().strip())
            except ValueError:
                esc_count = 0

        esc_count += 1
        escalation_file.write_text(str(esc_count))

        if esc_count >= 2:
            # Second detection — HITL escalation
            msg = (
                "HITL ESCALATION: Repeated failure pattern detected for the second time.\n\n"
                f"Command: {command}\n"
                f"Last error: {stderr[:300]}\n\n"
                "You have been unable to resolve this after multiple attempts. "
                "STOP and explain the situation to the user. Present:\n"
                "1. What you were trying to accomplish\n"
                "2. What you tried and why it failed\n"
                "3. What you think the root cause is\n"
                "4. Options for the user to choose from\n"
            )
        else:
            # First detection — replanning prompt
            pattern = "oscillation (alternating between two failing approaches)" if oscillation else f"same command failing {repeat_count} times"
            msg = (
                f"LOOP DETECTED: {pattern}.\n\n"
                f"Command: {command}\n"
                f"Last error: {stderr[:300]}\n\n"
                "STOP. Before trying again (Axiom 5 — no blind retries, Axiom 8 — first principles):\n"
                "1. Re-read the original task to confirm your understanding of the goal\n"
                "2. Analyze WHY this command is failing — what is the root cause?\n"
                "3. What assumptions are you making that might be wrong?\n"
                "4. Devise a fundamentally different approach\n"
                "5. If you cannot identify a different approach, escalate to the user\n"
            )

        print(msg, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
