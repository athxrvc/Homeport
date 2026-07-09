# Local LLM API Gateway

A self-hosted, OpenAI-compatible API gateway for running local language models with Ollama and LiteLLM. This project is designed to be simple to run on a personal machine, easy to extend, and suitable for open-source collaboration.

## What this project is

This project lets you run local language models with Ollama and expose them through LiteLLM using an OpenAI-style API. It is useful when you want local inference, privacy, and a familiar interface without depending on external providers.

## Architecture

```text
Client / App
    |
    v
OpenAI-compatible API
    |
    v
LiteLLM
    |
    v
Ollama
    |
    v
Local LLM model
```

## Features

- Run local models with Ollama
- Expose them through LiteLLM with OpenAI-compatible endpoints
- Keep your data local by default
- Optionally publish the service through Cloudflare Tunnel
- Configure different models and routing rules

## Who this is for

- Developers who want a local LLM API
- Privacy-focused users who prefer self-hosted tools
- Teams experimenting with open-source model serving

## Getting started

For installation and setup instructions, see [SETUP.md](SETUP.md).

## License

This project is licensed under the MIT License. See the LICENSE file for details.