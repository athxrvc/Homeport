# Setup Guide

From nothing installed to "my local model answers requests from anywhere". About 10 minutes plus model download time.

```text
your app --> [Cloudflare Tunnel] --> LiteLLM (:4000) --> Ollama (:11434) --> model
             (optional)
```

## 1. What you need

- A computer that can run a model: Windows, macOS or Linux. Small models (1 to 4 billion parameters) run on almost anything; 7 to 8B models want roughly 8 GB of RAM or GPU memory.
- [git](https://git-scm.com), to clone this repo.
- Python 3.10 or newer. The install script finds or installs it on Windows and macOS; on Linux, install it first (for example `sudo apt install python3 python3-venv`).

The install script handles everything else (Ollama, LiteLLM, cloudflared). You only need a Cloudflare account and domain if you want a *permanent* public URL; the default quick tunnel needs neither.

## 2. Install

```bash
git clone https://github.com/athxrvc/homeport.git
cd homeport
```

Then run the install script.

macOS / Linux:

```bash
./scripts/install.sh
```

Windows (PowerShell):

```powershell
.\scripts\install.ps1
```

It installs whatever is missing (Ollama, LiteLLM in a private `.venv` inside the project, cloudflared, and Python if needed) and is safe to re-run. On Windows it uses winget; on macOS it downloads from the official sources, with no Homebrew and no admin password. Add `--no-tunnel` (Windows: `-NoTunnel`) to skip cloudflared if you only want local use.

> **Downloaded the ZIP instead of cloning?** On Windows you'll need one extra step: see ["is not digitally signed"](docs/troubleshooting.md#launching-the-script).

<details>
<summary>Prefer to install things by hand?</summary>

- **Ollama:** the installer from [ollama.com/download](https://ollama.com/download) (Windows: `winget install Ollama.Ollama`; Linux: `curl -fsSL https://ollama.com/install.sh | sh`).
- **LiteLLM:** `pip install "litellm[proxy]"`. It needs Python 3.10+; macOS's built-in `python3` is 3.9, which is too old. If `litellm` isn't found afterwards, pip's script folder isn't on your `PATH`.
- **cloudflared** (only for a public URL): Windows `winget install --id Cloudflare.cloudflared`; macOS and Linux from Cloudflare's [download page](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/). Open a new terminal afterwards and check `cloudflared --version`.

The start scripts use the `.venv` copy of LiteLLM if it exists, otherwise whatever is on your `PATH`.

</details>

## 3. Pull a model

Homeport doesn't choose a model for you. Pull the one you want (browse the [Ollama library](https://ollama.com/library); `llama3.2` is small and good for a first test):

```bash
ollama pull llama3.2
ollama list
```

Remember the exact name in `ollama list` (for example `llama3.2:latest`): it's what clients send as `model`. Ollama runs in the background (the app on Windows and macOS, a service on Linux). If the start script later says it can't reach Ollama, start it with `ollama serve`. If `ollama` isn't found right after installing, open a new terminal.

## 4. First run: local only

Get it working on your own machine first, so if something's wrong you know it isn't the tunnel.

Windows (PowerShell):

```powershell
.\scripts\start.ps1 -Tunnel none
```

macOS / Linux:

```bash
./scripts/start.sh --tunnel none
```

It creates a `.env` file with a random API key the first time. After a few seconds you'll see:

```text
Gateway is up.
  Local URL : http://localhost:4000/v1
  API key   : sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  Models    : llama3.2:latest
```

Leave that window open and, in a **second terminal**, send a request with your key and model name. The first one can be slow while Ollama loads the model.

Windows (PowerShell):

```powershell
Invoke-RestMethod -Uri "http://localhost:4000/v1/chat/completions" -Method Post `
  -Headers @{Authorization="Bearer sk-YOUR-KEY"} -ContentType 'application/json' `
  -Body '{"model":"llama3.2:latest","messages":[{"role":"user","content":"Say hi"}]}'
```

macOS / Linux:

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-YOUR-KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.2:latest","messages":[{"role":"user","content":"Say hi"}]}'
```

You should get JSON with `"choices"` holding the model's answer. The same request **without** the key should be refused (an error, no answer; the status is usually 400 or 500 rather than 401, see [security](docs/security.md#about-the-error-codes)). Your key is in `.env` if you need it again.

Works? Stop with **Ctrl+C**. If not, see [troubleshooting](docs/troubleshooting.md). (Windows says scripts are disabled? Run `powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1 -Tunnel none`. macOS/Linux says permission denied? Run `chmod +x scripts/*.sh` once.)

## 5. Go public

Start it again without `-Tunnel none`. The default is a free **quick tunnel**:

Windows:

```powershell
.\scripts\start.ps1
```

macOS / Linux:

```bash
./scripts/start.sh
```

After 10 to 20 seconds you'll see a **Public URL** like `https://some-random-words.trycloudflare.com/v1`. Anyone with that URL **and your API key** can use your model while the window stays open. Try it from another device, such as your phone on mobile data, using the same request with the public URL instead of `http://localhost:4000`.

- A new URL can take a minute or two to start resolving, so "can't resolve host" right after startup is normal. Wait and retry.
- Quick-tunnel URLs change every run. For a permanent one, see [tunnels](docs/tunnels.md) (`-Tunnel named`, or Tailscale Funnel), and add [autostart](docs/autostart.md) to have it come up by itself.

## 6. Use it

You need three values:

| Setting | Value |
|---|---|
| **Base URL** | `https://<your-url>/v1` (or `http://localhost:4000/v1` locally) |
| **API key** | the `sk-...` key from `.env` |
| **Model** | the exact name from `ollama list` |

Put them into any OpenAI-compatible tool or SDK. Examples for curl, PowerShell, Python and JavaScript, streaming, and chat apps are in [using-the-api](docs/using-the-api.md).

## 7. Stop, update, uninstall

- **Stop:** Ctrl+C in the script's window. It stops LiteLLM and the tunnel.
- **Update:** `git pull`, then run the install script again (it upgrades LiteLLM). To update cloudflared on Windows use `winget upgrade Cloudflare.cloudflared`; on macOS and Linux delete `.venv/bin/cloudflared` and re-run the script.
- **Uninstall:** delete the project folder (that removes `.venv` and `.tools`). If you installed LiteLLM by hand, also `pip uninstall litellm`. Ollama and its models are separate; remove them with Ollama's own uninstaller.
- **Change your API key:** delete `.env` (or edit the `LITELLM_MASTER_KEY` line) and start the script again. The old key stops working immediately.
