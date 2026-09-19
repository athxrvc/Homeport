# Tunnels: getting a URL you can use from anywhere

Your computer normally isn't reachable from the internet: it's behind your home router and has no public address. A **tunnel** solves that. A small program on your computer makes an outbound connection to a relay service, and the relay hands out a public URL that forwards traffic back through that connection. You don't open router ports or need a static IP.

## Which option should I use?

| Option | URL | Needs | Best for |
|---|---|---|---|
| [**A. Quick tunnel**](#option-a-quick-tunnel-default) | random, changes every run | cloudflared | Trying it out, temporary sharing |
| [**B. Named Cloudflare tunnel**](#option-b-named-cloudflare-tunnel) | permanent, on your domain | cloudflared, a Cloudflare account and a domain | A stable URL you can put in apps |
| [**C. Tailscale Funnel**](#option-c-tailscale-funnel) | permanent `*.ts.net` | Tailscale account | A stable public URL with no domain |
| [**D. No tunnel / LAN**](#option-d-no-tunnel-local-or-lan-only) | `http://localhost:4000` or your LAN IP | nothing | Same machine or home network only |
| [**E. Private Tailscale network**](#option-e-private-network-tailscale-without-funnel) | private tailnet IP | Tailscale on each device | Only *your own* devices, nothing public |
| [**F. Something else**](#option-f-anything-else) | whatever you set up | your tooling | ngrok, your own server, a VPN... |

Not sure? Start with **A**. When you want something permanent, move to **B** (if you have a domain) or **C** (if you don't).

## A note on privacy

The model runs on your machine, so your prompts are never sent to a model provider. But with a **public tunnel** (A, B, C), requests and responses travel through the tunnel provider's network on the way to you. For example, Cloudflare terminates HTTPS at its edge. Your API key protects access; it doesn't hide the traffic from the relay. If that matters for what you're sending, use option D or E.

## Option A: Quick tunnel (default)

This is what `start.ps1` / `start.sh` do when you don't pick anything else.

```powershell
.\scripts\start.ps1                 # Windows
```

```bash
./scripts/start.sh                  # macOS / Linux
```

- **Free, no account, no domain.**
- You get a URL like `https://some-random-words.trycloudflare.com`. It is **new every time** you start the script.
- Cloudflare says these account-less tunnels come with no uptime guarantee, so they're meant for experiments, not for something you depend on.
- Because the URL changes, it isn't suitable for [autostart](autostart.md).

**Why the script passes its own config file for this.** If you've ever used cloudflared before, you may have `~/.cloudflared/config.yml` (`%USERPROFILE%\.cloudflared\config.yml` on Windows). cloudflared loads it automatically, and its rules would override a quick tunnel, making every request return 404. The script passes [`cloudflared/quick-tunnel.yml`](../cloudflared/quick-tunnel.yml), a config that deliberately has no ingress rules, to avoid that. If you run `cloudflared tunnel --url ...` yourself and get 404s, add `--config cloudflared/quick-tunnel.yml`.

## Option B: Named Cloudflare tunnel

A **named tunnel** gives you a permanent URL on a domain you own (for example `llm.yourdomain.com`). It survives restarts, so it's the right choice for autostart and for pasting into apps.

You need:

- A free [Cloudflare account](https://dash.cloudflare.com/sign-up)
- A domain whose DNS is managed by Cloudflare (buy one through Cloudflare or point an existing domain's nameservers at it)
- `cloudflared` installed ([setup step 4](../SETUP.md#4-install-cloudflared-for-a-public-url))

Pick **one** of the two methods.

### B1. Dashboard and token (easiest)

1. In the Cloudflare dashboard, open **Zero Trust → Networks → Tunnels** and create a tunnel of type **Cloudflared**. (Menu names shift occasionally. Cloudflare's [tunnel guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/) is the up-to-date reference.)
2. Add a **public hostname**: choose your domain and a subdomain such as `llm`, set the service type to **HTTP**, and the URL to `localhost:4000`.
3. Copy the tunnel **token** Cloudflare shows you.
4. Put it in `.env`:

   ```ini
   CLOUDFLARE_TUNNEL_TOKEN=eyJ...your-token...
   PUBLIC_URL=https://llm.yourdomain.com
   ```

   `PUBLIC_URL` is optional; it just lets the script print your URL for you.
5. Run:

   ```powershell
   .\scripts\start.ps1 -Tunnel named
   ```

   ```bash
   ./scripts/start.sh --tunnel named
   ```

Treat the token like a password. Anyone with it can run your tunnel.

### B2. Command line and config file

```bash
cloudflared tunnel login                       # opens a browser; pick your domain
cloudflared tunnel create homeport             # prints a tunnel UUID and writes a credentials .json
cloudflared tunnel route dns homeport llm.yourdomain.com
```

Then either:

- **Edit the repo's template**, [`cloudflared/config.yml`](../cloudflared/config.yml): fill in your tunnel UUID, the path to the credentials JSON, and your hostname; **or**
- **Use cloudflared's standard config** at `~/.cloudflared/config.yml` and leave the repo template untouched. The scripts detect the untouched template (it still contains `<TUNNEL-UUID>`) and fall back to cloudflared's default config automatically.

A working config looks like this:

```yaml
tunnel: 01234567-89ab-cdef-0123-456789abcdef
credentials-file: C:\Users\you\.cloudflared\01234567-89ab-cdef-0123-456789abcdef.json   # Windows path shown

ingress:
  - hostname: llm.yourdomain.com          # bare hostname: NO "https://"
    service: http://localhost:4000

  - service: http_status:404              # required catch-all
```

Check the rules before running:

```bash
cloudflared tunnel --config cloudflared/config.yml ingress validate
```

Then start with `-Tunnel named` / `--tunnel named`. Leave `CLOUDFLARE_TUNNEL_TOKEN` empty in `.env`, otherwise the token takes priority.

> **Status:** the config template validates and the scripts choose the right `cloudflared` arguments for each case, but the maintainers haven't brought up a real named tunnel end to end (that needs a Cloudflare account and a domain). Feedback is welcome.

Optional extra protection: put [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/) in front of the hostname so callers must also authenticate with Cloudflare. See [security.md](security.md).

## Option C: Tailscale Funnel

[Tailscale Funnel](https://tailscale.com/kb/1223/funnel) publishes a local service at a stable HTTPS URL like `https://your-machine.your-tailnet.ts.net`, with no domain to buy.

1. Install Tailscale and sign in.
2. Enable HTTPS and Funnel for your tailnet, following Tailscale's [Funnel guide](https://tailscale.com/kb/1223/funnel). This is a one-time setup in their admin console.
3. Start the gateway **without** a Cloudflare tunnel, then point Funnel at it:

   ```bash
   ./scripts/start.sh --tunnel none             # or: .\scripts\start.ps1 -Tunnel none
   tailscale funnel 4000
   ```

Tailscale prints the public URL. Use it as your base URL (`https://<machine>.<tailnet>.ts.net/v1`).

> **Status:** not tested by the maintainers. This follows Tailscale's own documentation.

## Option D: No tunnel (local or LAN only)

```powershell
.\scripts\start.ps1 -Tunnel none
```

- Serves `http://localhost:4000/v1` on the same machine. Nothing is exposed.
- **To allow other devices on your home network**, also bind to all interfaces: `-BindHost 0.0.0.0` (`--host 0.0.0.0`), then use `http://<this-PC's-LAN-IP>:4000/v1`. The API key still applies, but the traffic isn't encrypted, so only do this on a network you trust. You may also need to allow port 4000 through your OS firewall.

## Option E: Private network (Tailscale without Funnel)

If only *your own* devices need to reach the model, you don't need anything public at all. Put those devices on the same [Tailscale](https://tailscale.com) network, start the gateway bound to your Tailscale address, and connect to that address from your other devices:

```bash
./scripts/start.sh --tunnel none --host <this-machine's-tailscale-ip>
# from another device on your tailnet: http://<that-ip>:4000/v1
```

Tailscale encrypts the traffic between your devices, and nothing is reachable from the public internet. This is the most private option.

> **Status:** not tested by the maintainers.

## Option F: Anything else

The gateway is just an HTTP server on `127.0.0.1:4000`, so anything that can forward traffic to it works: ngrok, a reverse proxy on a server you own (Caddy, nginx) reached over a VPN or SSH tunnel, WireGuard, and so on. Start with `-Tunnel none` and point your tool at `http://127.0.0.1:4000`.

Whatever you use, **only ever forward port 4000 (LiteLLM), never Ollama's port 11434**, and keep the API key on. See [security.md](security.md).

## Comparing the public options

| | Quick (A) | Named (B) | Tailscale Funnel (C) |
|---|---|---|---|
| Cost | Free | Free tunnel; you need a domain (a few dollars a year) | Free tier available |
| Account needed | No | Cloudflare | Tailscale |
| URL stable | No | Yes | Yes |
| Good for autostart | No | Yes | Yes |
