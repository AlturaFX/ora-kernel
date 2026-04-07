-- ORA Kernel Schema: Task Dependencies
-- Junction table for flexible task sequencing

CREATE TABLE IF NOT EXISTS orch_task_dependencies (
    upstream_task_id    UUID NOT NULL REFERENCES orch_tasks(id) ON DELETE CASCADE,
    downstream_task_id  UUID NOT NULL REFERENCES orch_tasks(id) ON DELETE CASCADE,
    dependency_type     TEXT NOT NULL DEFAULT 'blocks',  -- 'blocks', 'verification', 'aggregation'
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (upstream_task_id, downstream_task_id)
);

CREATE INDEX IF NOT EXISTS idx_task_deps_downstream ON orch_task_dependencies(downstream_task_id);
CREATE INDEX IF NOT EXISTS idx_task_deps_type ON orch_task_dependencies(dependency_type);

-- Prevent self-referencing dependencies
ALTER TABLE orch_task_dependencies
    ADD CONSTRAINT no_self_dependency CHECK (upstream_task_id != downstream_task_id);
