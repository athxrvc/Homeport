# Setup Guide

This guide takes you from nothing installed to "my local model answers requests from anywhere". It takes about 10 minutes plus model download time. Every step says what you should see, so you know it worked before moving on.

**What you'll set up**

```text
your app --> [Cloudflare Tunnel] --> LiteLLM (:4000) --> Ollama (:11434) --> model
             (optional)
```

**Contents**

1. [What you need](#1-what-you-need)
2. [Install Ollama and pull a model](#2-install-ollama-and-pull-a-model)
3. [Install LiteLLM](#3-install-litellm)
4. [Install cloudflared (for a public URL)](#4-install-cloudflared-for-a-public-url)
5. [Get the project](#5-get-the-project)
6. [First run: local only](#6-first-run-local-only)
7. [Go public](#7-go-public)
8. [Use it](#8-use-it)
9. [Stop, update, uninstall](#9-stop-update-uninstall)
10. [Where to go next](#10-where-to-go-next)

## 1. What you need

| Requirement | Notes |
|---|---|
| A computer that can run a model | Windows 10/11, macOS or Linux. Smaller models (1 to 4 billion parameters) run on almost anything. 7 to 8B models want roughly 8 GB of RAM or GPU memory; larger models want more. |
| [Ollama](https://ollama.com) | Runs the model. |
| Python **3.10 to 3.13** and pip | For LiteLLM. Check with `python --version`. |
| [git](https://git-scm.com) | To clone this repo (or download the ZIP from GitHub instead). |
| [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) | **Only** for a public URL. Skip it for local-only use. |
| A Cloudflare account and domain | **Only** for a permanent URL. The default quick tunnel needs neither. |

## 2. Install Ollama and pull a model

**Windows:** run the installer from [ollama.com/download](https://ollama.com/download), or:

```powershell
winget install Ollama.Ollama
```

**macOS:** download the app from [ollama.com/download](https://ollama.com/download).

**Linux:**

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Check it's installed:

```bash
ollama --version
```

Pull a model. `llama3.2` is a small, fast one that's good for a first test; browse others in the [Ollama library](https://ollama.com/library).

```bash
ollama pull llama3.2
ollama list
```

You should see your model listed, for example `llama3.2:latest`. **Remember that exact name**, because it is what clients will send as `model`.

Optional sanity check that the model itself works:

```bash
ollama run llama3.2 "Say hello in five words"
```

Ollama runs a background service on port 11434. On Windows and macOS the Ollama app starts it for you. On Linux the installer sets up a service. If the start script later says it can't reach Ollama, start it with `ollama serve`.

## 3. Install LiteLLM

Either of these works.

**Option 1: pip** (simplest):

```bash
pip install "litellm[proxy]"
```

**Option 2: [uv](https://docs.astral.sh/uv/)** (keeps it isolated from your other Python packages):

```bash
uv tool install "litellm[proxy]"
```

Check that the `litellm` command is found:

```bash
litellm --help
```

If you get "command not found" (or "not recognized"), the folder pip installed it into isn't on your `PATH`. On Windows that's usually `...\Python3xx\Scripts`; on Linux and macOS often `~/.local/bin`. Add it to `PATH` and open a new terminal. With uv, run `uv tool update-shell`.

## 4. Install cloudflared (for a public URL)

Skip this step if you only want local use.

**Windows:**

```powershell
winget install --id Cloudflare.cloudflared
```

**macOS:**

```bash
brew install cloudflared
```

**Linux:** follow Cloudflare's [download page](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/), which has packages for Debian/Ubuntu, RHEL/Fedora and others.

Open a **new** terminal afterwards, and check:

```bash
cloudflared --version
```

## 5. Get the project

```bash
git clone https://github.com/athxrvc/homeport.git
cd homeport
```

## 6. First run: local only

Get it working on your own machine before adding the internet. That way, if something's wrong, you know it isn't the tunnel.

Windows (PowerShell):

```powershell
.\scripts\start.ps1 -Tunnel none
```

macOS / Linux:

```bash
./scripts/start.sh --tunnel none
```

> **PowerShell says scripts are disabled?** Run it as `powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1 -Tunnel none`.
> **macOS/Linux says permission denied?** Run `chmod +x scripts/start.sh` once.

The first time, it creates a `.env` file with a randomly generated API key. After LiteLLM starts (the first launch can take 10 to 30 seconds), you'll see something like:

```text
Gateway is up.
  Local URL : http://localhost:4000/v1
  API key   : sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  Models    : llama3.2:latest
```

Leave that window open. In a **second terminal**, try three things.

**1. A request with your key should get a reply** (use your key and model name):

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

The first request can take a while, since Ollama is loading the model into memory. You should get back JSON containing `"choices"` with the model's answer.

**2. A request without the key should be refused.** Run the same command without the `Authorization` header. You should get an error and **no** model answer. (The status code is usually 400 or 500 rather than 401. That's a quirk of LiteLLM's error handling and is harmless. See [docs/security.md](docs/security.md#about-the-error-codes).)

**3. Your key** lives in `.env` if you need to look it up again.

Everything worked? Stop the gateway with **Ctrl+C** and continue. If something didn't, see [docs/troubleshooting.md](docs/troubleshooting.md).

## 7. Go public

Start it again without `-Tunnel none`. The default is a free **quick tunnel**:

Windows:

```powershell
.\scripts\start.ps1
```

macOS / Linux:

```bash
./scripts/start.sh
```

After a few seconds you'll see a **Public URL** like `https://some-random-words.trycloudflare.com/v1`. That's it. Anyone who has that URL **and your API key** can use your model while this window stays open.

Test it from another device (your phone on mobile data is a great check that it's truly reachable from anywhere) using the same request as above, with the public URL in place of `http://localhost:4000`.

**Quick-tunnel URLs change every time you start the script.** That's fine for trying things out. For a permanent URL, see the options in [docs/tunnels.md](docs/tunnels.md):

- **Your own domain on Cloudflare:** `-Tunnel named` / `--tunnel named`
- **No domain:** Tailscale Funnel
- **Always on:** add [autostart](docs/autostart.md)

## 8. Use it

You need three values:

| Setting | Value |
|---|---|
| **Base URL** | `https://<your-url>/v1` (or `http://localhost:4000/v1` locally) |
| **API key** | the `sk-...` key from `.env` |
| **Model** | the exact name from `ollama list`, e.g. `llama3.2:latest` |

Put those into any OpenAI-compatible tool or SDK. Worked examples for curl, PowerShell, Python and JavaScript, streaming, and connecting chat apps are in [docs/using-the-api.md](docs/using-the-api.md).

## 9. Stop, update, uninstall

**Stop:** press **Ctrl+C** in the window running the script. It stops LiteLLM and the tunnel for you.

**Update:**

```bash
git pull
pip install -U "litellm[proxy]"        # or: uv tool upgrade litellm
```

Updating cloudflared: `winget upgrade Cloudflare.cloudflared` on Windows, `brew upgrade cloudflared` on macOS.

**Uninstall:** delete the project folder, then `pip uninstall litellm` (or `uv tool uninstall litellm`). Ollama and its models are separate. Remove those from Ollama's own uninstaller if you want.

**Change your API key:** delete `.env` (or edit the `LITELLM_MASTER_KEY` line) and start the script again. Old keys stop working immediately.

## 10. Where to go next

- [docs/using-the-api.md](docs/using-the-api.md): code examples and app connections
- [docs/tunnels.md](docs/tunnels.md): permanent URLs
- [docs/autostart.md](docs/autostart.md): start on boot
- [docs/configuration.md](docs/configuration.md): change ports, pin models, add aliases
- [docs/security.md](docs/security.md): read before sharing your URL
- [docs/troubleshooting.md](docs/troubleshooting.md): when something's off
