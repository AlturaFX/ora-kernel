# Split Spec Schema

A split_spec is returned by Domain Nodes when work needs to be decomposed into subtasks. The Kernel reads the split_spec and dispatches each subtask as a separate subagent.

## Schema

```json
{
  "strategy": "parallel | sequential",
  "rationale": "Why this decomposition serves the mission (Axiom 7 — required)",
  "budget_mode": "pool | subdivide | independent",
  "subtasks": [
    {
      "task_title": "Human-readable title for this subtask",
      "input_data": { "...": "Task-specific input fields" },
      "resource_hints": {
        "capability_tags": ["tag1", "tag2"],
        "min_context_window": 100000
      }
    }
  ],
  "aggregation_instructions": "How the Kernel should reassemble results after all subtasks complete."
}
```

## Field Definitions

### strategy
- `parallel`: Subtasks are independent and can run concurrently. The Kernel dispatches all at once using `run_in_background: true`.
- `sequential`: Subtasks depend on each other. The Kernel dispatches them one at a time, passing prior results as context to the next.

### rationale (required)
Axiom 7 (Purpose) requires every decomposition to explain why it serves the mission. The Kernel validates this before dispatching. A missing or generic rationale ("splitting for efficiency") is insufficient — explain what each piece accomplishes.

### budget_mode
- `pool`: Subtasks share the parent's budget. Default.
- `subdivide`: Parent explicitly allocates portions to each subtask.
- `independent`: Each subtask gets its own budget. Requires HITL approval.

### subtasks (array)
Each subtask has:
- `task_title` (required): Clear, descriptive name
- `input_data` (required): Everything the subtask needs. Must be self-contained per Axiom 6 (Isolation) — no implicit references to other subtasks.
- `resource_hints` (optional): Helps the Kernel route to the right node type
  - `capability_tags`: semantic tags like `["code_generation", "python"]`
  - `min_context_window`: minimum tokens needed

### aggregation_instructions (required)
Tells the Kernel how to reassemble results. The Domain Node will be called again with `aggregation_mode: true` and all child results. These instructions guide that aggregation call.

## Kernel Behavior on Receiving split_spec

1. Validate: rationale is present and meaningful
2. Create subtask entries in orch_tasks with dependencies in orch_task_dependencies
3. For each subtask:
   - Match `resource_hints` against node registry
   - If no match: trigger self-expansion (NodeDesigner)
   - Construct subagent prompt with matched node spec + subtask input_data
   - Dispatch subagent
4. When all subtasks reach UNVERIFIED:
   - Dispatch the original Domain Node again with aggregation_mode + child results
5. Domain Node returns aggregated UNVERIFIED result
6. Proceed to verification cycle
