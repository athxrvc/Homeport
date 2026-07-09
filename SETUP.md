# Setup Guide

This guide covers installing and running the project locally.

## Requirements

- Ollama installed locally
- Python 3.9+ and pip
- Optional: Cloudflare account and cloudflared

## 1. Install Ollama

Install Ollama from https://ollama.com and verify the installation:

```bash
ollama --version
```

Pull a model:

```bash
ollama pull your-model-name:latest
```

## 2. Install LiteLLM

```bash
pip install "litellm[proxy]"
```

or:

```bash
uv tool install "litellm[proxy]"
```

## 3. Configure LiteLLM

Create a configuration file named config.yaml:

```yaml
model_list:
  - model_name: gemma4
    litellm_params:
      model: ollama/your-model-name:latest
      api_base: http://localhost:11434

litellm_settings:
  master_key: "replace-with-a-strong-secret"
```

Start LiteLLM:

```bash
litellm --config config.yaml
```

The service will be available at:

```text
http://localhost:4000
```

## 4. Test locally

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer replace-with-a-strong-secret" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"gemma4",
    "messages":[{"role":"user","content":"Hello"}]
  }'
```

## 5. Optional: expose it publicly with Cloudflare Tunnel

Install cloudflared and configure a tunnel. Replace the sample values in cloudfared/config.yml with your own tunnel ID and hostname.

Example configuration:

```yaml
tunnel: your-tunnel-id
credentials-file: C:\Users\<username>\.cloudflared\your-tunnel-id.json

ingress:
  - hostname: https://your-domain.example
    service: http://localhost:4000

  - service: http_status:404
```

## Security recommendations

- Use a strong API key for LiteLLM
- Do not expose Ollama directly to the internet
- Restrict public access if you are using Cloudflare Access or another gateway

## Adding more models

You can add more entries to model_list for different local models.

```yaml
model_list:
  - model_name: general
    litellm_params:
      model: ollama/your-model-name:latest
      api_base: http://localhost:11434

  - model_name: coder
    litellm_params:
      model: ollama/your-coder-model:latest
      api_base: http://localhost:11434
```
