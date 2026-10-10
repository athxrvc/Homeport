# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `scripts/install.sh` (macOS/Linux) and `scripts/install.ps1` (Windows): one command that installs everything Homeport needs. It finds or installs Python 3.10+ (on macOS a private copy downloaded through uv, with no Homebrew or admin password; winget on Windows), installs LiteLLM into a project-local `.venv`, installs cloudflared (Homebrew, winget, or a direct download into `.venv` on Linux) and Ollama, starts Ollama, and pulls a first model if there is none. The start scripts use the `.venv` copy of LiteLLM automatically, so no `PATH` changes are needed.
- `scripts/start.ps1` (Windows) and `scripts/start.sh` (macOS/Linux): one command that checks prerequisites, creates `.env` with a generated API key, starts LiteLLM and an optional Cloudflare tunnel, and prints the public URL plus a ready-to-run example.
- Catch-all model route: any model pulled into Ollama is available under its own name, with no config edits.
- `-Tunnel quick|named|none` (`--tunnel`) modes; `-BindHost` (`--host`) and `-Port` (`--port`) options.
- `.env.example`, `.gitignore`, `.gitattributes`.
- Documentation: rewritten README and setup guide, plus guides for using the API, tunnels, configuration, autostart, security, troubleshooting and an FAQ.
- `CONTRIBUTING.md`, `SECURITY.md`, issue and pull request templates.

### Fixed
- Docs: the macOS launchd recipe now covers what a real Mac run found: create `~/Library/LaunchAgents` first, keep the project out of Documents/Desktop/Downloads (macOS blocks background jobs from reading them), and use `launchctl bootstrap`/`bootout`.
- Docs: how to stop leftover LiteLLM and cloudflared processes after `kill -9` on macOS/Linux; `chmod 600 .env` for an existing `.env`; a warning that redirected script output contains the API key; and a more realistic wait for a new tunnel name to resolve (a minute or two).
- `start.sh` now creates `.env` readable only by your own user account (it was world-readable), since it holds the API key.
- `start.sh --help` and `install.sh --help` printed a stray `set -euo pipefail` line.
- `install.sh` skipped an installed Python 3.14 and installed Python 3.12 when it didn't need to.
- `master_key` was under `litellm_settings`, where LiteLLM ignores it, leaving the API unauthenticated. It now lives under `general_settings`.
- The cloudflared template used `hostname: https://...`; hostnames must not include a scheme.
- Renamed the misspelled `Cloudfared/` directory to `cloudflared/`.
- Quick tunnels returned 404 for anyone with an existing `~/.cloudflared/config.yml`; the script now passes `cloudflared/quick-tunnel.yml`, which has no ingress rules.
- Windows: LiteLLM crashed at startup when its output was redirected (cp1252 encoding); the scripts now set `PYTHONUTF8=1`.
- Windows: probing `localhost` stalled for about 2 seconds per attempt (IPv6 fallback); the scripts use `127.0.0.1`.
- **The scripts printed Cloudflare's API address (`https://api.trycloudflare.com`) as the public URL when `cloudflared` couldn't reach the internet**, along with example commands that send the API key to that host. They now ignore that address, detect that cloudflared exited, and stop with a clear "no internet connection?" message.
- The scripts kept running with a dead public URL if the tunnel process died mid-run. They now say so, stop the gateway too, and exit with code 1. The same exit code 1 is now returned when LiteLLM itself dies (it was 0).
- Windows: LiteLLM and cloudflared were left running (and the public URL stayed live) whenever the script's own process was killed: `Stop-ScheduledTask`, Task Manager's "End task", `taskkill /F`. `start.ps1` now runs them in a job object that ends with the script, so nothing is left behind.
- `cloudflared/quick-tunnel.yml` was empty, which made cloudflared log an `ERR ... was empty` line on every quick-tunnel start. It now contains a harmless setting.
- Docs: the Windows autostart recipe failed with "Access is denied" for a normal user (the trigger now uses `-User $env:USERNAME`); a ZIP download on Windows was blocked by `RemoteSigned` ("not digitally signed") and the docs now explain and give the tested fix; the Python streaming snippet wasn't self-contained; the docs now warn that `http://` tunnel URLs send the key unencrypted, list the pages reachable without a key, and describe what a fresh `pip install` of LiteLLM 1.101.0 actually shows.

### Changed
- `install.sh` on macOS no longer uses Homebrew or asks for a password. It downloads cloudflared (into `.venv/bin`), Ollama (`Ollama.app`, into `/Applications` or `~/Applications`) and, only if no Python 3.10+ is found, a private Python through uv (into `.tools/`), all from their official sources.
- The quick-tunnel summary now says a new URL can take a minute or two to start resolving, so a "could not resolve host" right after startup doesn't look like a failure.
- Project renamed from "Local LLM API Gateway" to **Homeport**. Repository, clone and issue links, and the service, task and launch-agent names in the autostart guide were updated to match.
- LiteLLM now listens on `127.0.0.1` by default instead of all interfaces.
- Documented Python requirement corrected to "3.10 or newer".
