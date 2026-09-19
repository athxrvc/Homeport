# Contributing

Thanks for wanting to help! This is a small project (config files, two launch scripts and documentation), so contributing is easy. Good first contributions include:

- **Testing on your platform** and reporting what worked or didn't. The README's [status](README.md#status) lists what hasn't been tried yet: native Linux and macOS, a real named tunnel, Tailscale, and Linux/macOS autostart.
- **Fixing or clarifying docs.** If a step confused you, it will confuse others.
- **Guides for specific apps** (a chat UI, an editor, an agent framework) connecting to the gateway, written from something you actually got working.
- **New tunnel or autostart recipes**, with notes on what you tested.
- **Bug fixes and small improvements** to the scripts.

## Reporting bugs and asking questions

Open a [GitHub issue](https://github.com/athxrvc/homeport/issues/new/choose). The template asks for your OS, versions and the relevant log lines. Please **remove your API key, tunnel token and tunnel URL** before pasting anything. The start script's on-screen output contains the key.

For security problems, don't open a public issue. See [SECURITY.md](SECURITY.md).

## Project layout

```text
LiteLLM/config.yaml        LiteLLM gateway config (models + auth)
cloudflared/config.yml     Template for a named Cloudflare tunnel
cloudflared/quick-tunnel.yml   No-ingress config so quick tunnels ignore ~/.cloudflared/config.yml
scripts/start.ps1          Windows launcher (PowerShell)
scripts/start.sh           macOS / Linux launcher (bash)
.env.example               Template for local secrets (.env is git-ignored)
SETUP.md                   Step-by-step install guide
docs/                      Topic guides
```

## Running it locally while you work

```bash
./scripts/start.sh --tunnel none          # or: .\scripts\start.ps1 -Tunnel none
```

Use `--tunnel none` while developing so you don't publish anything. Use a different port (`--port 4010`) if you already run a gateway on 4000. Logs are in `logs/`.

## Guidelines for changes to the scripts

- **Keep both scripts in step.** A behavior change in `start.ps1` should be mirrored in `start.sh`, and vice versa.
- **PowerShell must run on Windows PowerShell 5.1** (the version built into Windows), not only PowerShell 7. That means no `&&`, ternary `?:` or `??`.
- **Bash should stay portable** across Linux and macOS: no GNU-only flags where a portable form exists.
- **No new dependencies.** The scripts should need only what the README already requires. (`jq`, for example, is deliberately avoided.)
- **Safe by default.** Don't weaken the auth requirement, and don't make anything listen on more than `127.0.0.1` by default.
- **Windows gotchas already handled**, so please keep them: `PYTHONUTF8=1` (LiteLLM's banner crashes on cp1252 when output is redirected), and probing `127.0.0.1` rather than `localhost` (IPv6 fallback adds ~2 s per try). Kill process *trees* on Windows (`taskkill /T`), because `litellm.exe` is a launcher that spawns Python, and keep the job object in `start.ps1`: it is what stops LiteLLM and cloudflared when the script's process is killed (Stop-ScheduledTask, End task).
- Shell scripts must keep **LF** line endings. `.gitattributes` enforces this.

## Guidelines for docs

- **Only state what you have tested.** If a page quotes an error message, reproduce it first. If a step is untested, say so plainly (the docs already do this with "Status" notes). Untested-but-labelled is fine; untested-and-implied-to-work isn't.
- Write for someone who has never used Ollama or a terminal much: say what they should *see* after each step.
- Show **both** Windows (PowerShell) and macOS/Linux (bash) commands where they differ.
- Never include real keys, tokens, domains or personal paths in examples. Use placeholders like `<your key>`, `sk-YOUR-KEY`, `llm.yourdomain.com`.
- Keep the [CHANGELOG](CHANGELOG.md) updated under **Unreleased**.

## Making a pull request

1. Fork the repo and create a branch.
2. Make your change and test it. For script changes, run the gateway and make a real request (with and without the key). For doc changes, follow the steps you edited.
3. Update the docs and CHANGELOG if behavior changed.
4. Open a PR and fill in the template, including **what you tested and on which OS**.

Keep PRs focused: one topic per PR is easier to review.

## License

By contributing, you agree your contributions are licensed under the project's [MIT License](LICENSE).
