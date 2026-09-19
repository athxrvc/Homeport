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

### Fixed
- `master_key` was under `litellm_settings`, where LiteLLM ignores it, leaving the API unauthenticated. It now lives under `general_settings`.
- The cloudflared template used `hostname: https://...`; hostnames must not include a scheme.
- Renamed the misspelled `Cloudfared/` directory to `cloudflared/`.
- Quick tunnels returned 404 for anyone with an existing `~/.cloudflared/config.yml`; the script now passes an empty config.
- Windows: LiteLLM crashed at startup when its output was redirected (cp1252 encoding); the scripts now set `PYTHONUTF8=1`.
- Windows: probing `localhost` stalled for about 2 seconds per attempt (IPv6 fallback); the scripts use `127.0.0.1`.

### Changed
- LiteLLM now listens on `127.0.0.1` by default instead of all interfaces.
- Documented Python requirement corrected to 3.10 to 3.13 (LiteLLM's requirement).
