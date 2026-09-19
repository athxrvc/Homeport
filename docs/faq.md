# FAQ

## The basics

**What is this, in one sentence?**
A ready-made setup that gives a model running in Ollama an API-key-protected, OpenAI-compatible URL you can use from anywhere.

**Is it free?**
The project is free and MIT-licensed, and so are Ollama, LiteLLM and a Cloudflare quick tunnel. You pay for your own electricity, and a domain (a few dollars a year) if you want a permanent Cloudflare URL. Tailscale Funnel needs no domain.

**Do I need to keep my computer on?**
Yes. The model runs on your machine, so the URL only works while your computer, Ollama and the gateway are running. See [autostart.md](autostart.md) to have it start on boot.

**Do I need a GPU?**
No. Ollama can run models on CPU, just more slowly. Small models (1 to 4 billion parameters) are usable on ordinary laptops. Bigger models want a GPU with enough memory.

**Is it private?**
The model runs on your machine, so your prompts aren't sent to an AI provider. With a *public tunnel*, traffic does pass through the tunnel provider's network. For maximum privacy use local-only or a private Tailscale network. See [security.md](security.md#privacy).

## Design questions

**Ollama already has an OpenAI-compatible API. Why add LiteLLM?**
Ollama's API has no authentication, and exposing it to the internet would let anyone use your machine. LiteLLM sits in front of it, requires an API key, and keeps Ollama private on your own computer. It also makes it easy to alias models and to expand later.

**Why Cloudflare Tunnel?**
It's free, needs no router configuration or static IP, and provides HTTPS. You aren't locked into it: [other options](tunnels.md) work, including Tailscale and anything that can forward to port 4000.

**What does the start script change on my computer?**
Very little. It creates `.env` and `logs/` in the project folder, and runs LiteLLM and (optionally) cloudflared as child processes that it stops when you press Ctrl+C. It installs nothing and changes no system settings.

**Why a catch-all model config instead of listing my models?**
So it works with zero setup and picks up new `ollama pull`s automatically. The cost is that `/v1/models` doesn't list your real models. If that matters to you, [pin them](configuration.md#pinning-models-and-creating-aliases).

## Using it

**Which apps does it work with?**
Anything that can talk to an OpenAI-compatible API with a custom base URL. Chat interfaces, editors, agents and SDKs generally can. It has been tested with curl, PowerShell, and the official OpenAI Python and JavaScript SDKs. See [using-the-api.md](using-the-api.md).

**Can I share it with friends?**
You can give them the URL and key, but it's one shared key with no per-person limits or logs, so anyone with it has full access to your machine's model. Only share with people you trust, and change the key afterwards if you want to revoke access ([how](security.md#if-your-key-leaks-or-you-just-want-a-new-one)). Per-user keys are possible with LiteLLM's advanced features but aren't set up here.

**Does it support images (vision), tool/function calling or embeddings?**
The gateway passes requests to LiteLLM and Ollama, so it depends on what LiteLLM, Ollama and your chosen model support. Only text chat and streaming are tested in this repo.

**Can it serve more than one model at a time?**
Yes. Every model you've pulled is reachable by name. How many run at once, and how fast, is up to Ollama and your hardware.

**Can I run it on a server, a Raspberry Pi or a home server?**
Any machine that can run Ollama, LiteLLM and (optionally) cloudflared should work. Only Windows (PowerShell and Git Bash) has been tested by the maintainers so far. See the [tested matrix](../README.md#what-has-been-tested).

**Is there a Docker setup?**
Not yet. The scripts run everything natively. A tested Docker Compose setup would be a great contribution. See [CONTRIBUTING.md](../CONTRIBUTING.md).

## Troubleshooting pointers

**Why do I get HTTP 500 instead of 401 when my key is wrong?**
A LiteLLM quirk; requests are still rejected. See [security.md](security.md#about-the-error-codes).

**My quick-tunnel URL changed.**
That's how quick tunnels work. Use a [named tunnel or Tailscale Funnel](tunnels.md) for a permanent one.

More in [troubleshooting.md](troubleshooting.md).

## About the project

**Can I use it for commercial work?**
The MIT license allows it. You're responsible for complying with the licenses and terms of the pieces you run: your chosen model's license, Ollama, LiteLLM, and Cloudflare's or Tailscale's terms.

**How do I contribute?**
See [CONTRIBUTING.md](../CONTRIBUTING.md). Testing on other platforms is especially valuable.
