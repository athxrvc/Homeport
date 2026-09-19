# Security

Putting a model on the internet means strangers *can* find it. This page explains what protects you, what doesn't, and what to do about it. Read it before you share a URL. For reporting a vulnerability, see [SECURITY.md](../SECURITY.md).

## What you're protecting

Whoever can use your gateway can use your **GPU/CPU time, electricity and model**, and see whatever they're able to make the model say. The setup has three layers of defense:

1. **The API key.** Every request must include it. This is the main protection.
2. **Ollama is never exposed.** Only LiteLLM is reachable, and Ollama listens only on your own machine.
3. **LiteLLM listens on `127.0.0.1`** by default, so nothing on your network can reach it except software on your own computer, such as the tunnel.

## Checklist

- [ ] Every start uses a non-empty `LITELLM_MASTER_KEY` (the scripts enforce this).
- [ ] `.env` is not committed, shared or pasted anywhere. It is git-ignored by default.
- [ ] Only port **4000** is ever tunnelled or forwarded. **Never 11434.**
- [ ] Nothing outside your machine can reach port 4000 directly. Leave the default `127.0.0.1` unless you understand the LAN implications.
- [ ] Logs and screenshots are scrubbed of your key and URL before you share them.
- [ ] Ollama, LiteLLM and cloudflared are kept up to date.

## The API key

- The scripts generate a random key with 256 bits of randomness. Don't replace it with something short or guessable.
- **It's a single shared secret.** Anyone you give it to has full access, and there are no per-person keys or usage limits in this setup. Share it only with people (and apps) you'd trust with your computer's resources.
- **Don't put it in client-side code**, meaning anything a browser downloads (a website's JavaScript, a mobile app you distribute). Anyone can read it from there. Keep it on servers or in local-only tools.
- **Use environment variables** in your own code rather than pasting the key into source files.

### If your key leaks, or you just want a new one

1. Stop the gateway (Ctrl+C).
2. Delete `.env` (a new key is generated on the next start), or edit the `LITELLM_MASTER_KEY` line.
3. Start it again. The old key stops working immediately.
4. Update the key in each app that uses it.

If your **Cloudflare tunnel token** leaks, rotate it in the Cloudflare dashboard (delete and recreate the tunnel's token). Note that in `named` mode with a token, the start script hands the token to `cloudflared` as a command-line argument, so other programs running as your user can see it in the process list. Don't run Homeport on a machine shared with people you don't trust. The API key, by contrast, is passed through an environment variable and is not on any command line.

## What a stranger with only your URL can see

Anyone who learns the URL can load a few pages **without a key**. (As of LiteLLM 1.101.0:)

| Reachable without a key | What it is |
|---|---|
| `/` and `/redoc` | LiteLLM's API documentation pages |
| `/openapi.json`, `/routes` | The list of API routes and their schemas |
| `/ui`, `/sso/key/generate` | LiteLLM's admin login page. Homeport runs without a database, which LiteLLM's admin UI normally needs. Logging in through it was not tested |
| `/health/liveliness`, `/health/readiness` | "I'm alive" and `{"status":"healthy","db":"Not connected"}` |
| `/test` | `{"route":"/test"}` |

That reveals that you run LiteLLM and what its API looks like, and nothing else. **Every functional endpoint requires the key**: `/v1/*`, `/key/*`, `/model/*`, `/metrics` and the rest all reject unauthenticated requests. No keys, model names, configuration or logs are exposed, and **Ollama's own API (`/api/*`) is not reachable at all**, with or without the key. LiteLLM has switches to hide its documentation pages (`NO_DOCS`, `NO_REDOC`, `DISABLE_ADMIN_UI`), but on this version they only remove `/redoc`, so Homeport doesn't set them.

If you want the public surface reduced to the API alone, put a rule in front of it (for example, a Cloudflare WAF or Access rule that only lets `/v1/*` through on a named tunnel).

## Never expose Ollama directly

Ollama has **no authentication**. If you forward port 11434, anyone who finds it can run models on your machine, download or delete models, and more. The default setup never does this: the tunnel points at LiteLLM's port 4000, and LiteLLM (which checks the key) talks to Ollama locally.

Two ways people accidentally undo this:

- Setting Ollama's `OLLAMA_HOST` to `0.0.0.0` *and* pointing a tunnel or port-forward at it.
- Configuring a tunnel's `service:` as `http://localhost:11434` instead of `http://localhost:4000`.

Check your tunnel target if you change it.

## Quick-tunnel URLs are not secret

A `trycloudflare.com` URL is random and hard to guess, but it isn't a secret: it can show up in logs, browser history, or wherever you paste it. **The API key is what actually protects you**, not the obscurity of the URL.

**Always use the `https://` form.** A quick tunnel also answers on plain `http://` and does not redirect to `https://`. Anyone using the `http://` URL sends the API key across the network unencrypted.

## Extra protection for public endpoints

If you keep a permanent public URL, consider adding layers:

- **Cloudflare Access** in front of a named tunnel's hostname, so people must also authenticate with Cloudflare (SSO, email one-time codes, and so on) before a request reaches you. See Cloudflare's [Access policies](https://developers.cloudflare.com/cloudflare-one/policies/access/). For machine-to-machine use, Cloudflare supports service tokens.
- **Rate limiting and firewall rules** on your domain in Cloudflare, to slow down brute-force and abuse.
- **A private network** ([Tailscale without Funnel](tunnels.md#option-e-private-network-tailscale-without-funnel)) if only your own devices need access. Then nothing is public at all.

> These are options to explore, not steps the maintainers have tested. Follow the vendors' documentation.

## Privacy

The model runs on your hardware, so your prompts aren't sent to a model provider. But:

- With a **public tunnel**, requests and responses pass through the relay's network on the way (Cloudflare terminates HTTPS at its edge; Tailscale Funnel similarly relays traffic). The relay is *technically able* to see the traffic. If that's not acceptable for what you're sending, use local-only or a private network.
- The start scripts write logs to `logs/`. Treat them as private, and check before pasting them publicly.
- Apps you connect may keep their own history of your conversations.

## About the error codes

You may notice that a request with a missing or wrong key comes back as HTTP **500** (missing key) or **400** (wrong key), not the standard 401. The exact codes depend on your LiteLLM version (some return 401 for a missing key).

**Requests are still rejected.** No model output is ever returned. The odd codes happen because LiteLLM's authentication-failure handler tries to load an optional database component (`prisma`) that isn't installed in a plain `litellm[proxy]` setup, and errors while building the response.

Two practical consequences:

- **Don't write client code that expects a 401** to detect a bad key. Treat any non-200 as a failure.
- **Every rejected request writes a stack trace to `logs/litellm.err.log`.** If bots discover your URL, that log can grow. It's safe to delete when the gateway is stopped, and worth an occasional look.

## Keep things updated

```bash
pip install -U "litellm[proxy]"        # or: uv tool upgrade litellm
```

Update Ollama through its app or installer, and cloudflared through your package manager (`winget upgrade Cloudflare.cloudflared`, `brew upgrade cloudflared`). Then `git pull` for this repo's changes (see the [CHANGELOG](../CHANGELOG.md)).
