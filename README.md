# Homeport

*A local LLM API gateway.*

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Run an AI model on your own computer, then use it from anywhere with a single URL.**

Homeport puts an OpenAI-compatible API, an API key and (optionally) a free Cloudflare Tunnel in front of a model running in [Ollama](https://ollama.com). Any app or SDK that talks to OpenAI can talk to your own hardware instead, from your phone, your laptop or a server.

- **Private.** Prompts are processed on your machine. (A public tunnel relays traffic through the tunnel provider; use local-only or a private Tailscale network if that matters. See [security](docs/security.md#privacy).)
- **No per-token bill.** You pay for electricity.
- **Safe by default.** An API key is required, and Ollama itself is never exposed.
- **Works with existing tools.** Anything with a custom OpenAI base URL: SDKs, chat apps, editors, agents.

It works **only while your computer (and Ollama) is running**. This is a self-hosted gateway, not a hosting service.

## How it works

```text
 Your app / phone / laptop
        |   https://<your-url>/v1     (must send your API key)
        v
 Cloudflare Tunnel  ............... optional; skip it for local-only use
        |
        v
 LiteLLM   127.0.0.1:4000   OpenAI-compatible API + API-key check
        |
        v
 Ollama    127.0.0.1:11434  runs the model on your CPU/GPU
```

[LiteLLM](https://github.com/BerriAI/litellm) translates the OpenAI API into Ollama's and checks the key. [cloudflared](https://github.com/cloudflare/cloudflared) (optional) makes it reachable from the internet without opening ports on your router. This repo is the glue: configs, install and start scripts, and guides.

## Quick start

```bash
git clone https://github.com/athxrvc/homeport.git
cd homeport
```

macOS / Linux:

```bash
./scripts/install.sh
ollama pull llama3.2      # or any model you like
./scripts/start.sh
```

Windows (PowerShell):

```powershell
.\scripts\install.ps1
ollama pull llama3.2      # or any model you like
.\scripts\start.ps1
```

The install script installs whatever is missing (Ollama, LiteLLM in a private `.venv`, cloudflared, Python) and is safe to re-run. Pick any model from the [Ollama library](https://ollama.com/library); the name to use in requests is the one `ollama list` shows. The [setup guide](SETUP.md) has the step-by-step and the by-hand route.

The first run creates a `.env` with a random API key. When everything is up, the script prints your **public URL**, your **API key** and a command to try. Use them with any OpenAI-compatible client:

```python
from openai import OpenAI

client = OpenAI(base_url="https://<your-url>/v1", api_key="<your key>")

reply = client.chat.completions.create(
    model="llama3.2:latest",          # the exact name shown by `ollama list`
    messages=[{"role": "user", "content": "Hello!"}],
)
print(reply.choices[0].message.content)
```

Any model you pull later is available straight away. Press **Ctrl+C** in the script's window to stop everything.

## Choose how you run it

| You want | Run | You get |
|---|---|---|
| To try it now, no account | `.\scripts\start.ps1`<br>`./scripts/start.sh` | A free `trycloudflare.com` URL that **changes every run** |
| A permanent URL on your domain | `-Tunnel named`<br>`--tunnel named` | e.g. `llm.yourdomain.com` (needs a Cloudflare-managed domain) |
| A permanent URL, no domain | `-Tunnel none` plus Tailscale Funnel | A stable `*.ts.net` URL |
| Local use only | `-Tunnel none`<br>`--tunnel none` | `http://localhost:4000/v1` |
| It up whenever the PC is on | a named tunnel plus autostart | See [autostart](docs/autostart.md) |

## Documentation

- [Setup guide](SETUP.md): step-by-step install and first run
- [Using the API](docs/using-the-api.md): curl, PowerShell, Python and JavaScript examples; connecting apps
- [Tunnels](docs/tunnels.md): quick, named and Tailscale options
- [Configuration](docs/configuration.md): `.env`, script options, pinning models
- [Autostart](docs/autostart.md): start on boot
- [Security](docs/security.md): keeping a public endpoint safe
- [Troubleshooting](docs/troubleshooting.md) and [FAQ](docs/faq.md)
- [Contributing](CONTRIBUTING.md), [Changelog](CHANGELOG.md), [Security policy](SECURITY.md)

## Security in brief

- Every request needs your API key; the start scripts refuse to run without one.
- Keep `.env` private and treat the key like a password.
- Never expose Ollama's port (11434) directly: it has no authentication. Only LiteLLM is exposed, and it listens on `127.0.0.1` by default.

Read [security](docs/security.md) before publishing a URL.

## Status

Homeport runs on Windows and on macOS (Apple Silicon). Linux, Intel Macs, a real named Cloudflare tunnel and Tailscale haven't been tried yet, so those paths are documented but unverified. Issues are welcome.

## License

[MIT](LICENSE). Built on [Ollama](https://github.com/ollama/ollama), [LiteLLM](https://github.com/BerriAI/litellm) and [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared).
