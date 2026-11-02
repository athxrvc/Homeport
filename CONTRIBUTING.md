# Contributing

Thanks for wanting to help! This is a small project (configs, a few scripts and docs), so contributing is easy. Useful contributions:

- Trying Homeport on a platform or setup that hasn't been tried yet (see [Status](README.md#status)) and reporting how it went.
- Fixing or clarifying docs. If a step confused you, it will confuse others.
- Guides for connecting a specific app (a chat UI, an editor, an agent framework) that you actually got working.
- Bug fixes and small improvements to the scripts.

## Reporting bugs

Open a [GitHub issue](https://github.com/athxrvc/homeport/issues/new/choose). The template asks for your OS, versions and the relevant log lines. **Remove your API key, tunnel token and tunnel URL** before pasting anything (the start script's output contains the key). For security problems, don't open a public issue: see [SECURITY.md](SECURITY.md).

## Project layout

```text
scripts/install.sh, install.ps1    Install Ollama, LiteLLM (.venv), cloudflared, Python
scripts/start.sh, start.ps1        Start the gateway and an optional tunnel
LiteLLM/config.yaml                Gateway config (models + auth)
cloudflared/                       Tunnel configs (named-tunnel template, quick-tunnel)
.env.example                       Template for local secrets (.env is git-ignored)
SETUP.md, docs/                    Guides
```

To try changes without publishing anything, run `./scripts/start.sh --tunnel none` (Windows: `.\scripts\start.ps1 -Tunnel none`).

## Changing the scripts

- Keep the `.sh` and `.ps1` versions in step.
- `.ps1` files must run on Windows PowerShell 5.1: no `&&`, `?:` or `??`.
- Keep bash portable across Linux and macOS (macOS ships bash 3.2), and add no new dependencies (`jq`, for example, is deliberately avoided).
- Stay safe by default: never weaken the API-key requirement, and don't listen on more than `127.0.0.1` by default.
- Shell scripts keep LF line endings (`.gitattributes` enforces it).

## Changing the docs

- Only document what you've actually run, and say plainly when something is unverified.
- Show both Windows (PowerShell) and macOS/Linux (bash) commands where they differ.
- Use placeholders like `<your key>` and `llm.yourdomain.com`, never real keys, tokens, domains or personal paths.

## Pull requests

Fork, branch, make one focused change, try it (for scripts: start the gateway and make a real request with and without the key), update the docs and [CHANGELOG](CHANGELOG.md) if behavior changed, and say in the PR what you tested and on which OS.

By contributing, you agree your contributions are licensed under the project's [MIT License](LICENSE).
