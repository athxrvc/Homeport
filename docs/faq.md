# FAQ

**Do I need a GPU?**
No. Ollama can run models on CPU, just more slowly. Small models (1 to 4 billion parameters) are usable on ordinary laptops; bigger ones want a GPU with enough memory.

**Why add LiteLLM? Ollama already has an OpenAI-compatible API.**
Ollama's API has no authentication, so exposing it to the internet would let anyone use your machine. LiteLLM sits in front, requires an API key, and keeps Ollama private on your computer.

**What does the install/start script change on my computer?**
The install script installs what's missing (see [SETUP](../SETUP.md#2-install)). The start script only creates `.env` and `logs/` in the project folder and runs LiteLLM and (optionally) cloudflared, which it stops when you press Ctrl+C. It changes no system settings.

**Can I share it with friends?**
You can give them the URL and key, but it's one shared key with no per-person limits, so anyone with it has full access to your model. Share it only with people you trust, and [change the key](security.md#if-your-key-leaks-or-you-just-want-a-new-one) to revoke access. Per-user keys are possible with LiteLLM's advanced features but aren't set up here.

**Does it support images (vision), tool calling or embeddings?**
That depends on what LiteLLM, Ollama and your model support; the gateway passes requests through. This guide only covers text chat and streaming.

**Can it serve more than one model?**
Yes. Every model you've pulled is reachable by name. How many run at once, and how fast, is up to Ollama and your hardware.

**Can I run it on a server or a Raspberry Pi?**
Anything that can run Ollama, LiteLLM and (optionally) cloudflared should work. See [Status](../README.md#status) for what has been tried.

**Is there a Docker setup?**
Not yet. A Docker Compose setup would be a great [contribution](../CONTRIBUTING.md).

**Can I use it commercially?**
The MIT license allows it. You're responsible for the licenses and terms of the pieces you run: your model, Ollama, LiteLLM, and Cloudflare's or Tailscale's terms.
