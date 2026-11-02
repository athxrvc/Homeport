# Security

Putting a model on the internet means strangers *can* find it. Whoever can use your gateway can use your GPU/CPU time and your model. Three things protect you:

1. **The API key.** Every request must include it. This is the main protection.
2. **Ollama is never exposed.** Only LiteLLM is reachable; Ollama listens only on your own machine.
3. **LiteLLM listens on `127.0.0.1`** by default, so only software on your computer (such as the tunnel) can reach it.

To report a vulnerability in Homeport itself, see [SECURITY.md](../SECURITY.md).

## The API key

- The scripts generate a random 256-bit key and refuse to start without one. Don't replace it with something short.
- **It's one shared secret.** Anyone who has it has full access; there are no per-person keys or limits. Share it only with people and apps you trust.
- **Keep it out of client-side code** (a website's JavaScript, a distributed app). Use environment variables in your own code.
- **Keep `.env` private.** `start.sh` creates it readable only by you (`chmod 600`); if yours was made by hand or earlier, run `chmod 600 .env`. The start script also prints the key, so if you redirect its output to a file (a launchd `StandardOutPath`, `nohup ... > file`), that file contains it.
- Scrub your key and URL from logs and screenshots before sharing them.

### If your key leaks, or you just want a new one

Stop the gateway, delete `.env` (or edit the `LITELLM_MASTER_KEY` line), and start it again. The old key stops working immediately. Then update the key in each app that uses it.

A leaked **Cloudflare tunnel token** is rotated in the Cloudflare dashboard. In `named` mode with a token, the start script passes the token to `cloudflared` on its command line, so other programs running as your user can see it; don't run Homeport on a machine shared with people you don't trust.

## What a stranger with only your URL can see

A few LiteLLM pages load **without a key**: its API documentation (`/`, `/redoc`, `/openapi.json`, `/routes`), an admin login page (`/ui`), and health checks. That reveals that you run LiteLLM and what its API looks like, nothing more. Every functional endpoint (`/v1/*`, `/key/*`, `/model/*`, `/metrics`) rejects requests without the key, and Ollama's own API (`/api/*`) isn't reachable at all.

LiteLLM has switches to hide those pages (`NO_DOCS`, `NO_REDOC`, `DISABLE_ADMIN_UI`), but as of 1.101.0 they only remove `/redoc`, so Homeport doesn't set them. If you want only the API exposed, put a rule in front of a named tunnel (for example a Cloudflare WAF rule that lets only `/v1/*` through).

## Never expose Ollama directly

Ollama has **no authentication**: anyone who reaches port 11434 can run models on your machine, and download or delete them. The default setup never exposes it: the tunnel points at LiteLLM's port 4000, which checks the key and talks to Ollama locally. Only tunnel or forward port **4000**, never 11434. Two ways people undo this by accident: setting `OLLAMA_HOST` to `0.0.0.0` *and* forwarding it, or pointing a tunnel's `service:` at `http://localhost:11434` instead of `4000`.

## Quick-tunnel URLs are not secret

A `trycloudflare.com` URL is random but not secret: it can show up in logs, browser history, or wherever you paste it. The key is what protects you. **Always use the `https://` form**: a quick tunnel also answers on plain `http://` without redirecting, and anyone using that sends the key unencrypted.

## Extra protection for public endpoints

If you keep a permanent URL, consider [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/) in front of the hostname (so callers must also authenticate with Cloudflare), Cloudflare rate limiting and firewall rules, or a private network ([Tailscale without Funnel](tunnels.md#option-e-private-network-tailscale-without-funnel)) if only your own devices need access. Follow the vendors' documentation for these.

## Privacy

Prompts are processed on your hardware, not sent to a model provider. But:

- With a **public tunnel**, traffic passes through the relay's network (Cloudflare terminates HTTPS at its edge; Tailscale Funnel similarly relays). It is technically able to see the traffic. Use local-only or a private network if that matters for what you send.
- The start scripts write logs to `logs/`; treat them as private.
- Apps you connect may keep their own history of your conversations.

## About the error codes

A request with a missing or wrong key comes back as HTTP **500** or **400**, not the standard 401 (the exact codes depend on your LiteLLM version). **It is still rejected and no model output is returned.** The odd codes come from LiteLLM's auth-failure handler looking for an optional database component that a plain `litellm[proxy]` install doesn't have.

So don't write client code that expects a 401; treat any non-200 as a failure. Also, every rejected request writes a stack trace to `logs/litellm.err.log`, which can grow if bots find your URL. It's safe to delete when the gateway is stopped.

## Keep things updated

Re-run the install script to upgrade LiteLLM, update Ollama through its app or installer, and `git pull` for this repo's changes. See [SETUP](../SETUP.md#7-stop-update-uninstall) for cloudflared.
