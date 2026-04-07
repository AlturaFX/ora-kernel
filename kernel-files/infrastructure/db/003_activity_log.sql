-- ORA Kernel Schema: Activity Log
-- Immutable, append-only event log (Axiom 1: Observable State)

CREATE TABLE IF NOT EXISTS orch_activity_log (
    id              BIGSERIAL PRIMARY KEY,
    task_id         UUID REFERENCES orch_tasks(id),
    session_id      TEXT,                       -- Claude Code session_id
    agent_id        TEXT,                       -- Claude Code agent_id (null = main agent)
    level           TEXT NOT NULL,              -- 'INFO', 'WARN', 'ERROR', 'HITL'
    event_source    TEXT NOT NULL,              -- 'kernel', 'node', 'hook', 'self_improvement'
    action          TEXT NOT NULL,              -- 'DISPATCH', 'COMPLETE', 'FAIL', 'RETRY', 'VERIFY', 'HITL_ESCALATE', 'IMPROVE'
    node_name       TEXT,                       -- which node was involved
    details         JSONB NOT NULL DEFAULT '{}',
    rationale       TEXT,                       -- why this action was taken (Axiom 7)
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Immutability: revoke UPDATE and DELETE from application role
-- (Apply after creating an application-specific role)
-- REVOKE UPDATE, DELETE ON orch_activity_log FROM app_role;

CREATE INDEX IF NOT EXISTS idx_activity_task ON orch_activity_log(task_id);
CREATE INDEX IF NOT EXISTS idx_activity_session ON orch_activity_log(session_id);
CREATE INDEX IF NOT EXISTS idx_activity_created ON orch_activity_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_action ON orch_activity_log(action);
CREATE INDEX IF NOT EXISTS idx_activity_node ON orch_activity_log(node_name);
