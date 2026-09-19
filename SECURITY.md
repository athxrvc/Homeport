# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Use GitHub's private reporting instead: go to the repository's **Security** tab and choose **Report a vulnerability**. Include what you found, how to reproduce it, and the impact you think it has.

You can expect an acknowledgement within a few days. This is a small volunteer project, so fixes are made on a best-effort basis, and you'll be told when one lands.

## Scope

This project is a set of configuration files and launch scripts that connect three other programs ([Ollama](https://github.com/ollama/ollama), [LiteLLM](https://github.com/BerriAI/litellm) and optionally [cloudflared](https://github.com/cloudflare/cloudflared)). It is in scope if:

- a script or default config here leaves a user's gateway less secure than the docs promise (for example, exposes it without authentication, leaks the API key, or binds to a wider network interface than documented);
- the docs give advice that would lead people into an insecure setup.

Vulnerabilities in Ollama, LiteLLM, cloudflared or Cloudflare itself should be reported to those projects.

## Security model, in short

- Every request to the gateway must carry the API key from `.env` (`LITELLM_MASTER_KEY`). The start scripts refuse to run without one.
- LiteLLM listens on `127.0.0.1` by default. Only the tunnel (running on the same machine) reaches it.
- Ollama has no authentication of its own and must never be exposed directly.

The full guidance for users is in [docs/security.md](docs/security.md).

## Handling secrets when you report bugs

Logs and terminal output from the start scripts contain your **API key** and a **tunnel URL**. Remove both before pasting them into a public issue.
