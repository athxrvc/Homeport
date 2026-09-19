# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `scripts/start.ps1` (Windows) and `scripts/start.sh` (macOS/Linux): one command that checks prerequisites, creates `.env` with a generated API key, starts LiteLLM and an optional Cloudflare tunnel, and prints the public URL plus a ready-to-run example.
- Catch-all model route: any model pulled into Ollama is available under its own name, with no config edits.
- `-Tunnel quick|named|none` (`--tunnel`) modes; `-BindHost` (`--host`) and `-Port` (`--port`) options.
- `.env.example`, `.gitignore`, `.gitattributes`.
- Documentation: rewritten README and setup guide, plus guides for using the API, tunnels, configuration, autostart, security, troubleshooting and an FAQ.
- `CONTRIBUTING.md`, `SECURITY.md`, issue and pull request templates.
- `tests/api_tests.py`: a portable API test suite anyone can run against their own gateway (about 25 checks), and `tests/README.md` with a checklist for platforms that haven't been tested.
- `docs/testing.md`: the Windows 11 test report (what was tested, how, the results, the problems found, and what remains untested).

### Fixed
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
- Project renamed from "Local LLM API Gateway" to **Homeport**. Repository, clone and issue links, and the service, task and launch-agent names in the autostart guide were updated to match.
- LiteLLM now listens on `127.0.0.1` by default instead of all interfaces.
- Documented Python requirement corrected to "3.10 or newer": the gateway was tested end to end on 3.10, 3.12, 3.13 and 3.14 (and on 3.9, where pip installs an older LiteLLM, 1.83.9).
