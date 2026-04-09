# API Key Setup for ORA Kernel Cloud

## Get Your API Key

1. Go to https://console.anthropic.com
2. Sign in with your Anthropic account
3. Navigate to **Settings → API Keys**
4. Click **Create Key**, name it `ora-kernel-cloud`
5. Copy the key (starts with `sk-ant-...`) — you only see it once

## Add Billing

API usage is billed separately from your Claude Pro/Max subscription.

1. In the Console: **Settings → Billing**
2. Add a payment method
3. Set a monthly spend limit (recommended: start at $50)

## Store the Key Securely

### Option A: Environment variable (recommended for development)

Add to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

Then reload: `source ~/.bashrc`

The `anthropic` Python SDK reads this automatically — no code changes needed.

### Option B: `.env` file (recommended for project use)

Create a `.env` file in the `ora-kernel-cloud` project root:

```bash
echo 'ANTHROPIC_API_KEY=sk-ant-your-key-here' > .env
```

The orchestrator loads it via `python-dotenv` or reads it manually.

### Option C: System keyring (most secure)

```bash
# Store
python3 -c "import keyring; keyring.set_password('ora-kernel', 'api_key', 'sk-ant-your-key-here')"

# Retrieve (in your code)
python3 -c "import keyring; print(keyring.get_password('ora-kernel', 'api_key'))"
```

Requires `pip install keyring`. Uses your OS keychain (macOS Keychain, GNOME Keyring, Windows Credential Vault).

## Keep It Out of Git

These entries are already in the `.gitignore`:

```
# API keys and secrets
.env
*.local.json
```

If you haven't already, verify `.env` is gitignored:

```bash
echo '.env' >> .gitignore
```

### What NOT to do

- Never put the key in `config.yaml`, `settings.json`, or any tracked file
- Never pass it as a command-line argument (visible in process list)
- Never commit it to git — even in a "temporary" commit. If you accidentally commit a key, rotate it immediately at https://console.anthropic.com/settings/keys

## Verify It Works

```bash
# Quick test — should return your account info
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
```

If you get a JSON response with `"type": "message"`, your key is working.

## Cost Expectations

| Activity | Approximate Cost |
|---|---|
| Managed Agent session (idle) | Free ($0 when idle) |
| Managed Agent session (running) | $0.08/hr runtime + token costs |
| Heartbeat check (12/day, mostly silent) | ~$0.05/day |
| Daily briefing (1/day) | ~$0.15/day |
| Idle work (2-3 tasks/night) | ~$1-3/day depending on task |
| Self-improvement (weekly) | ~$2-5/week |
| **Estimated monthly (light use)** | **$30-60** |
| **Estimated monthly (heavy use)** | **$100-200** |

Runtime charges only accrue while the agent is in `running` status — not while idle waiting for the next event. This means an always-on session that mostly waits costs very little in runtime.
