# Configuration

Almost everything works with no configuration. This page covers what you *can* change.

## The files

| File | Purpose | Edit it? |
|---|---|---|
| [`.env`](../.env.example) | Your secrets: API key, optional tunnel token. **Git-ignored.** | Yes, it's yours |
| [`LiteLLM/config.yaml`](../LiteLLM/config.yaml) | Which models are exposed and how requests are authenticated | To pin models or add aliases |
| [`cloudflared/config.yml`](../cloudflared/config.yml) | Template for a named tunnel (config-file method) | Only for a named tunnel |
| [`cloudflared/quick-tunnel.yml`](../cloudflared/quick-tunnel.yml) | Deliberately has no ingress rules; used for quick tunnels | No |
| [`scripts/start.ps1`](../scripts/start.ps1), [`start.sh`](../scripts/start.sh) | One-command launchers | Rarely |

## `.env` settings

Created automatically on first run from [`.env.example`](../.env.example). One `KEY=value` per line; lines starting with `#` are comments.

| Variable | Required | What it does |
|---|---|---|
| `LITELLM_MASTER_KEY` | **Yes** | The API key clients must send as `Authorization: Bearer <key>`. Generated for you. The scripts refuse to start if it's empty. |
| `CLOUDFLARE_TUNNEL_TOKEN` | Only for `named` with the dashboard method | Token for a remotely-managed Cloudflare tunnel. If set, it takes priority over any config file. |
| `PUBLIC_URL` | No | Your named tunnel's hostname (for example `https://llm.yourdomain.com`), so the script can print a ready-to-use URL. Purely cosmetic. |

**To generate a key yourself** (any long random string starting with `sk-` works):

```bash
python -c "import secrets; print('sk-' + secrets.token_urlsafe(32))"
```

## Script options

| Windows (`start.ps1`) | macOS/Linux (`start.sh`) | Default | Meaning |
|---|---|---|---|
| `-Tunnel quick\|named\|none` | `--tunnel quick\|named\|none` | `quick` | Which tunnel to start (see [tunnels.md](tunnels.md)) |
| `-Port 4000` | `--port 4000` | `4000` | Local port for LiteLLM |
| `-BindHost 127.0.0.1` | `--host 127.0.0.1` | `127.0.0.1` | Network interface LiteLLM listens on. `127.0.0.1` means this machine only; `0.0.0.0` also allows other devices on your network. |

Examples:

```powershell
.\scripts\start.ps1 -Tunnel named -Port 8080
```

```bash
./scripts/start.sh --tunnel none --host 0.0.0.0
```

If you change the port, a named tunnel's `service:` (or the dashboard's public hostname URL) must point at the same port.

Logs are written to `logs/` (git-ignored). Look there first when something goes wrong.

## The LiteLLM config

[`LiteLLM/config.yaml`](../LiteLLM/config.yaml) ships with two parts.

### 1. `model_list`: which models are available

The default is a **catch-all**:

```yaml
model_list:
  - model_name: "*"
    litellm_params:
      model: "ollama_chat/*"
      api_base: http://localhost:11434
```

Whatever model name a client sends is passed to Ollama. If you `ollama pull` something new, it's immediately usable, with no edits or restarts. (`ollama_chat/` makes LiteLLM use Ollama's chat endpoint, which LiteLLM recommends for chat models.)

The trade-off is that `GET /v1/models` doesn't list your real models. That only matters to apps that build a dropdown from it. See [using-the-api.md](using-the-api.md#the-model-list-shows-odd-entries).

### 2. `general_settings`: authentication

```yaml
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

`os.environ/NAME` tells LiteLLM to read the value from the environment variable `NAME`, which the start scripts fill from `.env`. **This must stay under `general_settings`.** Placed under `litellm_settings`, LiteLLM silently ignores it and your API is open to anyone.

## Pinning models and creating aliases

To expose only certain models, or to give them friendlier names, replace the catch-all with explicit entries:

```yaml
model_list:
  - model_name: general              # what clients send as "model"
    litellm_params:
      model: ollama_chat/llama3.2:latest   # what Ollama actually runs
      api_base: http://localhost:11434

  - model_name: coder
    litellm_params:
      model: ollama_chat/qwen2.5-coder:7b
      api_base: http://localhost:11434
```

Restart the gateway after editing. Then:

- Clients use `general` or `coder` as the model name.
- `GET /v1/models` lists exactly `general` and `coder`, so dropdown-based apps work.
- Only the models you list are reachable.

The benefit of aliases: you can swap the underlying model later (change `llama3.2` to something newer) without touching any client.

Keeping aliases *and* the catch-all together also works: the aliases answer, and any other model name is still passed straight through to Ollama. `/v1/models` then lists your aliases plus the made-up `ollama_chat/llama2` entry described in [using-the-api.md](using-the-api.md#the-model-list-shows-odd-entries).

## Ollama on a different machine or port

The config points at `http://localhost:11434`. If Ollama runs elsewhere, edit `api_base` in each entry of `model_list`.

The start scripts also check for Ollama at `127.0.0.1:11434` before launching, and will stop with an error if it isn't there. In that case, run the pieces yourself as shown below.

## Running the pieces manually

The scripts are convenience wrappers. You can run everything yourself, for example for a custom setup or inside your own service manager.

```bash
# 1. Provide the key (Linux/macOS shown)
export LITELLM_MASTER_KEY="sk-your-key"

# 2. The gateway
litellm --config LiteLLM/config.yaml --host 127.0.0.1 --port 4000

# 3. In another terminal, a tunnel (optional)
cloudflared tunnel --config cloudflared/quick-tunnel.yml --url http://127.0.0.1:4000
```

On Windows PowerShell, use `$env:LITELLM_MASTER_KEY = "sk-your-key"`, and also set `$env:PYTHONUTF8 = "1"` before starting LiteLLM. Without it, LiteLLM can crash at startup on Windows when its output is redirected to a file.

## Going further with LiteLLM

LiteLLM has many features this project doesn't configure: per-user API keys with budgets and rate limits, fallbacks between models, caching, request logging, and more. Most of the multi-user features need a database. This repo deliberately keeps the setup to a single master key so it stays simple. Everything LiteLLM supports is documented at [docs.litellm.ai](https://docs.litellm.ai/), and you can extend `LiteLLM/config.yaml` as far as you like. Pull requests that add well-tested, optional recipes are welcome (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
