# Using the API

Once the gateway is running, your model speaks the OpenAI API. This page shows how to call it and how to connect other tools.

## The three values

| Setting | Value | Where to find it |
|---|---|---|
| **Base URL** | `https://<your-url>/v1`, or `http://localhost:4000/v1` on the same machine | Printed by the start script |
| **API key** | `sk-...` | Printed by the start script; stored in `.env` as `LITELLM_MASTER_KEY` |
| **Model** | The name from `ollama list`, such as `llama3.2:latest` | `ollama list` |

Two easy mistakes: the Base URL must end in `/v1`, and the model name must match what Ollama shows. The `:latest` tag can be left off (`llama3.2` works the same as `llama3.2:latest`), but any other tag, such as `:8b`, must be included.

## Endpoints

| Endpoint | Auth | Notes |
|---|---|---|
| `POST /v1/chat/completions` | key | The main one. Supports streaming. |
| `GET /v1/models` | key | Lists models. See [the model list caveat](#the-model-list-shows-odd-entries). |
| `GET /health/liveliness`, `GET /health/readiness` | none | Simple "is it up" checks. |

Chat completions, streaming and model listing are what has been tested. LiteLLM can serve other OpenAI endpoints (for example embeddings), but they are not covered or tested here. See the [LiteLLM docs](https://docs.litellm.ai/) if you need them.

## curl (macOS, Linux, Git Bash)

```bash
curl https://<your-url>/v1/chat/completions \
  -H "Authorization: Bearer <your key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2:latest",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Add `"stream": true` to the JSON and `-N` to curl to see tokens arrive as they're generated.

## PowerShell (Windows)

PowerShell's built-in `curl` is an alias for something else and mangles JSON quotes. Use `Invoke-RestMethod`:

```powershell
$body = @{
  model    = "llama3.2:latest"
  messages = @(@{ role = "user"; content = "Hello!" })
} | ConvertTo-Json -Depth 5

$reply = Invoke-RestMethod -Uri "https://<your-url>/v1/chat/completions" -Method Post `
  -Headers @{ Authorization = "Bearer <your key>" } `
  -ContentType "application/json" -Body $body

$reply.choices[0].message.content
```

## Python

```bash
pip install openai
```

```python
from openai import OpenAI

client = OpenAI(base_url="https://<your-url>/v1", api_key="<your key>")

reply = client.chat.completions.create(
    model="llama3.2:latest",
    messages=[
        {"role": "system", "content": "You are a concise assistant."},
        {"role": "user", "content": "Explain DNS in two sentences."},
    ],
)
print(reply.choices[0].message.content)
```

**Streaming:**

```python
stream = client.chat.completions.create(
    model="llama3.2:latest",
    messages=[{"role": "user", "content": "Tell me a short story."}],
    stream=True,
)
for chunk in stream:
    if chunk.choices and chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

## JavaScript / Node.js

```bash
npm install openai
```

```js
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://<your-url>/v1",
  apiKey: "<your key>",
});

const reply = await client.chat.completions.create({
  model: "llama3.2:latest",
  messages: [{ role: "user", content: "Hello!" }],
});
console.log(reply.choices[0].message.content);

// Streaming
const stream = await client.chat.completions.create({
  model: "llama3.2:latest",
  messages: [{ role: "user", content: "Tell me a short story." }],
  stream: true,
});
for await (const chunk of stream) {
  process.stdout.write(chunk.choices[0]?.delta?.content ?? "");
}
```

(Save as a `.mjs` file, or set `"type": "module"` in `package.json`, to use `import` and top-level `await`.)

Keep your key out of your source code. Read it from an environment variable (`os.environ["GATEWAY_KEY"]`, `process.env.GATEWAY_KEY`) instead.

## Connecting apps and tools

Most software that supports "OpenAI-compatible" or "custom OpenAI endpoint" providers has the same three fields. Fill them with the values at the top of this page.

| The app calls it... | Put in... |
|---|---|
| Base URL, API Base, Endpoint, Server URL | `https://<your-url>/v1` |
| API key, Secret key, Bearer token | your `sk-...` key |
| Model, Model ID | your Ollama model name, typed exactly |

Things that trip people up:

- **Cloud-hosted apps can't reach `localhost`.** If the app runs on someone else's servers, `http://localhost:4000` means *their* machine. Use your public URL. Apps that run on your own computer can use either.
- **Use the `https://` public URL for anything outside your machine.** The tunnel provides HTTPS. Plain `http://localhost:4000` is for same-machine use.
- **Some apps ask you to choose the model from a list.** See the next section.
- **Test with curl or the Python snippet first.** If those work and the app doesn't, the problem is the app's settings, not the gateway.

This project doesn't ship instructions for specific third-party apps, because they change their menus often. If you get a particular app working, a short guide contributed to this repo would help others (see [CONTRIBUTING.md](../CONTRIBUTING.md)).

### The model list shows odd entries

Apps that fill a dropdown from `GET /v1/models` will see entries such as `*` and `ollama_chat/llama2` instead of your real models. That is a side effect of the default catch-all config, which lets every model work without listing them one by one. **Chat requests still work**: you can type your model name into the app manually.

If you want a proper dropdown, list your models explicitly in the config. `/v1/models` then shows exactly what you list (this was tested):

```yaml
# LiteLLM/config.yaml
model_list:
  - model_name: general
    litellm_params:
      model: ollama_chat/llama3.2:latest
      api_base: http://localhost:11434
```

Clients then use `general` as the model name. See [configuration.md](configuration.md).

## Good to know

**The first request is slow.** Ollama loads the model into memory on first use, and unloads it after a period of inactivity (5 minutes by default; the `OLLAMA_KEEP_ALIVE` environment variable changes this). After a quiet spell, expect the next request to take longer.

**"Thinking" models.** Some models reason before answering and return that in a separate `reasoning_content` field. If `max_tokens` is small, the model can use it all up thinking and return an empty `content` with `finish_reason: "length"`. Raise `max_tokens` or leave it out.

**Use streaming for long answers.** Streaming through the tunnel was tested and delivers tokens progressively, as it does locally. It also matters for a second reason: Cloudflare documents that its proxy can drop a request that gets no response data for roughly 100 seconds (a 524 error). We didn't manage to trigger this in testing (our longest non-streaming request took 49 seconds), but a very long non-streaming generation could hit it. With `stream: true`, data flows continuously and this can't happen.

**Sampling parameters.** `max_tokens`, `stream` and system/user messages are tested. Other parameters such as `temperature` follow LiteLLM's Ollama support. See the [LiteLLM Ollama docs](https://docs.litellm.ai/docs/providers/ollama).
