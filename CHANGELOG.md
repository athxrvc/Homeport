# Changelog

Notable changes to Homeport. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

First public version.

- `scripts/install.*`: one command that installs Ollama, LiteLLM (in a private `.venv`), cloudflared and Python if they're missing. winget on Windows; official downloads on macOS, with no Homebrew or admin password. It doesn't download a model: you pull the one you want.
- `scripts/start.*`: checks prerequisites, creates `.env` with a generated API key, starts LiteLLM and an optional Cloudflare tunnel, and prints the public URL and a ready-to-run example. Tunnel modes `quick`, `named` and `none`; `--host` and `--port` options.
- Safe defaults: an API key is required, LiteLLM listens on `127.0.0.1`, and Ollama is never exposed.
- Any model you pull into Ollama works by its own name, with no config edits.
- If the tunnel or LiteLLM dies, the scripts say so, stop everything and exit with code 1. On Windows, ending the script (including `Stop-ScheduledTask`) also ends LiteLLM and the tunnel.
- Guides for setup, API usage, tunnels, configuration, autostart (Windows, macOS, Linux), security and troubleshooting, plus an FAQ.
- Renamed from "Local LLM API Gateway" to **Homeport**.
