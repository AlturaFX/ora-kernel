# SPEC-001: ORA Kernel Cloud — Managed Agent Fork

**Status**: Draft
**Created**: 2026-04-08
**Author**: AlturaFX + Claude Opus 4.6
**Source**: docs/CLOUD_ARCHITECTURE.md
**Repo**: New fork — `ora-kernel-cloud`

---

## Goal

Create a fork of ORA Kernel that hosts the Kernel as a Claude Managed Agent — a persistent, always-on cloud session. This enables autonomous operation (heartbeats, briefings, idle work, self-improvement) without a TUI being open, and provides real-time monitoring via the existing forex-ml-platform dashboard.

### Problem This Solves

The base ORA Kernel requires a Claude Code TUI session to be running. The Kernel dies when you close the terminal. Autonomous features (heartbeat, briefing, idle work) only work when the TUI is active and `/kernel-listen` is backgrounded. This limits the system to "working while you're watching."

### Success Criteria

- [ ] A Managed Agent session stays alive indefinitely without a TUI
- [ ] Cron triggers (heartbeat, briefing, idle work, consolidation) are sent via API
- [ ] SSE events are consumed and written to PostgreSQL in real-time
- [ ] Token costs are tracked per-session with running totals
- [ ] HITL approvals work via the dashboard
- [ ] The dashboard's Orchestration tab shows live Managed Agent activity
- [ ] WISDOM.md and journal entries survive container restarts
- [ ] A local Claude Code TUI can share the same postgres state (hybrid mode)

---

## Scope

### In Scope

1. **Thin orchestrator** — Python daemon managing the Managed Agent lifecycle
2. **Dashboard integration** — Extend existing Orchestration tab for Managed Agent monitoring
3. **File sync** — WISDOM.md and journal persistence across ephemeral containers
4. **Hybrid mode** — Local TUI + cloud agent sharing postgres
5. **Cost monitoring** — Real-time token and container cost tracking

### Out of Scope

- Modifying the Constitution or axioms (identical to base ORA Kernel)
- Changing node spec format (identical)
- Multi-tenant support (single user/org for now)
- Mobile app integration (future — Remote Control exists but is separate)

---

## Constraints

- Requires Anthropic API key with Managed Agents beta access
- API billing separate from Claude Code subscription
- Container runtime: $0.05/hr beyond 50 free hours/day
- Managed Agents API is in beta (`managed-agents-2026-04-01` header required)
- Each session gets isolated container — no shared filesystem between sessions
- Python 3.8+ for thin orchestrator (stdlib + `anthropic` SDK)

---

## Dependencies

| Dependency | Status | Notes |
|---|---|---|
| `ora-kernel` base repo | Complete | Fork from this |
| `anthropic` Python SDK | Available | `pip install anthropic` |
| PostgreSQL `ora_kernel` database | Exists | Same schema, shared state |
| forex-ml-platform dashboard | Exists | Extend Orchestration tab |
| Managed Agents API access | Beta | Enabled by default for API accounts |

---

## Contracts & Interfaces

### 1. Orchestrator ↔ Anthropic API

**Agent creation:**
```python
Agent = {
    name: str,           # "ORA Kernel"
    model: str,          # "claude-opus-4-6"
    system: str,         # Contents of CLAUDE.md (with ORA-KERNEL markers)
    tools: list,         # [{"type": "agent_toolset_20260401"}]
}
```

**Session lifecycle:**
```
create_session(agent_id, environment_id) → session_id
events.send(session_id, events=[user.message]) → void
events.stream(session_id) → SSE stream
session.retrieve(session_id) → status, event_count
```

**Event types consumed:**
```
agent.message     → Log to activity_log, forward to dashboard
agent.tool_use    → Log to activity_log, forward to dashboard
agent.tool_result → Log to activity_log
session.status_*  → Update session health, forward to dashboard
span.model_request_end → Write to otel_token_usage + otel_cost_tracking
```

**Event types sent:**
```
user.message            → Task dispatch, cron triggers (/heartbeat, /briefing, etc.)
user.interrupt          → Emergency stop
user.tool_confirmation  → HITL approval/denial from dashboard
```

### 2. Orchestrator ↔ PostgreSQL

Uses existing `ora_kernel` schema. New tables needed:

```sql
-- Track Managed Agent sessions
CREATE TABLE IF NOT EXISTS cloud_sessions (
    id              BIGSERIAL PRIMARY KEY,
    agent_id        TEXT NOT NULL,       -- Anthropic agent ID
    environment_id  TEXT NOT NULL,       -- Anthropic environment ID
    session_id      TEXT NOT NULL UNIQUE, -- Anthropic session ID
    status          TEXT NOT NULL DEFAULT 'created',
    container_start TIMESTAMPTZ,
    container_hours NUMERIC(10,4) DEFAULT 0,
    total_input_tokens  BIGINT DEFAULT 0,
    total_output_tokens BIGINT DEFAULT 0,
    total_cost_usd  NUMERIC(10,4) DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    last_event_at   TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ
);

-- Sync WISDOM.md and journal entries for container persistence
CREATE TABLE IF NOT EXISTS kernel_files_sync (
    file_path       TEXT PRIMARY KEY,    -- e.g., ".claude/kernel/journal/WISDOM.md"
    content         TEXT NOT NULL,
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    synced_from     TEXT NOT NULL        -- 'container' or 'local'
);
```

### 3. Orchestrator ↔ Dashboard

**WebSocket protocol** (extends existing `orchestrator-client.js` message types):

```json
// New message types from orchestrator to dashboard:

// Agent status update
{"type": "managed_agent_status", "status": "running|idle|terminated", "session_id": "...", "uptime_hours": 12.5}

// Live event forwarding
{"type": "managed_agent_event", "event_type": "agent.tool_use", "tool_name": "Bash", "input": "...", "timestamp": "..."}
{"type": "managed_agent_event", "event_type": "agent.message", "text": "...", "timestamp": "..."}

// Cost ticker update
{"type": "managed_agent_cost", "session_cost_usd": 1.234, "hourly_rate": 0.05, "tokens_today": {"input": 50000, "output": 12000}}

// HITL request forwarded from agent
{"type": "managed_agent_hitl", "request_id": "...", "tool_name": "...", "description": "...", "options": ["approve", "deny"]}

// From dashboard to orchestrator:

// HITL response
{"type": "managed_agent_hitl_response", "request_id": "...", "decision": "approve|deny", "note": "optional reason"}

// Direct message to agent
{"type": "managed_agent_message", "content": "user message text"}
```

### 4. Container ↔ PostgreSQL

The Managed Agent's container connects to postgres for task state. Environment networking must allow the postgres host.

Connection string passed via bootstrap event or environment variable.

---

## Task Breakdown

### Phase 1: Thin Orchestrator (MVP)

**Task 1.1: Fork repo and set up ora-kernel-cloud**
- Fork `ora-kernel` to `ora-kernel-cloud`
- Add `anthropic` SDK dependency
- Add `orchestrator/` directory for new code
- Acceptance: repo exists, installs cleanly

**Task 1.2: Agent and environment management**
- `orchestrator/agent_manager.py`: create/retrieve agent and environment
- Store IDs in local config file (`.ora-kernel-cloud.json`)
- Idempotent: reuse existing agent/environment if already created
- Acceptance: `python orchestrator/agent_manager.py setup` creates agent + env, prints IDs

**Task 1.3: Session lifecycle**
- `orchestrator/session_manager.py`: create session, send bootstrap event, handle restart on termination
- Bootstrap clones repo, runs install.py, reads CLAUDE.md
- Acceptance: session starts, agent reports ready, survives container restart

**Task 1.4: SSE event consumer**
- `orchestrator/event_consumer.py`: connect to stream, parse events by type, write to postgres
- Map `span.model_request_end` → `otel_token_usage` + `otel_cost_tracking`
- Map `agent.tool_use` / `agent.tool_result` → `orch_activity_log`
- Print events to stdout as fallback UI
- Acceptance: events flow from agent through consumer to postgres, token counts match

**Task 1.5: Cron trigger scheduler**
- `orchestrator/scheduler.py`: APScheduler or simple threading.Timer
- Sends `/heartbeat` (every 2hrs), `/briefing` (daily 8am), `/idle-work` (off-hours), `/consolidate` (weekly)
- Configurable via `config.yaml`
- Acceptance: triggers arrive at agent on schedule, agent processes them

**Task 1.6: HITL via stdin (MVP)**
- When `user.tool_confirmation` needed, print to stdout and read from stdin
- Temporary until dashboard integration (Phase 2)
- Acceptance: can approve/deny tool calls from terminal

**Task 1.7: Main entry point**
- `orchestrator/main.py`: ties together agent_manager, session_manager, event_consumer, scheduler
- `python -m orchestrator` starts the full system
- Graceful shutdown on SIGTERM/SIGINT
- Acceptance: single command starts everything, Ctrl+C shuts down cleanly

### Phase 2: Dashboard Integration

**Task 2.1: WebSocket bridge**
- `orchestrator/ws_bridge.py`: WebSocket server (port 8002)
- Consumes events from event_consumer, translates to dashboard protocol
- Acceptance: dashboard connects to ws://localhost:8002 and receives events

**Task 2.2: Dashboard agent health panel**
- New panel in Orchestration tab showing: session status, uptime, container hours
- Cytoscape node for Managed Kernel (always visible, color = status)
- Acceptance: panel shows live status, updates on status change

**Task 2.3: Dashboard cost panel**
- Real-time token cost display, hourly burn rate, daily/monthly projection
- Extends existing budget ticker HUD
- Acceptance: costs update in real-time as agent works

**Task 2.4: Dashboard event stream panel**
- Live scrolling log of agent events (tool calls, messages)
- Filter by event type
- Acceptance: events appear within 1 second of occurrence

**Task 2.5: Dashboard HITL integration**
- Extend existing HITL widget to handle Managed Agent confirmation requests
- Forward responses via WebSocket → orchestrator → API
- Acceptance: can approve/deny from dashboard, agent proceeds

### Phase 3: File Sync

**Task 3.1: Postgres file sync tables**
- Migration `007_file_sync.sql` for `kernel_files_sync` and `cloud_sessions` tables
- Acceptance: tables created, basic CRUD works

**Task 3.2: Bootstrap with file hydration**
- Bootstrap event pulls WISDOM.md and recent journal entries from postgres before starting work
- Acceptance: fresh container has accumulated wisdom

**Task 3.3: Journal/WISDOM write-through**
- When agent writes journal or WISDOM in container, also write to postgres via psql
- Acceptance: journal entries survive container restart

**Task 3.4: Node spec git flow**
- New node specs (from self-expansion) committed to git from container
- Acceptance: NodeCreator output persists in repo

### Phase 4: Hybrid Mode

**Task 4.1: Shared task routing**
- Tasks created in local TUI appear in Kernel's postgres queue
- Kernel's autonomous results visible in local TUI session
- Acceptance: create task locally, see it dispatched by cloud Kernel

**Task 4.2: Unified activity log**
- Both local and cloud sources write to same `orch_activity_log`
- Self-improvement cycle sees all activity regardless of source
- Acceptance: `/self-improve` analyzes tasks from both contexts

---

## Validation Plan

### Automated Tests
```bash
# Phase 1
pytest orchestrator/tests/test_agent_manager.py     # Agent/env creation
pytest orchestrator/tests/test_session_manager.py    # Session lifecycle
pytest orchestrator/tests/test_event_consumer.py     # Event parsing + postgres writes
pytest orchestrator/tests/test_scheduler.py          # Cron trigger timing

# Phase 2
pytest orchestrator/tests/test_ws_bridge.py          # WebSocket message translation

# Phase 3
pytest orchestrator/tests/test_file_sync.py          # Postgres read/write roundtrip
```

### Integration Tests
```bash
# End-to-end: start orchestrator, send task, verify in postgres
python -m orchestrator --test-mode

# Dashboard: open browser, verify panels render
playwright-cli open http://localhost:8080/dashboard.html
playwright-cli snapshot  # Verify Orchestration tab shows Managed Agent node
```

### Manual Verification
- [ ] Start orchestrator, verify agent session created in Claude Console
- [ ] Send `/heartbeat`, verify silent when healthy
- [ ] Send a task, watch it flow through dashboard in real-time
- [ ] Trigger HITL, approve from dashboard, verify agent continues
- [ ] Kill container, verify session restarts and WISDOM.md survives
- [ ] Open Claude Code TUI, create task, verify cloud Kernel picks it up

---

## Files to Create

### New (in ora-kernel-cloud fork)

| File | Purpose |
|---|---|
| `orchestrator/__init__.py` | Package init |
| `orchestrator/__main__.py` | Entry point (`python -m orchestrator`) |
| `orchestrator/main.py` | Ties all components together |
| `orchestrator/agent_manager.py` | Agent + environment CRUD |
| `orchestrator/session_manager.py` | Session lifecycle + bootstrap |
| `orchestrator/event_consumer.py` | SSE stream → postgres + forwarding |
| `orchestrator/scheduler.py` | Cron trigger scheduling |
| `orchestrator/ws_bridge.py` | WebSocket bridge to dashboard |
| `orchestrator/config.py` | Configuration loading |
| `orchestrator/db.py` | PostgreSQL connection helpers |
| `config.yaml` | Orchestrator configuration (schedules, ports, postgres DSN) |
| `requirements.txt` | `anthropic`, `psycopg2-binary`, `apscheduler`, `websockets` |
| `infrastructure/db/007_cloud_sessions.sql` | Cloud session + file sync tables |

### Modified (from base ora-kernel)

| File | Change |
|---|---|
| `kernel-files/CLAUDE.md` | Add note about cloud mode + postgres connectivity instructions |
| `README.md` | Cloud-specific quickstart, cost model, dashboard setup |
| `CHANGELOG.md` | v2.0.0 entries |

### Dashboard files (in forex-ml-platform, separate PR)

| File | Change |
|---|---|
| `dashboard.html` | New panels in Orchestration tab |
| `src/dashboard/orchestrator-client.js` | New WebSocket connection to port 8002, new event handlers |

---

## Risks & Open Questions

### Risks

1. **Beta instability** — Managed Agents is in beta. API may change between releases. Mitigation: pin SDK version, abstract API calls behind our own interfaces.

2. **Container cold start** — Each session needs to clone repo and set up. Could add 30-60 seconds to restart. Mitigation: minimize bootstrap, cache packages in environment.

3. **Cost runaway** — An agent stuck in a loop burns tokens. Mitigation: our loop detector runs in the container (hooks work via filesystem), plus the orchestrator monitors `span.model_request_end` costs and can `user.interrupt` if budget exceeded.

4. **Postgres connectivity from container** — The container needs network access to your postgres. If postgres is local (not cloud-hosted), you'd need a tunnel or public endpoint. Mitigation: document this requirement clearly; suggest cloud postgres (Supabase, Railway, Neon) as an option.

### Open Questions

1. **Environment variable injection** — Can we pass POSTGRES_DSN as an env var to the container, or does the agent need to discover it from the system prompt?
2. **Agent versioning** — When we update CLAUDE.md, do we create a new agent version or update the existing one? (API supports versioning)
3. **Multi-project** — If the user runs ORA Kernel Cloud on two projects, do they share one agent with two environments, or two separate agents?
4. **Dashboard deployment** — Is the forex-ml dashboard accessible from the cloud container for HITL, or does HITL always flow through the orchestrator?

---

## Handoff Notes

This spec is ready for implementation. Recommended approach:

1. **Fork the repo** — `gh repo fork AlturaFX/ora-kernel --fork-name ora-kernel-cloud`
2. **Phase 1 first** — The thin orchestrator is the foundation. Implement tasks 1.1-1.7 before anything else.
3. **Use `/build-with-agent-team`** — Tasks 1.2-1.6 are independent Python modules that can be built in parallel by separate agents, then integrated in Task 1.7.
4. **Dashboard work is a separate PR** against forex-ml-platform, not the ora-kernel-cloud repo.
