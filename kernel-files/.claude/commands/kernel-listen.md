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
6. After applying changes, trigger `/write-journal` then `/consolidate` to capture learnings

### `/write-journal`
Write a journal entry for the current session. Dispatch the journal_writer node with:
- The session activity log from `/tmp/claude-kernel/{session_id}/activity_log.jsonl`
- Completed and failed task summaries from postgres
- The current session_id

The journal_writer returns a markdown entry. Write it to `.claude/kernel/journal/YYYY-MM-DD.md` (using today's date). If a file for today already exists, append a session separator (`---`) and the new entry.

### `/consolidate`
Run the "dreaming" cycle — consolidate journal entries into WISDOM.md.

1. Read all journal entries from the last 7 days:
```bash
find .claude/kernel/journal -name "????-??-??.md" -mtime -7
```

2. Read current `.claude/kernel/journal/WISDOM.md`

3. Dispatch the consolidation_analyst node with:
   - All recent journal entry contents
   - Current WISDOM.md content
   - retention_days: 7 (configurable)
   - stale_threshold_days: 14

4. Dispatch the consolidation_analyst_verifier with:
   - The consolidation output
   - Same journal data for cross-checking
   - Previous WISDOM.md

5. If verified COMPLETE:
   - Write the updated WISDOM.md to `.claude/kernel/journal/WISDOM.md`
   - Log the consolidation event to postgres activity_log
   - Write a summary to pending_briefing.md if changes were made

6. If verified FAILED or conflicts detected:
   - Write conflict details to pending_briefing.md for HITL review
   - Do NOT update WISDOM.md until conflicts are resolved

### `/briefing`
Generate a daily project summary and suggested priorities. Query postgres for recent activity then write a structured briefing to `.claude/events/pending_briefing.md`.

**1. Yesterday's activity** — what happened since the last briefing:
```sql
SELECT action, COUNT(*) AS count,
       COUNT(DISTINCT task_id) AS unique_tasks
FROM orch_activity_log
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY action
ORDER BY count DESC;
```

**2. Completed work:**
```sql
SELECT t.task_title, n.name AS node_name,
       t.completed_at, t.retry_count
FROM orch_tasks t
LEFT JOIN orch_nodes n ON t.node_id = n.id
WHERE t.status = 'COMPLETE'
  AND t.completed_at > NOW() - INTERVAL '24 hours'
ORDER BY t.completed_at DESC;
```

**3. Failed work** — what needs a new approach:
```sql
SELECT t.task_title, n.name AS node_name,
       t.retry_count, t.max_retries,
       t.result_data->>'error' AS last_error
FROM orch_tasks t
LEFT JOIN orch_nodes n ON t.node_id = n.id
WHERE t.status = 'FAILED'
  AND t.updated_at > NOW() - INTERVAL '24 hours'
ORDER BY t.updated_at DESC;
```

**4. Pending work** — what's queued and ready:
```sql
SELECT t.task_title, t.status, t.budget_size, t.created_at,
       t.is_awaiting_human
FROM orch_tasks t
WHERE t.status IN ('NEW', 'INCOMPLETE', 'UNVERIFIED')
ORDER BY
  CASE t.budget_size
    WHEN 'S' THEN 1 WHEN 'M' THEN 2
    WHEN 'L' THEN 3 WHEN 'XL' THEN 4
  END,
  t.created_at;
```

**5. Self-improvement status:**
```sql
SELECT value FROM orch_config WHERE key = 'self_improvement_threshold';
```
Check `/tmp/claude-kernel/*/completed_count` against the threshold — how close to the next self-improvement cycle?

**6. Any active anomalies** — include the heartbeat anomaly checks.

**Format the briefing as:**

```markdown
# Daily Briefing — {date}

## Yesterday
- {N} tasks completed, {M} failed, {P} still pending
- Notable completions: {list}
- Notable failures: {list with brief error context}

## Today's Priorities
1. {Highest priority pending task — reasoning for why}
2. {Next priority — reasoning}
3. {Next — reasoning}

## Attention Needed
- {Any HITL-awaiting tasks}
- {Any anomalies from heartbeat checks}
- {Self-improvement cycle status}

## System Health
- Node performance: {any nodes with >20% failure rate}
- Budget status: {any tasks near retry limits}
```

**Priority reasoning**: Consider task dependencies (what unblocks other work), budget size (smaller tasks clear backlogs), failure recency (recently failed tasks may have fresh context), and HITL items (humans waiting = highest priority).

### `/dispatch {json}`
Parse the task JSON and execute the full Kernel lifecycle:
1. Classify intent from the task description
2. Check `.claude/kernel/nodes/` for a matching node
3. Dispatch the appropriate subagent with the node's prompt
4. Handle verification cycle on completion
5. Log results

### `/heartbeat`
Proactive system health check. Stay SILENT if nothing is wrong (the HEARTBEAT_OK pattern).

Run these anomaly checks via the postgres MCP:

**1. Stuck tasks** — dispatched but not completed within expected time:
```sql
SELECT id, task_title, status, dispatched_at,
       EXTRACT(EPOCH FROM (NOW() - dispatched_at))/3600 AS hours_stuck
FROM orch_tasks
WHERE dispatched_at IS NOT NULL
  AND status IN ('INCOMPLETE', 'UNVERIFIED')
  AND dispatched_at < NOW() - INTERVAL '2 hours'
ORDER BY dispatched_at;
```

**2. Retry budget warnings** — tasks approaching their retry limit:
```sql
SELECT t.id, t.task_title, t.retry_count, t.max_retries,
       t.retry_count::float / t.max_retries AS exhaustion_pct
FROM orch_tasks t
WHERE t.status NOT IN ('COMPLETE', 'FAILED', 'CANCELLED')
  AND t.retry_count >= t.max_retries - 1
ORDER BY exhaustion_pct DESC;
```

**3. Node failure rate spike** — nodes failing more than 30% in recent tasks:
```sql
SELECT node_name, COUNT(*) AS total,
       COUNT(*) FILTER (WHERE action = 'FAIL') AS failures,
       ROUND(COUNT(*) FILTER (WHERE action = 'FAIL')::numeric / COUNT(*) * 100, 1) AS fail_pct
FROM orch_activity_log
WHERE created_at > NOW() - INTERVAL '24 hours'
  AND action IN ('COMPLETE', 'FAIL')
GROUP BY node_name
HAVING COUNT(*) >= 3
   AND COUNT(*) FILTER (WHERE action = 'FAIL')::numeric / COUNT(*) > 0.3;
```

**4. Orphaned subagents** — check status files for agents started but never completed:
```bash
find /tmp/claude-kernel/ -name status.json -exec grep -l '"phase": "started"' {} \;
```
For each, check if start_time is more than 30 minutes ago.

**Decision logic:**
- If ALL checks return empty results → do nothing (HEARTBEAT_OK). No output, no briefing entry.
- If ANY check returns results → write a summary to `.claude/events/pending_briefing.md` with:
  - Which checks triggered
  - Specific task IDs and names
  - Recommended actions
  - Severity (info / warning / critical)

### `/status`
Report current state:
1. List active subagents from status files
2. Count completed/failed/pending tasks from this session
3. Report recent activity log entries

### Post-completion suggestions
After any task reaches COMPLETE, consider offering a context-aware suggestion. This is NOT a message route — it's behavior you apply after processing any event that completes a task.

**Step 1: Check if suggestions are welcome**
```sql
SELECT suggestion_type, helpful_pct
FROM v_suggestion_effectiveness
WHERE total >= 3;
```
Skip any suggestion type with helpful_pct < 30%.

**Step 2: Check for suggestion opportunities (in priority order, pick at most ONE)**

*Unblocked downstream tasks:*
```sql
SELECT dt.task_title, dt.status
FROM orch_task_dependencies d
JOIN orch_tasks dt ON dt.id = d.downstream_task_id
WHERE d.upstream_task_id = '{completed_task_id}'
  AND dt.status IN ('NEW', 'INCOMPLETE');
```

*Definition-of-done gaps:*
Read PROJECT_DNA.md definition_of_done. Check whether the completed task's verification covered all criteria. If any criterion wasn't checked, suggest verifying it.

*Pattern-based follow-ups:*
If the completed task was "write code" → suggest "run tests". If it was "research" → suggest "document findings". Use the activity log to see if this pattern has been useful before.

**Step 3: Present the suggestion (if one was found)**
Format: one sentence describing the suggestion, then:
> "Was this suggestion helpful? (yes / no / skip)"

**Step 4: Record feedback**
```sql
INSERT INTO orch_suggestion_feedback
  (session_id, task_id, suggestion_type, suggestion_text, context, feedback, feedback_at)
VALUES
  ('{session_id}', '{task_id}', '{type}', '{text}', '{context}', '{response}', NOW());
```

If the user says "yes" → record 'helpful', proceed with the suggestion.
If "no" → record 'not_helpful', acknowledge and move on.
If "skip" or they ignore it → record 'skipped', move on immediately.

### `/idle-work`
Autonomous low-risk work during downtime. The user is NOT at the TUI — all output goes to `pending_briefing.md`.

**Step 1: Check autonomy gate**
Read PROJECT_DNA.md `autonomy_level` section. If it restricts autonomous execution, respect those boundaries. By default, only research and analysis tasks are permitted unattended — never deployment, external API calls, or file modifications outside the project.

**Step 2: Find eligible tasks**
```sql
SELECT t.id, t.task_title, t.budget_size, t.input_data,
       n.name AS node_name, n.node_type, n.capability_tags
FROM orch_tasks t
LEFT JOIN orch_nodes n ON t.node_id = n.id
WHERE t.status = 'NEW'
  AND t.budget_size = 'S'
  AND t.is_awaiting_human = FALSE
ORDER BY t.created_at
LIMIT 3;
```

If no eligible tasks exist, do nothing and return.

**Step 3: Filter by safety**
For each candidate task, check:
- Is the node type safe for unattended execution? (research, analysis = yes; coding, deployment = check autonomy_level)
- Does the task require external access? (API calls, web requests = check autonomy_level)
- Is the budget_size S? (only small tasks run unattended)

**Step 4: Execute (one task at a time)**
For each eligible task (max 2 per idle-work cycle):
1. Dispatch the matched node as a subagent
2. Wait for completion (do NOT use run_in_background — this is already a background context)
3. If UNVERIFIED → dispatch the verifier
4. If verified COMPLETE → update postgres, log to activity_log
5. If FAILED → log and move on (do NOT retry — Axiom 5)

**Step 5: Write results to briefing**
Append to `.claude/events/pending_briefing.md`:
```markdown
## [timestamp] Idle Work: "{task_title}"
Status: COMPLETE | FAILED
Summary: {brief result}
Node: {node_name}
Autonomy: This task was executed during downtime per PROJECT_DNA.md autonomy_level.

---
```

**Safety rules for idle work:**
- NEVER exceed 2 tasks per idle-work cycle
- NEVER execute tasks with budget_size > S
- NEVER execute tasks flagged is_awaiting_human
- NEVER modify protected files
- NEVER take actions that are irreversible (deployment, external writes)
- If ANY step fails or is ambiguous, stop and log — do not proceed to next task
- All results go to pending_briefing.md, never direct output (user is away)

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
