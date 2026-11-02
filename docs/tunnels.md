# Tunnels: a URL you can use from anywhere

Your computer sits behind your router with no public address. A **tunnel** fixes that: a small program on your computer makes an outbound connection to a relay, and the relay gives you a public URL that forwards back through it. No router ports to open, no static IP.

| Option | URL | Needs | Best for |
|---|---|---|---|
| [**A. Quick tunnel**](#option-a-quick-tunnel-default) | random, changes every run | cloudflared | Trying it out |
| [**B. Named Cloudflare tunnel**](#option-b-named-cloudflare-tunnel) | permanent, on your domain | Cloudflare account and a domain | A stable URL for apps and autostart |
| [**C. Tailscale Funnel**](#option-c-tailscale-funnel) | permanent `*.ts.net` | Tailscale account | A stable public URL with no domain |
| [**D. No tunnel / LAN**](#option-d-no-tunnel-local-or-lan-only) | `localhost` or your LAN IP | nothing | This machine or your home network |
| [**E. Private Tailscale network**](#option-e-private-network-tailscale-without-funnel) | private tailnet IP | Tailscale on each device | Only your own devices |

Not sure? Start with **A**, then move to **B** (if you have a domain) or **C** (if you don't). With a public tunnel (A, B, C), traffic passes through the provider's network; use D or E if that matters (see [security](security.md#privacy)).

## Option A: Quick tunnel (default)

What `start.ps1` / `start.sh` do when you don't pick anything else:

```bash
./scripts/start.sh                  # Windows: .\scripts\start.ps1
```

Free, no account, no domain. You get a URL like `https://some-random-words.trycloudflare.com`, **new every run**, so it isn't suitable for [autostart](autostart.md). Cloudflare gives these account-less tunnels no uptime guarantee, so use them for experiments, not something you depend on.

If you've used cloudflared before, your own `~/.cloudflared/config.yml` would override a quick tunnel and make every request return 404. The scripts avoid this by passing [`cloudflared/quick-tunnel.yml`](../cloudflared/quick-tunnel.yml); if you run `cloudflared tunnel --url ...` yourself and get 404s, add `--config cloudflared/quick-tunnel.yml`.

## Option B: Named Cloudflare tunnel

A permanent URL on a domain you own (for example `llm.yourdomain.com`). It survives restarts, so it's the right choice for autostart. You need a free [Cloudflare account](https://dash.cloudflare.com/sign-up), a domain whose DNS is managed by Cloudflare, and `cloudflared` installed (the install script does that). Pick **one** method.

### B1. Dashboard and token (easiest)

1. In the Cloudflare dashboard open **Zero Trust → Networks → Tunnels** and create a tunnel of type **Cloudflared** (menu names shift; Cloudflare's [tunnel guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/) is the current reference).
2. Add a **public hostname**: your domain and a subdomain such as `llm`, service type **HTTP**, URL `localhost:4000`.
3. Copy the tunnel **token** (treat it like a password) into `.env`:

   ```ini
   CLOUDFLARE_TUNNEL_TOKEN=eyJ...your-token...
   PUBLIC_URL=https://llm.yourdomain.com
   ```

   `PUBLIC_URL` is optional; it only lets the script print your URL.
4. Run `.\scripts\start.ps1 -Tunnel named` (macOS/Linux: `./scripts/start.sh --tunnel named`).

### B2. Command line and config file

```bash
cloudflared tunnel login                       # opens a browser; pick your domain
cloudflared tunnel create homeport             # prints a tunnel UUID and writes a credentials .json
cloudflared tunnel route dns homeport llm.yourdomain.com
```

Then either fill in the repo's template, [`cloudflared/config.yml`](../cloudflared/config.yml), or keep cloudflared's standard config at `~/.cloudflared/config.yml` and leave the template alone (the scripts notice it still contains `<TUNNEL-UUID>` and fall back to cloudflared's own config). A working config:

```yaml
tunnel: 01234567-89ab-cdef-0123-456789abcdef
credentials-file: C:\Users\you\.cloudflared\01234567-89ab-cdef-0123-456789abcdef.json   # Windows path shown

ingress:
  - hostname: llm.yourdomain.com          # bare hostname: NO "https://"
    service: http://localhost:4000

  - service: http_status:404              # required catch-all
```

Check it with `cloudflared tunnel --config cloudflared/config.yml ingress validate`, then start with `-Tunnel named` / `--tunnel named`. Leave `CLOUDFLARE_TUNNEL_TOKEN` empty in `.env`, or the token takes priority.

## Option C: Tailscale Funnel

[Tailscale Funnel](https://tailscale.com/kb/1223/funnel) publishes a local service at a stable HTTPS URL like `https://your-machine.your-tailnet.ts.net`, with no domain to buy.

1. Install Tailscale and sign in.
2. Enable HTTPS and Funnel for your tailnet (a one-time step in their admin console; see their [Funnel guide](https://tailscale.com/kb/1223/funnel)).
3. Start the gateway without a Cloudflare tunnel, then point Funnel at it:

   ```bash
   ./scripts/start.sh --tunnel none             # or: .\scripts\start.ps1 -Tunnel none
   tailscale funnel 4000
   ```

Tailscale prints the public URL; use `https://<machine>.<tailnet>.ts.net/v1` as your base URL.

## Option D: No tunnel (local or LAN only)

`./scripts/start.sh --tunnel none` (Windows: `.\scripts\start.ps1 -Tunnel none`) serves `http://localhost:4000/v1` on this machine only. To allow other devices on your home network, also pass `--host 0.0.0.0` (Windows: `-BindHost 0.0.0.0`) and use `http://<this-computer's-LAN-IP>:4000/v1`. The key still applies, but traffic isn't encrypted, so only do this on a network you trust, and you may need to allow port 4000 through your firewall.

## Option E: Private network (Tailscale without Funnel)

If only your own devices need the model, nothing has to be public. Put them on one [Tailscale](https://tailscale.com) network, bind the gateway to your Tailscale address, and connect to it from your other devices:

```bash
./scripts/start.sh --tunnel none --host <this-machine's-tailscale-ip>
# from another device on your tailnet: http://<that-ip>:4000/v1
```

Tailscale encrypts the traffic between your devices and nothing is reachable from the public internet, so this is the most private option.

## Anything else

The gateway is just an HTTP server on `127.0.0.1:4000`, so anything that can forward to it works (ngrok, a reverse proxy over a VPN, WireGuard). Start with `-Tunnel none`. Whatever you use, **only forward port 4000 (LiteLLM), never Ollama's 11434**, and keep the API key on.
