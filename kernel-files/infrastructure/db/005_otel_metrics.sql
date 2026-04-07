-- ORA Kernel Schema: OpenTelemetry Metrics Tables
-- Receives data from OTel collector pipeline

-- Per-API-call token usage
CREATE TABLE IF NOT EXISTS otel_token_usage (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    session_id      TEXT,
    agent_id        TEXT,
    model           TEXT,
    input_tokens    INTEGER NOT NULL DEFAULT 0,
    output_tokens   INTEGER NOT NULL DEFAULT 0,
    cache_read      INTEGER NOT NULL DEFAULT 0,
    cache_creation  INTEGER NOT NULL DEFAULT 0,
    total_tokens    INTEGER GENERATED ALWAYS AS (input_tokens + output_tokens + cache_read + cache_creation) STORED
);

CREATE INDEX IF NOT EXISTS idx_otel_tokens_session ON otel_token_usage(session_id);
CREATE INDEX IF NOT EXISTS idx_otel_tokens_agent ON otel_token_usage(agent_id);
CREATE INDEX IF NOT EXISTS idx_otel_tokens_ts ON otel_token_usage(timestamp DESC);

-- Per-API-call cost tracking
CREATE TABLE IF NOT EXISTS otel_cost_tracking (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    session_id      TEXT,
    agent_id        TEXT,
    model           TEXT,
    cost_usd        NUMERIC(10,6) NOT NULL DEFAULT 0,
    duration_ms     INTEGER
);

CREATE INDEX IF NOT EXISTS idx_otel_cost_session ON otel_cost_tracking(session_id);
CREATE INDEX IF NOT EXISTS idx_otel_cost_ts ON otel_cost_tracking(timestamp DESC);

-- Per-tool-call execution metrics
CREATE TABLE IF NOT EXISTS otel_tool_results (
    id              BIGSERIAL PRIMARY KEY,
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    session_id      TEXT,
    agent_id        TEXT,
    tool_name       TEXT NOT NULL,
    duration_ms     INTEGER,
    success         BOOLEAN NOT NULL DEFAULT TRUE,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_otel_tools_session ON otel_tool_results(session_id);
CREATE INDEX IF NOT EXISTS idx_otel_tools_name ON otel_tool_results(tool_name);
CREATE INDEX IF NOT EXISTS idx_otel_tools_ts ON otel_tool_results(timestamp DESC);

-- ============================================================================
-- Useful views for self-improvement cycle queries
-- ============================================================================

-- Per-node performance summary
CREATE OR REPLACE VIEW v_node_performance AS
SELECT
    n.name AS node_name,
    n.node_type,
    COUNT(t.id) AS total_tasks,
    COUNT(t.id) FILTER (WHERE t.status = 'COMPLETE') AS completed,
    COUNT(t.id) FILTER (WHERE t.status = 'FAILED') AS failed,
    ROUND(
        COUNT(t.id) FILTER (WHERE t.status = 'FAILED')::NUMERIC /
        NULLIF(COUNT(t.id), 0) * 100, 1
    ) AS failure_rate_pct,
    AVG(EXTRACT(EPOCH FROM (t.completed_at - t.started_at)) * 1000)
        FILTER (WHERE t.completed_at IS NOT NULL) AS avg_duration_ms,
    AVG(t.retry_count) AS avg_retries
FROM orch_nodes n
LEFT JOIN orch_tasks t ON t.node_id = n.id
GROUP BY n.name, n.node_type;

-- Per-session cost summary
CREATE OR REPLACE VIEW v_session_costs AS
SELECT
    session_id,
    COUNT(*) AS api_calls,
    SUM(cost_usd) AS total_cost_usd,
    SUM(duration_ms) AS total_duration_ms,
    MIN(timestamp) AS session_start,
    MAX(timestamp) AS session_end
FROM otel_cost_tracking
GROUP BY session_id;
