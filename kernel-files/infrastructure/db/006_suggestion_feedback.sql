-- ORA Kernel Schema: Suggestion Feedback
-- Tracks which proactive suggestions users found helpful.
-- The Kernel reads this history to calibrate future suggestions.

CREATE TABLE IF NOT EXISTS orch_suggestion_feedback (
    id              BIGSERIAL PRIMARY KEY,
    session_id      TEXT,
    task_id         UUID REFERENCES orch_tasks(id),
    suggestion_type TEXT NOT NULL,              -- 'next_task', 'unblocked', 'doc_stale', 'dod_gap', 'pattern'
    suggestion_text TEXT NOT NULL,              -- the actual suggestion presented
    context         JSONB NOT NULL DEFAULT '{}', -- what triggered it (completed task, dependency, etc.)
    feedback        TEXT,                       -- 'helpful', 'not_helpful', 'skipped', NULL (no response)
    feedback_note   TEXT,                       -- optional user comment on why
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    feedback_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_suggestions_type ON orch_suggestion_feedback(suggestion_type);
CREATE INDEX IF NOT EXISTS idx_suggestions_feedback ON orch_suggestion_feedback(feedback);
CREATE INDEX IF NOT EXISTS idx_suggestions_created ON orch_suggestion_feedback(created_at DESC);

-- View: suggestion effectiveness by type
CREATE OR REPLACE VIEW v_suggestion_effectiveness AS
SELECT
    suggestion_type,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE feedback = 'helpful') AS helpful,
    COUNT(*) FILTER (WHERE feedback = 'not_helpful') AS not_helpful,
    COUNT(*) FILTER (WHERE feedback = 'skipped' OR feedback IS NULL) AS ignored,
    ROUND(
        COUNT(*) FILTER (WHERE feedback = 'helpful')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE feedback IS NOT NULL AND feedback != 'skipped'), 0) * 100, 1
    ) AS helpful_pct
FROM orch_suggestion_feedback
GROUP BY suggestion_type;
