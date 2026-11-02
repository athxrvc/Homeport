# Troubleshooting

Logs are in `logs/` inside the project: `litellm.err.log` for the gateway and `cloudflared.err.log` for the tunnel (on macOS/Linux, `litellm.log` and `cloudflared.log`).

## Check each layer in turn

The request path is **Ollama → LiteLLM → tunnel**. The first layer that fails is your problem.

1. **Ollama:** `curl http://127.0.0.1:11434/api/tags` (Windows: `curl.exe`) should list your models. If not, open the Ollama app or run `ollama serve`.
2. **Gateway, locally:** start with `-Tunnel none` and send the request from [setup step 4](../SETUP.md#4-first-run-local-only). If it fails, read `logs/litellm.err.log`.
3. **Tunnel:** only once 1 and 2 work, call your public URL the same way.

## The start script stops with an error

The script prints one of these and exits, leaving nothing running.

| Message | Cause and fix |
|---|---|
| `'litellm' not found` | Run `./scripts/install.sh` (Windows: `.\scripts\install.ps1`). It puts LiteLLM in the project's `.venv`, where the start scripts find it with no `PATH` changes. If you installed it yourself, add pip's script folder to `PATH` and open a new terminal. |
| `'cloudflared' not found` | Run the install script, or install it by hand ([setup guide](../SETUP.md#2-install)), or use `-Tunnel none`. |
| `Port 4000 is already in use` | Another program (maybe a previous run) has it. Close it, or use `-Port 4010` / `--port 4010`. To see what has it: `Get-NetTCPConnection -LocalPort 4000` (Windows) or `lsof -i :4000` (macOS/Linux). |
| `Can't reach Ollama at http://localhost:11434` | Ollama isn't running: open its app or run `ollama serve`. For Ollama on another machine or port, see [configuration](configuration.md#ollama-on-a-different-machine-or-port). |
| `Ollama has no models yet` | Pull the one you want: `ollama pull <name>` (browse the [Ollama library](https://ollama.com/library)). |
| `LITELLM_MASTER_KEY is empty in .env` | Put a key on that line, or delete `.env` to have a new one generated. The scripts won't start without a key. |
| `LiteLLM didn't come up` | Read `logs/litellm.err.log`. Usual causes: Python older than 3.10 (macOS's built-in 3.9 prints `TypeError: unsupported operand type(s) for \|`), a broken install (re-run the install script), or a syntax error in `LiteLLM/config.yaml`. The first start can take up to 30 seconds. |
| `Tunnel didn't report a URL` or `cloudflared exited before the tunnel was ready` | Quick tunnel: cloudflared couldn't reach Cloudflare. Check your internet connection, then `logs/cloudflared.err.log`. It needs outbound access on port 7844, which some corporate, school and public networks block. |
| `cloudflared exited` | Named tunnel: usually a bad token, or a config with placeholder values. See [tunnels](tunnels.md#option-b-named-cloudflare-tunnel). |
| `The tunnel (cloudflared) stopped…` or `LiteLLM exited…` | One of them died while running. The script stops the other and exits (code 1), so it never keeps running with a dead public URL. Check the log, then start it again. |

## Launching the script

- **PowerShell: "running scripts is disabled on this system":** run `powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1` (the same works for `install.ps1`).
- **PowerShell: "is not digitally signed":** you downloaded the **ZIP**, and Windows marks files from the internet (`git clone` doesn't have this problem). Remove the mark once with `Get-ChildItem -Recurse .\homeport-main | Unblock-File` (use your extracted folder's name), or use the `-ExecutionPolicy Bypass` form above.
- **macOS/Linux: "Permission denied":** run `chmod +x scripts/*.sh` once, or start it with `bash scripts/start.sh`.

## Requests fail

| Symptom | Cause and fix |
|---|---|
| **HTTP 500 with no key, 400 with a wrong key** | Your key is missing or wrong (the odd codes are a LiteLLM quirk, see [security](security.md#about-the-error-codes)). Check the `Authorization: Bearer <key>` header against `.env`. |
| **HTTP 500 with `model '...' not found`** | The name doesn't match `ollama list`. The `:latest` tag is optional; other tags (`:8b`) are required. |
| **Works on `localhost`, not on the public URL** | Check you used `https://` and the `/v1` path and that the tunnel is still running. A 404 with an empty body from a quick tunnel means cloudflared picked up your own `~/.cloudflared/config.yml` (the scripts prevent this; if you run cloudflared by hand, add `--config cloudflared/quick-tunnel.yml`). |
| **"Could not resolve host" / `ERR_NAME_NOT_RESOLVED` right after the URL was printed** | The tunnel is fine; your provider's DNS just hasn't learned the new name, which can take a minute or two. Wait and retry (don't hammer it, failed lookups get cached), switch your DNS to `1.1.1.1` or `8.8.8.8`, or try from another network. Quick-tunnel URLs also change every run, so use the newly printed one. |
| **HTTP 524 or a timeout on a long request** | Cloudflare gives up on requests with no data for about 100 seconds. Use streaming (`"stream": true`). |
| **Empty `content` with `finish_reason: "length"`** | A "thinking" model used up `max_tokens` reasoning. Raise it or omit it ([details](using-the-api.md#good-to-know)). |
| **Slow** | The first request is slow while Ollama loads the model (it unloads after ~5 idle minutes). If it's always slow, the model may be too big for your hardware or running on CPU; try a smaller one. |
| **A model dropdown is empty or shows odd entries** | The default config doesn't list models. Type the name by hand, or [pin your models](using-the-api.md#the-model-list-shows-odd-entries). |

## Leftover processes and shell quirks

- **macOS/Linux:** Ctrl+C and closing the Terminal window stop everything, but `kill -9` on the script leaves LiteLLM and cloudflared running (and the public URL working). Stop them with `pkill -f litellm; pkill -f cloudflared`. Note that stopping only LiteLLM leaves the tunnel up, returning HTTP 502, and that `pkill -f cloudflared` stops *every* cloudflared on the machine, including a named-tunnel service, so look first with `pgrep -fl cloudflared`.
- **Windows:** ending the script any way (Ctrl+C, closing the window, "End task", `Stop-ScheduledTask`) also ends LiteLLM and the tunnel. If you run `litellm` yourself and a port stays busy, end the whole process tree with `taskkill /PID <pid> /T /F`.
- **Windows PowerShell:** `curl` is an alias for `Invoke-WebRequest`. Use `curl.exe`, or `Invoke-RestMethod` as in [using the API](using-the-api.md#powershell-windows).

## Still stuck?

Open an [issue](https://github.com/athxrvc/homeport/issues/new/choose) with your OS, versions and the relevant log lines. **Remove your API key, tunnel token and tunnel URL first.**
