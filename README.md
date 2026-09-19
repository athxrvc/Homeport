# Homeport

*A local LLM API gateway.*

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Run an AI model on your own computer, then use it from anywhere with a single URL.**

If you have a model running in [Ollama](https://ollama.com), Homeport gives it an OpenAI-compatible API, protects it with an API key, and (optionally) puts it on the internet through a free Cloudflare Tunnel. Any app, script or SDK that can talk to OpenAI can talk to your own hardware instead: your phone, your laptop, a cloud server, a friend's app.

- **Private.** Prompts are processed on your machine, not sent to a model provider. (With a public tunnel, traffic does pass through the tunnel provider's network on its way to you. Use local-only or a private Tailscale network if that matters. See [security](docs/security.md#privacy).)
- **No per-token bill.** You pay for electricity, not API calls.
- **Works with existing tools.** Anything that supports a custom OpenAI base URL: SDKs, chat UIs, editors, agents.
- **Safe by default.** An API key is required, and Ollama itself is never exposed.
- **Your choice of setup.** Quick throwaway URL, permanent URL on your own domain, Tailscale, or local only.

The catch: it works **only while your computer (and Ollama) is running**. This is a self-hosted gateway, not a hosting service.

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

- **Ollama** runs the model.
- **[LiteLLM](https://github.com/BerriAI/litellm)** translates the OpenAI API into Ollama's and checks the API key.
- **[cloudflared](https://github.com/cloudflare/cloudflared)** (optional) makes LiteLLM reachable from the internet without opening ports on your router.

This repository is the glue: a ready-made LiteLLM config, tunnel configs, start scripts that wire everything up in one command, and guides.

## Quick start

You need [Ollama](https://ollama.com), Python 3.10 to 3.13, and (only for a public URL) [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/). The [setup guide](SETUP.md) walks through installing each one on Windows, macOS and Linux.

```bash
git clone https://github.com/athxrvc/homeport.git
cd homeport

ollama pull llama3.2                  # or any model you like
pip install "litellm[proxy]"
```

Start the gateway.

Windows (PowerShell):

```powershell
.\scripts\start.ps1
```

macOS / Linux:

```bash
./scripts/start.sh
```

The first run creates a `.env` with a random API key. When everything is up, the script prints your **public URL**, your **API key**, and a command to try. Use them with any OpenAI-compatible client:

```python
from openai import OpenAI

client = OpenAI(base_url="https://<your-url>/v1", api_key="<your key>")

reply = client.chat.completions.create(
    model="llama3.2:latest",          # the exact name shown by `ollama list`
    messages=[{"role": "user", "content": "Hello!"}],
)
print(reply.choices[0].message.content)
```

Every model you have in Ollama is available under its own name. When you `ollama pull` a new one, it just works. Press **Ctrl+C** in the script's window to stop everything.

## Choose how you run it

| You want | Run | You get |
|---|---|---|
| To try it right now, no account | `.\scripts\start.ps1`<br>`./scripts/start.sh` | A free `trycloudflare.com` URL that **changes every run** |
| A permanent URL on your own domain | `-Tunnel named`<br>`--tunnel named` | e.g. `llm.yourdomain.com` (needs a Cloudflare-managed domain) |
| A permanent URL with no domain | `-Tunnel none` plus Tailscale Funnel | A stable `*.ts.net` URL |
| Local use only | `-Tunnel none`<br>`--tunnel none` | `http://localhost:4000/v1` |
| It up whenever the PC is on | a named tunnel plus autostart | See [autostart.md](docs/autostart.md) |

Details for every option: [docs/tunnels.md](docs/tunnels.md).

## Documentation

| Guide | What's in it |
|---|---|
| [SETUP.md](SETUP.md) | Step-by-step install and first run on Windows, macOS and Linux, with how to check it works |
| [docs/using-the-api.md](docs/using-the-api.md) | Calling the gateway from curl, PowerShell, Python and JavaScript; streaming; connecting apps |
| [docs/tunnels.md](docs/tunnels.md) | Quick tunnel, named tunnel, Tailscale Funnel, LAN-only, and other options |
| [docs/configuration.md](docs/configuration.md) | The config file, `.env` settings, script options, pinning models and aliases |
| [docs/autostart.md](docs/autostart.md) | Start automatically when your computer boots |
| [docs/security.md](docs/security.md) | Keeping a public endpoint safe; rotating your key |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Symptoms and fixes |
| [docs/faq.md](docs/faq.md) | Common questions |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to help |

## Security in brief

A public URL that reaches your GPU deserves care.

- Every request needs your API key. The start scripts refuse to run without one.
- Keep `.env` private (it is git-ignored) and treat the key like a password.
- Never expose Ollama's port (11434) directly. It has no authentication. Only LiteLLM is exposed.
- LiteLLM listens on `127.0.0.1` by default, so only the tunnel on your own machine can reach it.

Read [docs/security.md](docs/security.md) before publishing a URL. To report a vulnerability, see [SECURITY.md](SECURITY.md).

## What has been tested

Being upfront about this is part of being a good open-source project.

| Area | Status |
|---|---|
| Windows 11, Windows PowerShell 5.1, `start.ps1`, quick tunnel | **Tested end to end**: public URL, key rejection, chat, streaming |
| `start.sh` under Git Bash on Windows, quick tunnel | **Tested end to end** |
| Shutdown cleanup | Verified: the scripts stop LiteLLM and the tunnel when LiteLLM exits (PowerShell) or on SIGTERM (bash). A literal Ctrl+C keypress wasn't exercised |
| `start.sh` on native Linux and macOS | **Not yet tested.** It uses standard tools and should work; please report back |
| Named Cloudflare tunnel (`-Tunnel named`) | Config validated; **not tested end to end** |
| Tailscale Funnel | **Not tested** (documented from Tailscale's own docs) |
| Autostart recipes | **Not tested** |

Tested with Ollama 0.30.7, LiteLLM 1.91.0 and cloudflared 2026.7.0. If you try a combination that isn't tested yet, an issue or PR saying whether it worked is a very welcome contribution.

## Contributing

Bug reports, doc fixes, tests on other platforms and new tunnel recipes are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). A short history of changes is in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE). Use it however you like.

## Acknowledgements

This project is a thin layer over excellent work by others: [Ollama](https://github.com/ollama/ollama), [LiteLLM](https://github.com/BerriAI/litellm) and [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared).
