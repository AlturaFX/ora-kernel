-- ORA Kernel Schema: Core Tables
-- Database: ora_kernel
-- Portable, project-agnostic orchestration schema for Claude Code

-- Prerequisites
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

CREATE TYPE node_type AS ENUM ('domain_node', 'domain_verifier', 'task_node', 'task_verifier');
CREATE TYPE node_kind AS ENUM ('user', 'system', 'deprecated');
CREATE TYPE task_status AS ENUM ('NEW', 'INCOMPLETE', 'UNVERIFIED', 'COMPLETE', 'FAILED', 'CANCELLED');
CREATE TYPE budget_size_enum AS ENUM ('S', 'M', 'L', 'XL');

-- ============================================================================
-- orch_nodes — Node Registry
-- Maps to markdown files in .claude/kernel/nodes/
-- ============================================================================

CREATE TABLE IF NOT EXISTS orch_nodes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    node_type       node_type NOT NULL,
    node_kind       node_kind NOT NULL DEFAULT 'user',
    quad_name       TEXT NOT NULL,
    paired_verifier_id UUID REFERENCES orch_nodes(id),
    spec_path       TEXT NOT NULL,              -- relative path to .md spec file
    version         TEXT NOT NULL DEFAULT '1.0.0',
    description     TEXT NOT NULL,
    capability_tags TEXT[] NOT NULL DEFAULT '{}',
    input_schema    JSONB NOT NULL DEFAULT '{}',
    output_schema   JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(name, version)
);

CREATE INDEX IF NOT EXISTS idx_nodes_capability_tags ON orch_nodes USING GIN (capability_tags);
CREATE INDEX IF NOT EXISTS idx_nodes_quad ON orch_nodes(quad_name);

-- ============================================================================
-- orch_tasks — Task State Machine
-- Core lifecycle: NEW → INCOMPLETE → UNVERIFIED → COMPLETE | FAILED
-- ============================================================================

CREATE TABLE IF NOT EXISTS orch_tasks (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_title          TEXT NOT NULL,
    status              task_status NOT NULL DEFAULT 'NEW',
    node_id             UUID REFERENCES orch_nodes(id),

    -- Claude Code agent tracking
    session_id          TEXT,                   -- Claude Code session_id from hook stdin
    agent_id            TEXT,                   -- Claude Code agent_id (null = main agent)
    project_dir         TEXT,                   -- project directory for portability

    input_data          JSONB NOT NULL DEFAULT '{}',
    result_data         JSONB NOT NULL DEFAULT '{}',

    -- Budget and retry management (Axiom 3)
    budget_size         budget_size_enum DEFAULT 'S',
    retry_count         INTEGER DEFAULT 0,
    max_retries         INTEGER DEFAULT 3,

    -- HITL flag — orthogonal to status (Axiom 4)
    is_awaiting_human   BOOLEAN DEFAULT FALSE,
    hitl_reason         TEXT,

    -- Lifecycle timestamps
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    started_at          TIMESTAMPTZ,
    dispatched_at       TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON orch_tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_session ON orch_tasks(session_id);
CREATE INDEX IF NOT EXISTS idx_tasks_agent ON orch_tasks(agent_id);
CREATE INDEX IF NOT EXISTS idx_tasks_updated ON orch_tasks(updated_at);
CREATE INDEX IF NOT EXISTS idx_tasks_dispatched ON orch_tasks(dispatched_at)
    WHERE dispatched_at IS NOT NULL AND status NOT IN ('COMPLETE', 'FAILED', 'CANCELLED');

-- ============================================================================
-- orch_sessions — Kernel Session Tracking
-- Maps to Claude Code sessions (TUI sessions)
-- ============================================================================

CREATE TABLE IF NOT EXISTS orch_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      TEXT NOT NULL UNIQUE,       -- Claude Code session_id
    project_dir     TEXT,
    status          TEXT NOT NULL DEFAULT 'active',
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    ended_at        TIMESTAMPTZ,
    metadata        JSONB NOT NULL DEFAULT '{}'
);

-- ============================================================================
-- orch_config — Runtime Configuration
-- Self-improvement threshold, budget defaults, etc.
-- ============================================================================

CREATE TABLE IF NOT EXISTS orch_config (
    key             TEXT PRIMARY KEY,
    value           JSONB NOT NULL,
    description     TEXT,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Default configuration
INSERT INTO orch_config (key, value, description) VALUES
    ('self_improvement_threshold', '10', 'Number of completed tasks before self-improvement triggers'),
    ('default_max_retries', '3', 'Default max retries per task before HITL escalation'),
    ('budget_limits', '{"S": {"max_retries": 2}, "M": {"max_retries": 3}, "L": {"max_retries": 5}, "XL": {"max_retries": 8}}', 'Budget limits per task size')
ON CONFLICT (key) DO NOTHING;
