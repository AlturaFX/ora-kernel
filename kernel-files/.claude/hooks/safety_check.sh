#!/usr/bin/env bash
# PreToolUse hook: Blocks commands containing rm or sudo anywhere in the string.
# Handles chained commands (&&, ;, |), subshells, xargs, find -exec, etc.
# Exit 2 = block the tool call and send stderr message to the model.

# Read stdin JSON to get the full command
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Check for rm or sudo as whole words anywhere in the command
if echo "$COMMAND" | grep -qE '\brm\b|\bsudo\b'; then
    echo "BLOCKED: Command contains 'rm' or 'sudo'. These operations require human approval. Ask the user to perform this action manually." >&2
    exit 2
fi

exit 0
