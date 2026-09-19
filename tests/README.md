# Tests

This folder has one automated check that anyone can run against their own Homeport setup, plus a checklist for the things a script can't easily check. The full Windows 11 results are in [docs/testing.md](../docs/testing.md).

## The API test suite

[`api_tests.py`](api_tests.py) sends real requests to a running gateway and checks about 25 things: authentication, that Ollama's own API is never exposed, the OpenAI response shape, model names, streaming, malformed input, concurrency and OpenAI-SDK compatibility. It needs only Python 3.9+ (checked on 3.9, 3.13 and 3.14; the SDK checks run if `openai` is installed).

Start Homeport first (`.\scripts\start.ps1 -Tunnel none` or `./scripts/start.sh --tunnel none`), then:

```bash
python tests/api_tests.py --base http://localhost:4000 --key sk-YOUR-KEY --model llama3.2:latest
```

Use your key from `.env` and a model name from `ollama list`. To test the public path too, run it again with your tunnel URL as `--base` (for example `--base https://<your-url>`).

Useful options:

| Option | Meaning |
|---|---|
| `--quick` | Skip the concurrency and SDK checks |
| `--max-tokens 2000` | Raise the answer budget if you use a "thinking" model (see [using-the-api.md](../docs/using-the-api.md#good-to-know)) |
| `--json report.json` | Also write the results to a file, handy for pasting into an issue |

Each check prints `PASS`, `WARN`, `FAIL` or `INFO`:

- **FAIL** is a real problem: wrong API shape, missing authentication, Ollama exposed, a crash. The exit code is 1.
- **WARN** depends on the model or on upstream software, such as a model that ignores a system prompt. Worth a look, not a bug.
- **INFO** is recorded for reference (which endpoints answer without a key).

The run sends real prompts to your model, so allow a minute or two.

## Checklist for the things a script can't check

If you test on a platform that isn't in the [tested matrix](../README.md#what-has-been-tested), these are the checks that matter most. They're the ones that found real problems on Windows.

**Start and stop**

- [ ] The script starts from a fresh clone with no `.env`, creates one with a `sk-` key, and prints the summary.
- [ ] Ctrl+C in the window stops LiteLLM **and** the tunnel. Afterwards nothing is listening on the port and no `litellm` or `cloudflared` process remains.
- [ ] Killing only the script's process (not the whole tree) also leaves nothing behind (on Windows this is handled by a job object; on Linux/macOS the bash script relies on its `trap`, which can't catch `kill -9`).
- [ ] Kill `cloudflared` while it runs: the script must say so and stop, not sit there with a dead URL.
- [ ] A second copy on the same port is refused with a clear message.

**Error messages** (each one is quoted in [troubleshooting.md](../docs/troubleshooting.md), so check the text really matches)

- [ ] Missing `litellm`, missing `cloudflared`, Ollama not running, Ollama with no models, an empty `LITELLM_MASTER_KEY`, a broken `LiteLLM/config.yaml`.

**Public path**

- [ ] The quick-tunnel URL works from a **different network** (a phone on mobile data is ideal).
- [ ] The request fails without the key, and `/api/tags` never returns Ollama's model list.
- [ ] Streaming arrives progressively, not all at the end.

**Docs**

- [ ] Follow [SETUP.md](../SETUP.md) literally from a clean machine and note every step where the text and reality differ.

Please open an issue with your OS, versions and what you ran (remove your API key and tunnel URL first). A pull request that adds your platform to the matrix is even better.
