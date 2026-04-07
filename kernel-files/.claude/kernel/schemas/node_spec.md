# Node Spec Template

This template defines the structure for all node specification files. Every node in `.claude/kernel/nodes/` must follow this format. The NodeCreator uses this template when generating new nodes.

---

## Worker Node Template

```markdown
---
name: {NodeName}
type: task | domain
quad: {QuadName}
version: 1.0
created: {ISO date}
---

# {NodeName}

## System Prompt

[The complete prompt that gets injected into the Agent tool call. This is the
node's identity — it defines what the node does, how it thinks, and what it
produces. Be specific and unambiguous.]

## Input Contract

[Describe what this node receives as input. Include field names, types, and
which fields are required vs optional. Example:]

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| goal | string | Yes | What to accomplish |
| context | string | No | Background information |
| constraints | array | No | List of restrictions |

## Output Contract

Return a JSON object per `.claude/kernel/schemas/node_output.md`.

[Specify which fields this node typically populates:]

- `target_status`: UNVERIFIED on success, FAILED on error
- `inline_data`: {describe the expected structure}
- `artifacts`: {describe what files are produced, if any}

## Behavioral Constraints

[What this node must NOT do. These are injected into the subagent prompt.]

For Task Nodes:
- Do NOT plan, decompose, or split work
- Do NOT verify your own output
- Do NOT spawn subagents or delegate
- Execute the task atomically and return results

For Domain Nodes:
- Do NOT execute atomic work directly
- Plan and decompose OR aggregate — not both in one call
- When splitting: return split_spec with target_status UNVERIFIED
- When aggregating: synthesize child results into a single coherent output
```

---

## Verifier Node Template

```markdown
---
name: {NodeName}Verifier
type: verifier
quad: {QuadName}
verifies: {NodeName}
version: 1.0
created: {ISO date}
---

# {NodeName} Verifier

## System Prompt

You are an objective verifier. You receive work produced by {NodeName} and
evaluate it against specific criteria. You do NOT produce original work.

[Define what this verifier checks. Be specific about pass/fail criteria.
Reference PROJECT_DNA.md definition_of_done where applicable.]

## Input Contract

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| work_product | object | Yes | The NodeOutput from the producing node |
| task_description | string | Yes | The original task that was assigned |
| definition_of_done | string | No | Criteria from PROJECT_DNA.md |

## Output Contract

Return a JSON object per `.claude/kernel/schemas/node_output.md`.

- `target_status`: COMPLETE if verification passes, FAILED if rejected
- `inline_data.verification_notes`: Summary of what was checked
- `inline_data.checks_passed`: Array of check names that passed
- `inline_data.failed_checks`: Array of check names that failed (when FAILED)
- `error`: Required when FAILED — include specific reasons for rejection

## Verification Criteria

[List the specific, objective checks this verifier performs. Examples:]

1. Output matches the expected schema
2. All required fields are present and non-empty
3. Artifacts referenced actually exist
4. Content is factually consistent (no contradictions)
5. Work addresses the original task description
6. Definition of done criteria are met

## Behavioral Constraints

- Do NOT produce original work or creative content
- Do NOT fix problems — report them for replanning
- Do NOT approve work that partially meets criteria — either it passes all checks or it fails
- Be specific in rejection reasons so the replanning node can address them
- Reference the exact check that failed and what would need to change
```

---

## Node Quad Structure

Every capability in the system is implemented as a Quad:

| Component | File | Role |
|-----------|------|------|
| Domain Node | `{name}.md` | Plans work, decomposes tasks, aggregates results |
| Domain Verifier | `{name}_verifier.md` | Verifies the domain node's planning and aggregation |
| Task Node | `{name}_task.md` | Executes atomic work |
| Task Verifier | `{name}_task_verifier.md` | Verifies the task node's execution |

For simple capabilities (no decomposition needed), a minimal Quad has:
- Task Node + Task Verifier (2 files minimum)

The NodeCreator MUST produce both worker and verifier when creating new nodes.
