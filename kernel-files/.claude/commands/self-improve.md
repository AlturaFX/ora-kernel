---
description: Trigger the self-improvement cycle — analyzes recent task performance and proposes system improvements
allowed-tools: Bash, Read, Write, Agent, Glob, Grep
---

# Self-Improvement Cycle

You are running the self-improvement cycle. This analyzes recent system performance and proposes improvements. ALL proposed changes require user approval (HITL).

## Step 1: Gather Data

Read the activity log:
```bash
cat /tmp/claude-kernel/*/activity_log.jsonl 2>/dev/null
```

Count completed tasks and review the metrics.

## Step 2: Dispatch Tuning Analyst

Dispatch a subagent using the TuningAnalyst node spec (`.claude/kernel/nodes/self_improvement/tuning_analyst.md`):
- Pass the activity log entries as input
- Pass the current task count

Wait for the result. It will propose parameter adjustments.

## Step 3: Dispatch Refinement Analyst

Dispatch a subagent using the RefinementAnalyst node spec (`.claude/kernel/nodes/self_improvement/refinement_analyst.md`):
- Pass the activity log entries (focused on failures)
- Pass any nodes flagged by the Tuning Analyst

Wait for the result. It will propose prompt edits.

## Step 4: Verify Both

For each analyst result, dispatch the corresponding verifier:
- TuningAnalystVerifier for parameter proposals
- RefinementAnalystVerifier for prompt proposals

## Step 5: Present to User (HITL)

Present ALL verified proposals to the user. For each proposal:
1. What the change is
2. Why it's proposed (citing metrics)
3. What the expected impact is

Ask the user to approve or reject each proposal individually.

## Step 6: Apply Approved Changes

For approved parameter changes:
- Update orch_config or orch_budget_limits via postgres MCP

For approved prompt changes:
- Edit the node spec files in `.claude/kernel/nodes/`
- Update agents.yaml if capability_tags or descriptions changed

## Step 7: Log the Event

Record the self-improvement event in the activity log with:
- What was analyzed
- What was proposed
- What was approved/rejected
- What was applied

## Rules

- NEVER apply changes without user approval
- NEVER modify protected files (constitution, schemas, hooks, CLAUDE.md)
- Present proposals clearly so the user can make informed decisions
- If no improvements are needed, say so — don't force changes
