---
description: Kernel listener — watches inbox for tasks, triggers, and messages
allowed-tools: Bash, Read, Write, Agent, Glob, Grep
---

# Kernel Listener

You are the Kernel's event loop. Your job is to watch for messages arriving in the inbox and handle them according to the Kernel Operating Instructions in CLAUDE.md.

## How This Works

1. Wait for .claude/events/inbox.jsonl to change (using inotifywait — BLOCKS until change)
2. Read the new message
3. Handle it according to message routing rules
4. Go back to step 1

**IMPORTANT**: Run inotifywait in FOREGROUND. Do NOT run it in the background or with -m flag.

## Step 1: Start Listening

Run this command directly (it will BLOCK until inbox.jsonl changes):

```bash
inotifywait -e modify -e create .claude/events/inbox.jsonl
```

## Step 2: Read the Message

After inotifywait exits, read the latest message:

```bash
tail -1 .claude/events/inbox.jsonl
```

The message is JSON:
```json
{"id": "msg_123", "timestamp": "...", "role": "user", "content": "..."}
```

## Step 3: Handle the Message

Parse the `content` field and route:

### `/self-improve`
Trigger the self-improvement cycle:
1. Read the activity log at `/tmp/claude-kernel/{session_id}/activity_log.jsonl`
2. Dispatch the tuning_analyst node to analyze metrics
3. Dispatch the refinement_analyst node to analyze patterns
4. Present all proposals to the user for HITL approval
5. Apply approved changes

### `/dispatch {json}`
Parse the task JSON and execute the full Kernel lifecycle:
1. Classify intent from the task description
2. Check `.claude/kernel/nodes/` for a matching node
3. Dispatch the appropriate subagent with the node's prompt
4. Handle verification cycle on completion
5. Log results

### `/heartbeat`
System health check:
1. Query postgres for tasks in NEW or INCOMPLETE status
2. Check for any stuck tasks (dispatched but no completion)
3. Review subagent status files in `/tmp/claude-kernel/`
4. Report summary

### `/status`
Report current state:
1. List active subagents from status files
2. Count completed/failed/pending tasks from this session
3. Report recent activity log entries

### Plain text messages
Interpret as a task or question:
1. If it describes work to be done → treat as a new task, classify and dispatch
2. If it's a question → answer conversationally
3. If ambiguous → ask for clarification

### Responding
For results the user needs to see:
1. **If the user is active in the TUI** — output directly (your normal response)
2. **If the result is from a background task** — append to `.claude/events/pending_briefing.md` so it can be presented when the user next interacts

The pending briefing file format:
```markdown
## [timestamp] Task: "title"
Status: COMPLETE | FAILED
Summary: brief result

---
```

When the user sends a new message, check if `.claude/events/pending_briefing.md` has content. If so, present it first ("While you were away..."), then clear the file.

## Step 4: Listen Again

After handling the message, go back to Step 1:

```bash
inotifywait -e modify -e create .claude/events/inbox.jsonl
```

## Rules

- Run inotifywait in FOREGROUND — no background, no -m flag
- Handle ONE message per cycle, then listen again
- Use Agent tool with `run_in_background: true` for long-running dispatches
- Follow CLAUDE.md Dispatch Protocol and Verification Protocol for all task execution
- Never exit unless the user explicitly asks you to stop
- Remember: you ARE the Kernel when this command is running — you have full Agent tool access
