-- ORA Kernel Schema: Budget Limits
-- Configurable resource limits per task size (Axiom 3: Finite Resources)

CREATE TABLE IF NOT EXISTS orch_budget_limits (
    budget_size     budget_size_enum PRIMARY KEY,
    max_retries     INTEGER NOT NULL DEFAULT 3,
    max_tokens      INTEGER,                    -- token ceiling (null = unlimited)
    max_duration_ms INTEGER,                    -- time ceiling in ms (null = unlimited)
    max_cost_usd    NUMERIC(10,4),             -- cost ceiling (null = unlimited)
    description     TEXT,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO orch_budget_limits (budget_size, max_retries, description) VALUES
    ('S',  2, 'Single-turn tasks: lookups, quick questions, simple edits'),
    ('M',  3, 'Contained deliverables: implement one feature, write one module'),
    ('L',  5, 'Multi-step work: refactoring across files, comprehensive research'),
    ('XL', 8, 'Major assemblies: coordinating multiple subtasks, large deliverables')
ON CONFLICT (budget_size) DO NOTHING;
