# Troubleshooting

Find your symptom below. If you're stuck, the [diagnosis routine](#diagnosis-check-each-layer-in-turn) right after this paragraph finds the broken layer in about a minute. Logs are in `logs/` inside the project folder: `litellm.err.log` (and `litellm.out.log`) for the gateway, `cloudflared.err.log` for the tunnel. On macOS/Linux, `litellm.log` and `cloudflared.log`.

## Diagnosis: check each layer in turn

The request path has layers: **Ollama → LiteLLM → tunnel**. Test from the inside out; the first one that fails is your problem.

**1. Is Ollama working?**

```bash
curl http://127.0.0.1:11434/api/tags
```

(On Windows PowerShell, use `curl.exe`, or `Invoke-RestMethod http://127.0.0.1:11434/api/tags`.) You should get JSON listing your models. If not, Ollama isn't running: open the Ollama app or run `ollama serve`.

**2. Is the gateway working locally?** Start with `-Tunnel none` and try the request from [SETUP.md step 6](../SETUP.md#6-first-run-local-only). If that fails, the problem is LiteLLM or your config. Read `logs/litellm.err.log`.

**3. Does the tunnel work?** Only once 1 and 2 pass. Call your public URL the same way. If local works but public doesn't, the problem is the tunnel or the URL you're using.

## The start script stops with an error

The scripts print one of these messages and exit. Nothing is left running.

| Message | Cause and fix |
|---|---|
| `'litellm' not found` | LiteLLM isn't installed, or its folder isn't on your `PATH`. Run `pip install "litellm[proxy]"`. If it's installed, add pip's script folder to `PATH` (Windows: `...\Python3xx\Scripts`; Linux/macOS: often `~/.local/bin`) and open a **new** terminal. With uv: `uv tool update-shell`. |
| `'cloudflared' not found` | Install it ([setup step 4](../SETUP.md#4-install-cloudflared-for-a-public-url)) and open a new terminal, or use `-Tunnel none`. |
| `Port 4000 is already in use` | Something else is using the port, maybe a previous run still going. Close it, or use another port: `-Port 4010` / `--port 4010`. To see what's on it: `Get-NetTCPConnection -LocalPort 4000` (Windows) or `lsof -i :4000` (macOS/Linux). |
| `Can't reach Ollama at http://localhost:11434` | Ollama isn't running. Open the Ollama app or run `ollama serve`, then retry. If Ollama runs on a different machine or port, see [configuration.md](configuration.md#ollama-on-a-different-machine-or-port). |
| `Ollama has no models yet` | Pull one: `ollama pull llama3.2`. |
| `LITELLM_MASTER_KEY is empty in .env` | The `LITELLM_MASTER_KEY=` line in `.env` has no value. Put a key there, or delete `.env` to have a new one generated. The scripts won't start without an API key. |
| `LiteLLM didn't come up` | Read `logs/litellm.err.log`. Common causes: an unsupported Python version (LiteLLM needs 3.10 to 3.13), a broken install (try `pip install -U "litellm[proxy]"`), or a config file syntax error. The first start can take 10 to 30 seconds, so a slow disk or antivirus scan may need a retry. |
| `Tunnel didn't report a URL` | See `logs/cloudflared.err.log`. cloudflared needs outbound access to Cloudflare on port 7844. Some corporate, school and public networks block it, so try another network. |
| `cloudflared exited` | Named tunnel only. See `logs/cloudflared.err.log`. Usually a bad token, or a config file with wrong or placeholder values. See [tunnels.md](tunnels.md#option-b-named-cloudflare-tunnel). |

## Launching the script

**PowerShell: "running scripts is disabled on this system"**

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

**macOS/Linux: "Permission denied"**

```bash
chmod +x scripts/start.sh        # once
# or run it through bash without changing permissions:
bash scripts/start.sh
```

**Bash: `\r: command not found` or `bad interpreter`.** The file got Windows (CRLF) line endings, for example from a ZIP download or an editor. Convert it:

```bash
sed -i 's/\r$//' scripts/start.sh        # on macOS: sed -i '' 's/\r$//' scripts/start.sh
```

## Requests fail

| Symptom | Cause and fix |
|---|---|
| **HTTP 500 with no key, or 400 `No connected db` with a wrong key** | Your key is missing or wrong. These odd codes are a known LiteLLM quirk rather than a gateway fault. See [security.md](security.md#about-the-error-codes). Check the `Authorization: Bearer <key>` header and that the key matches `.env`. |
| **HTTP 500 with `model '...' not found`** | The model name doesn't match Ollama's. Compare with `ollama list`. The `:latest` tag is optional, but other tags are required (`:8b`). Check spelling. |
| **Works on `localhost`, fails on the public URL** | Test the layers above. Also check you used `https://` and the `/v1` path, and that the tunnel process is still running. |
| **Public URL returns 404 with an empty body** | Quick tunnel only: cloudflared picked up your `~/.cloudflared/config.yml` and its rules overrode the quick tunnel. The scripts already prevent this. If you run cloudflared by hand, add `--config` pointing to an empty YAML file (see [tunnels.md](tunnels.md#option-a-quick-tunnel-default)). |
| **Public URL stopped working / "can't resolve host"** | Quick-tunnel URLs change every time you start. Use the newly printed URL. For a permanent one, see [tunnels.md](tunnels.md). |
| **HTTP 524 or a timeout on a long request** | Cloudflare gives up on requests that return no data for a long time (roughly 100 seconds). Use streaming (`"stream": true`), which sends data continuously. |
| **Reply has empty `content`, `finish_reason` is `"length"`** | A "thinking" model spent its whole `max_tokens` budget reasoning. Raise `max_tokens` or omit it. See [using-the-api.md](using-the-api.md#good-to-know). |
| **The first request is very slow** | Ollama is loading the model into memory (and unloads it after ~5 idle minutes by default). Later requests are faster. |
| **Very slow responses all the time** | The model may be too big for your hardware, or running on CPU instead of GPU. That's Ollama's territory. Try a smaller model, and check Ollama's GPU documentation. |
| **An app's model dropdown is empty or shows `*`** | The default catch-all config doesn't enumerate models. Type the name manually, or pin models. See [using-the-api.md](using-the-api.md#the-model-list-shows-odd-entries). |

## Windows-specific

**`UnicodeEncodeError: 'charmap' codec can't encode characters` when starting LiteLLM.** This only happens when you run `litellm` yourself with its output redirected to a file. The start scripts already handle it. Fix it for your own runs by setting `PYTHONUTF8=1` first (`$env:PYTHONUTF8 = "1"` in PowerShell).

**Ports stay busy after the window closes.** `litellm.exe` starts Python as a child process. If the parent is killed forcefully, the child can survive. Kill the whole tree: `taskkill /PID <pid> /T /F`. Ctrl+C in the script's window shuts everything down properly.

**PowerShell `curl` behaves strangely.** In Windows PowerShell 5.1, `curl` is an alias for `Invoke-WebRequest`. Use `curl.exe` explicitly, or `Invoke-RestMethod` as shown in [using-the-api.md](using-the-api.md#powershell-windows).

## Still stuck?

Open an [issue](https://github.com/athxrvc/Local-LLM-API-Gateway/issues/new/choose) with your OS, versions and the relevant log lines. **Remove your API key, tunnel token and tunnel URL first.**
