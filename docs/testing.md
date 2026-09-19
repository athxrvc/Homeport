# Test report: Windows 11

A full clean-room test of Homeport on Windows 11, run on 19 September 2026 against the public `main` branch as it stood before the fixes described below (commit `e33610b`), from a fresh clone and a fresh Python environment, with a real Ollama model. It was run by Claude (an AI coding assistant) on the maintainer's machine while they were away, following the docs literally and then trying to break them.

**Verdict.** Every Windows workflow that was tested works as documented. The test found seven real problems (four in the scripts and their config, three in the docs); all are fixed and were re-tested, and the report below shows the before and after. What could **not** be tested is listed honestly in [Not tested](#not-tested), and that list matters as much as the passes.

## At a glance

| | |
|---|---|
| Distinct checks recorded | 237 |
| Pass | 212 |
| Warn (upstream or model behaviour, not Homeport bugs) | 10 |
| Info (recorded for reference) | 14 |
| Fail | 1 (see [the note on WIN-01](#windows-specific): a Windows behaviour that the docs now explain, with tested workarounds) |
| Longest continuous run | 50-minute soak through a public tunnel |
| Real model | `maxwellb/gemma4-12b-it-oym:latest` (a 12B "thinking" model, 7.2 GB, on an NVIDIA RTX 5070 Ti) |

## Environment

| Component | Version |
|---|---|
| OS | Windows 11 Home, build 26200 (10.0.26200), 64-bit, normal (non-admin) user |
| Shell | Windows PowerShell 5.1 (PowerShell 7 was not installed); execution policy `RemoteSigned` for the user |
| Hardware | AMD Ryzen 7 9800X3D, 31 GB RAM, NVIDIA GeForce RTX 5070 Ti |
| Ollama | 0.30.7 (0.34.2 was available at the time) |
| LiteLLM | **1.101.0**, from a fresh `pip install "litellm[proxy]"` in a new venv (also `uv tool install`, same version). The machine also had 1.91.0 installed; the first four `start.sh` checks used it |
| cloudflared | 2026.7.0 (2026.9.1 was available) |
| Python | 3.13.13 for the main run; the gateway was also run end to end on 3.10, 3.12 and 3.14 (LiteLLM 1.101.0) and on 3.9 (where pip installs LiteLLM 1.83.9), each in an isolated environment |
| Other | git 2.53, Git Bash, curl.exe, Node 24 with the `openai` JS SDK, Python `openai` SDK 2.44 |
| Network | ordinary home broadband |

## How it was tested

- **From scratch.** A fresh `git clone` of the public repository, and a brand-new virtual environment for LiteLLM, so the test used exactly what a new user gets. (A fresh install pulled LiteLLM 1.101.0, newer than the copy already on the machine, so the from-scratch run mattered.)
- **Docs as tests.** The code blocks in the README, SETUP and guides were extracted and run *verbatim* (only the URL, key and model placeholders substituted), under real Windows PowerShell 5.1, Python, Node and curl.
- **Error injection.** Every error message quoted in the troubleshooting guide was reproduced on purpose: missing tools, a busy port, an empty key, a broken config, Ollama stopped, Ollama with no models, and a tunnel that fails. Where a real failure couldn't be caused safely, a stub `cloudflared` produced the same output.
- **Real signals.** Ctrl+C was delivered as a genuine console `CTRL_C_EVENT`, and the script's process was force-killed, to check cleanup.
- **Real public path.** Requests went through actual Cloudflare quick tunnels over the public internet, including streaming and a request that outlasts Cloudflare's timeout.
- **Security probes.** What a stranger with only the URL can reach, whether Ollama's own API is exposed, and whether the key leaks into logs.
- **Regression.** After the fixes, the error-path, tunnel, lifecycle and API checks were re-run against the fixed scripts.

## Problems found and fixed

| # | Problem | Impact | Resolution | Evidence |
|---|---|---|---|---|
| 1 | With no internet, the scripts printed **`https://api.trycloudflare.com`** (Cloudflare's API host, taken from cloudflared's error text) as the public URL, plus example commands that would send the API key to it | High: wrong URL, key sent to a third-party host if pasted | Both scripts ignore that host, notice cloudflared exited, and stop with a clear message | ERR-09, SH-05 |
| 2 | If the tunnel died mid-run the script stayed silent with a dead public URL; LiteLLM dying returned exit code 0 | Medium | The script says so, stops the gateway, and exits 1 in both cases | MON-01, LC-01, SH-06, SH-07 |
| 3 | Killing the script's own process (`Stop-ScheduledTask`, "End task", `taskkill /F`) left LiteLLM and the tunnel running, so the public URL stayed live | High on Windows | `start.ps1` runs them in a job object that ends with the script | ORPH-01, AUTO-04, AUTO-06 |
| 4 | The documented autostart recipe failed for a normal user with "Access is denied" | Medium (docs) | Trigger is now bound to the current user (`-User $env:USERNAME`) | AUTO-01, AUTO-02 |
| 5 | A **ZIP download** on Windows is blocked by the common `RemoteSigned` policy ("not digitally signed") | Medium (docs) | Documented with two tested fixes (`Unblock-File`, or `-ExecutionPolicy Bypass`) | WIN-01, WIN-03, WIN-04 |
| 6 | The Python streaming snippet failed when copied alone (`NameError: client`) | Low (docs) | Made self-contained | DOC-07 |
| 7 | `quick-tunnel.yml` was empty, so cloudflared logged `ERR ... was empty` on every start | Low | File now holds a harmless setting; log is clean | TUN-36 |

Findings that changed the docs but not the code:

- **DNS lag.** A freshly printed quick-tunnel URL resolved instantly via `1.1.1.1` and `8.8.8.8` but stayed unresolvable on the ISP's resolver for over five minutes in one run (other runs: seconds). Now in the troubleshooting guide (DNS-01).
- **`http://` works on a quick tunnel** with no redirect to `https://`, so an app configured with `http://` would send the key unencrypted. Now warned about in the docs (TUN-32).
- **Pages reachable without a key** (Swagger UI, `/openapi.json`, `/routes`, the admin login page, health checks). Nothing sensitive, but now listed in [security.md](security.md#what-a-stranger-with-only-your-url-can-see). LiteLLM's switches to hide them only removed `/redoc`, so they were not adopted (SEC-01, SEC-02).
- **Cloudflare's ~100-second limit is real:** a slow non-streaming request through a quick tunnel came back as HTTP 524 (TUN-35). The docs said this was untested; they now say it was reproduced.
- **Upstream quirks confirmed on the newest LiteLLM:** wrong/missing key returns 400/500 instead of 401 (still rejected, nothing served); an empty `messages` array returns 200; `/v1/models` shows a made-up `ollama_chat/llama2` entry with the default config.
- **Python versions.** The docs said "3.10 to 3.13". The gateway also ran end to end on 3.14, and on 3.9 (where pip installs an older LiteLLM, 1.83.9, which returns a proper 401 for a missing key). The docs now say "3.10 or newer" with what was tested (PY-3.9 to PY-3.14).
- **Behaviour worth knowing, all good:** after 6.5 idle minutes Ollama unloads the model and the next request reloads it transparently (SOAK-03); a client that disconnects mid-stream does not leave the GPU busy (OPS-01); Ctrl+C in the middle of a streaming request stops the script in about 2 seconds and releases the client (LC-04); 4 simultaneous requests all complete.

## Results

Every row is the latest result for that check. "(after fix)" means it failed first, was fixed, and passed on re-test.

### API suite (run three ways)

The same checks ran against localhost, against a public quick tunnel, and again through a tunnel started by the *fixed* scripts. They are also available as a portable tool: [`tests/api_tests.py`](../tests/api_tests.py).

| # | Check | Local | Public tunnel | Tunnel, fixed scripts |
|---|---|---|---|---|
| 01 | chat completion has OpenAI response shape (id, object, choices[0].message.role, usage) | Pass | Pass | Pass |
| 02 | model answers a trivial instruction correctly ('pong') | Pass | Pass | Pass |
| 03 | model name WITHOUT the :latest tag works | Pass | Pass | Pass |
| 04 | unknown model -> error naming the model (not a hang or 200) | Pass | Pass | Pass |
| 05 | request with NO model field is rejected cleanly | Pass | Pass | Pass |
| 06 | simple arithmetic answer contains '4' | Pass | Pass | Pass |
| 07 | system message is honoured | Pass | Pass | Pass |
| 08 | multi-turn history is passed through (model recalls earlier turn) | Pass | Pass | Pass |
| 09 | unicode / emoji round-trips through the gateway intact | Pass | Warn | Warn |
| 10 | max_tokens is enforced (finish_reason=length, few tokens) | Pass | Pass | Pass |
| 11 | 'stop' sequence parameter accepted | Pass | Pass | Pass |
| 12 | temperature=0 + seed accepted and reproducible | Pass | Pass | Pass |
| 13 | streaming: SSE 'data:' lines, text/event-stream, terminated by [DONE] | Pass | Pass | Pass |
| 14 | streaming: final usage chunk when stream_options.include_usage=true | Pass | Pass | Pass |
| 15 | malformed JSON body -> 4xx/5xx JSON error, no crash | Pass | Pass | Pass |
| 16 | GET on the chat endpoint -> 405 (method not allowed) | Pass | Pass | Pass |
| 17 | empty messages array is rejected without crashing | Warn | Warn | Warn |
| 18 | gateway still healthy after the malformed requests above | Pass | Pass | Pass |
| 19 | lowercase 'bearer' scheme accepted | Pass | Pass | Pass |
| 20 | key with a trailing space is handled | Pass | Pass | Pass |
| 21 | 'api-key' header (Azure style) is not needed / behaviour recorded | Info | Info | Info |
| 22 | 'x-api-key' header behaviour recorded | Info | Info | Info |
| 23 | Ollama's own API (/api/*) is NOT reachable without a key | Pass | Pass | Pass |
| 24 | unauthenticated 200 responses recorded (info leakage review) | Info | Info | Info |
| 25 | Ollama's /api/tags is NOT exposed even WITH the gateway key | Pass | Pass | Pass |
| 26 | /health/readiness body (version disclosure check) | Info | Info | Info |
| 27 | 4 simultaneous requests all complete (queued or parallel) | Pass | Pass | n/a |
| 28 | openai SDK: client.models.list() works | Pass | Pass | Pass |
| 29 | openai SDK: chat.completions.create() works | Pass | Pass | Pass |
| 30 | openai SDK: streaming iterator works | Pass | Pass | Pass |
| 31 | openai SDK with a wrong key raises an exception | Pass | Pass | Pass |

The Warn results are model or upstream behaviour: the model itself inserted a space inside a Chinese word (accents, the emoji and Greek letters survived intact), and LiteLLM accepts an empty `messages` array. Check 27 (concurrency) was not repeated in the fixed-script run.

### Fresh clone and repository hygiene

| ID | Check | Result |
|---|---|---|
| CL-01 | git clone https://github.com/athxrvc/homeport.git | Pass |
| CL-02 | clone HEAD equals origin/main | Pass |
| CL-03 | all 24 expected files present | Pass |
| CL-04 | no .env, logs, credentials JSON or cert tracked | Pass |
| CL-05 | secret / personal-info scan of tracked files (documentation placeholders excluded) | Pass |
| CL-06 | start.sh is LF in worktree and mode 100755 | Pass |
| CL-07 | start.ps1 parses with zero errors (Windows PowerShell 5.1) | Pass |
| CL-08 | no PowerShell-7-only operators (&&, \|\|, ??, ?.) | Pass |
| CL-09 | start.sh passes bash -n (Git Bash) | Pass |
| CL-10 | all three YAML configs parse | Pass |
| CL-12 | LICENSE copyright line — Copyright (c) 2026 at | Warn |
| CL-13 | .env.example ships with empty values only | Pass |
| CL-16 | GitHub issue templates have valid front matter and the PR template exists | Pass |

### The portable test tool (`tests/api_tests.py`)

The tool that ships in the repo was itself tested: it passes against a healthy gateway and fails clearly when it should.

| ID | Check | Result |
|---|---|---|
| FR-08 | chat with valid key -> 200 and model answers "pong" | Pass |
| FR-09 | chat WITHOUT key is rejected (no completion served) | Pass |
| FR-10 | chat with WRONG key is rejected | Pass |
| PORT-01 | the portable suite tests/api_tests.py runs end to end against a fresh gateway and reports no FAIL | Pass |
| PORT-02 | the portable suite exits 1 and says why when the key is wrong | Pass |
| PORT-03 | the portable suite exits 1 with a helpful message when nothing is listening on the URL | Pass |
| PORT-04 | the portable suite exits 1 when the model name is wrong (checks that need a real model FAIL clearly) | Pass |
| PORT-05 | the portable suite compiles, prints --help, and takes its failure path on Python 3.9 and 3.14 (3.13 ran the full suite) | Pass |

### Installation from scratch

| ID | Check | Result |
|---|---|---|
| PR-02 | ollama --version works | Pass |
| PR-03 | ollama list shows the test model | Pass |
| PR-04 | SETUP.md model 'llama3.2:latest' exists in the Ollama registry | Pass |
| PR-05 | ollama run <model> "Say hello in five words" (SETUP.md step 2 sanity check) | Pass |
| PR-06 | SETUP.md Option 1: pip install "litellm[proxy]" in a brand-new venv | Pass |
| PR-07 | litellm --help works after install (SETUP.md step 3 check) | Pass |
| PR-08 | SETUP.md Option 2: uv tool install "litellm[proxy]" (isolated dirs) | Pass |
| PR-01-Cloudflare.cloudflared | winget package id 'Cloudflare.cloudflared' exists (SETUP.md) | Pass |
| PR-01-Ollama.Ollama | winget package id 'Ollama.Ollama' exists (SETUP.md) | Pass |
| PY-3.9 | Python 3.9.25 with LiteLLM 1.83.9: the gateway starts via start.ps1, answers a real chat, and rejects missing and wrong keys | Pass |
| PY-3.10 | Python 3.10.20 with LiteLLM 1.101.0: the gateway starts via start.ps1, answers a real chat, and rejects missing and wrong keys | Pass |
| PY-3.12 | Python 3.12.13 with LiteLLM 1.101.0: the gateway starts via start.ps1, answers a real chat, and rejects missing and wrong keys | Pass |
| PY-3.14 | Python 3.14.5 with LiteLLM 1.101.0: the gateway starts via start.ps1, answers a real chat, and rejects missing and wrong keys | Pass |

### First run

| ID | Check | Result |
|---|---|---|
| FR-01 | first run from a fresh copy (no .env), under RemoteSigned: creates .env, starts, prints the summary shown in SETUP.md | Pass |
| FR-02 | .env auto-created with sk- key = 43 base64url chars (256-bit), ASCII, no BOM | Pass |
| FR-03 | .env keeps every variable and comment from .env.example | Pass |
| FR-04 | .env and logs/ are git-ignored (git status clean after a run) | Pass |
| FR-07 | script launched the fresh-venv litellm (PATH resolution) | Pass |

### Model handling

| ID | Check | Result |
|---|---|---|
| MOD-01 | a model created AFTER the gateway started is usable at once by its own name (no restart, no config edit) | Pass |
| MOD-02 | name WITHOUT the tag fails when only a non-latest tag exists (docs: other tags must be written out) | Pass |
| MOD-03 | after 'ollama rm' the name stops working (gateway follows Ollama live) | Pass |
| MOD-04 | model names with capitals, dots, underscores, hyphens and a quantisation-style tag work | Pass |

### Configuration recipes

| ID | Check | Result |
|---|---|---|
| CFG-01 | configuration.md pinned aliases (general, coder): /v1/models lists exactly the aliases, aliases answer, the raw Ollama tag is NOT reachable | Pass |
| CFG-02 | aliases AND the catch-all together (docs say untested): both alias and raw tag work | Pass |
| CFG-03 | manual run per configuration.md + api_base to Ollama on a different port (11435): served by that instance only | Pass |

### `.env` parsing

| ID | Check | Result |
|---|---|---|
| ENV-01 | Notepad-style .env: UTF-8 with BOM and CRLF line endings | Pass |
| ENV-02 | value wrapped in double quotes: quotes are stripped | Pass |
| ENV-03 | value wrapped in single quotes: quotes are stripped | Pass |
| ENV-04 | spaces around = and trailing spaces, blank lines and comment lines around it | Pass |
| ENV-05 | no trailing newline at end of file | Pass |
| ENV-06 | ANSI (Windows-1252) comment with accented text before the key | Pass |
| ENV-07 | key containing $ = # & % characters is passed through unchanged | Pass |

### Error messages (every one quoted in the troubleshooting guide)

| ID | Check | Result |
|---|---|---|
| ERR-01 | missing litellm: message + exit 1 | Pass |
| ERR-02 | missing cloudflared: message + exit 1 + nothing started | Pass |
| ERR-03 | port in use: message + exit 1 | Pass |
| ERR-04 | empty LITELLM_MASTER_KEY: refuses to start, nothing started, exit code 1 | Pass |
| ERR-05 | -Tunnel bogus is rejected and the message lists the valid values | Pass |
| ERR-06 | -Port abc is rejected with a readable message | Pass |
| ERR-07 | broken config: "LiteLLM did not come up" + exit 1 + nothing left | Pass |
| ERR-08 | tunnel never reports a URL: message (now hints at internet) + exit 1 + LiteLLM cleaned up | Pass |
| ERR-09 | no internet / quick-tunnel creation fails: the script reports the failure instead of printing a public URL | Pass (after fix) |
| ERR-10 | Ollama not running: message tells the user to start it (app or ollama serve), exit code 1, nothing started | Pass |
| ERR-11 | Ollama reachable but no models pulled: message says to pull one, exit code 1, nothing started | Pass |

### Windows-specific

WIN-01 is the ZIP-download case. Windows itself blocks it under `RemoteSigned`, so the fix is documentation: WIN-02 to WIN-05 confirm the docs' guidance and workarounds.

| ID | Check | Result |
|---|---|---|
| CFG-04 | LiteLLM 1.101.0 started by hand with redirected output and WITHOUT PYTHONUTF8=1 (troubleshooting.md says it crashes on cp1252) | Pass |
| PATH-01 | repo in a folder path with spaces, accented characters and parentheses: starts, serves a real chat, writes logs | Pass |
| WIN-01 | start.ps1 from a downloaded ZIP (Mark-of-the-Web) under RemoteSigned | Fail (Windows behaviour; docs now explain and give tested fixes) |
| WIN-02 | Restricted policy shows the "running scripts is disabled" message that SETUP.md/troubleshooting quote | Pass |
| WIN-03 | documented workaround: powershell -ExecutionPolicy Bypass -File start.ps1 works on ZIP-downloaded files | Pass |
| WIN-04 | Unblock-File on the extracted ZIP, then RemoteSigned run works | Pass |
| WIN-05 | script started from an unrelated working directory still finds its repo, and writes nothing into that directory | Pass |

### Network exposure

| ID | Check | Result |
|---|---|---|
| NET-01 | -BindHost 0.0.0.0 makes the gateway reachable on the LAN address, still key-protected | Pass |
| NET-02 | starting a second instance on a busy port is refused, the first keeps serving | Pass |

### Start, stop and process cleanup

| ID | Check | Result |
|---|---|---|
| CYC-01 | 5 consecutive start -> Ctrl+C cycles: every cycle comes up, serves, and stops cleanly | Pass |
| CYC-02 | .env is not rewritten across restarts (same key every time) | Pass |
| LC-01 | script exits by itself when LiteLLM dies, prints why, exit code 1 (was 0), leaves nothing behind | Pass |
| LC-02 | REAL Ctrl+C (CTRL_C_EVENT to the console) stops start.ps1 -Tunnel none and cleans up | Pass |
| LC-03 | REAL Ctrl+C on a quick-tunnel run: script, LiteLLM and cloudflared all stop; tunnel URL stops working | Pass |
| LC-04 | real Ctrl+C while a request is streaming: the script stops within seconds, the client is released (not left hanging), port freed | Pass |
| MON-01 | tunnel process dies mid-run: script says so, exits with code 1, and stops the gateway too | Pass (after fix) |
| OPS-01 | client disconnects in the middle of a long streamed answer: the GPU is freed (next requests are not queued behind it) | Pass |
| ORPH-01 | force-killing ONLY the script host (taskkill /F, no /T) now takes LiteLLM and cloudflared down with it | Pass |
| ORPH-02 | after an orphaned gateway, the next start reports the busy port, and taskkill /PID <pid> /T /F frees it | Pass |

### Public tunnel

| ID | Check | Result |
|---|---|---|
| ARG-01 | quick mode passes cloudflared: tunnel --config cloudflared/quick-tunnel.yml --url http://127.0.0.1:<port> --no-autoupdate | Pass |
| DNS-01 | a freshly printed quick-tunnel URL can be unreachable for minutes on an ISP resolver even though the tunnel is healthy — Observed on this machine (ISP resolver): hostname resolved fine via 1.1.1.1 and 8.8.8.8 and the tunnel served requests via the resolved IP, but the ISP resolver still returned no address >5 minutes after the URL was printed (earlier runs resolved in ~4s). Not  | Warn |
| NAMED-01 | named, no token, template unfilled -> cloudflared default config | Pass |
| NAMED-02 | named, no token, template filled -> --config cloudflared/config.yml | Pass |
| NAMED-03 | named with token -> token wins | Pass |
| NAMED-04 | named mode with PUBLIC_URL set: summary prints that URL (base_url and example use it) while the tunnel process is healthy | Pass |
| NAMED-05 | named mode without PUBLIC_URL: summary tells the user to add /v1 to their hostname and to set PUBLIC_URL | Pass |
| TUN-01u | quick tunnel URL is printed (https://*.trycloudflare.com) | Pass |
| TUN-02u | public URL starts answering after it is printed | Pass |
| TUN-32 | plain http:// request to the quick-tunnel host is served (no redirect to https) — 200\|redirect= -> a client configured with an http:// base URL would send its API key unencrypted; docs must say to always use https:// | Warn |
| TUN-33 | HTTPS certificate verifies (curl without -k) | Pass |
| TUN-34 | streaming through the tunnel is progressive (tokens arrive over time, not all at the end) | Pass |
| TUN-35 | non-streaming requests longer than 100s through the quick tunnel (Cloudflare 524 claim in docs) | Pass |
| TUN-36 | cloudflared log of a quick-tunnel run contains no ERR lines (quick-tunnel.yml no longer empty) | Pass |

### Security

| ID | Check | Result |
|---|---|---|
| FR-05 | gateway listens on 127.0.0.1 only by default | Pass |
| FR-06 | LAN address is NOT reachable with the default bind (loopback control returns 200) | Pass |
| KEY-01 | deleting .env generates a NEW key; the old key is rejected immediately, the new one works | Pass |
| SEC-01 | endpoints reachable WITHOUT a key on LiteLLM 1.101.0 — / (Swagger UI), /redoc, /openapi.json, /routes, /ui (admin login page), /sso/key/generate, /test, /health/liveliness, /health/readiness answer 200. No keys, models, config or Ollama data are exposed; every functional endpoint (/v1/*, /key/*, /model/*, /metrics | Warn |
| SEC-02 | LiteLLM switches NO_DOCS / NO_REDOC / DISABLE_ADMIN_UI hide the docs pages — Only /redoc is removed. "/", /openapi.json, /routes, /ui and /sso/key/generate stay reachable, so these switches were NOT added to the scripts (they would give false confidence) | Warn |
| SEC-03 | /metrics 401 body mentions an internal module name — body says "No module named prisma" (harmless upstream message) | Info |
| SEC-04 | API key never appears in the log files users are told to paste into bug reports | Pass |

### Autostart (Windows Scheduled Task)

| ID | Check | Result |
|---|---|---|
| AUTO-01 | docs/autostart.md Windows recipe (as now written) registers a Scheduled Task as a normal non-admin user, run verbatim | Pass (after fix) |
| AUTO-02 | recipe with the trigger bound to the current user (-AtLogOn -User $env:USERNAME) registers as a normal user | Pass |
| AUTO-03 | task started via Start-ScheduledTask: hidden-window run brings the gateway up under Task Scheduler and serves requests | Pass |
| AUTO-04 | Stop-ScheduledTask (documented) ends the gateway completely: no LiteLLM process or open port left behind | Pass (after fix) |
| AUTO-05 | Unregister-ScheduledTask (documented) removes the task | Pass |
| AUTO-06 | the scheduled task can be started and stopped repeatedly (2nd cycle clean) | Pass |

### `start.sh` under Git Bash on Windows

This exercised the bash script's logic, but on Windows. Native Linux and macOS are not tested.

| ID | Check | Result |
|---|---|---|
| SH-01 | start.sh first run creates .env with a generated sk- key | Pass |
| SH-02 | start.sh quick tunnel serves the public URL; key required | Pass |
| SH-03 | start.sh public tunnel: real chat answered through the tunnel | Pass |
| SH-04 | start.sh: SIGTERM stops LiteLLM and cloudflared and frees the port (the script traps INT/TERM/EXIT) | Pass |
| SH-05 | start.sh: cloudflared fails with Cloudflare's API address in its error -> reports failure, no fake Public URL, exit 1 | Pass |
| SH-06 | start.sh: tunnel process dies mid-run -> script says so, exits 1, stops the gateway | Pass |
| SH-07 | start.sh: LiteLLM dies unexpectedly -> 'LiteLLM exited' message, exit code 1 (was 0), nothing left running | Pass |

### Documentation commands and snippets

| ID | Check | Result |
|---|---|---|
| CL-11 | every markdown file has balanced code fences | Pass |
| CL-14 | all relative links and #anchors resolve | Pass |
| CL-15 | all 20 external URLs in the docs resolve | Pass |
| DOC-01 | README.md quick-start Python snippet (OpenAI SDK, placeholders substituted) | Pass |
| DOC-02 | SETUP.md step 6 PowerShell Invoke-RestMethod snippet, verbatim, Windows PowerShell 5.1 | Pass |
| DOC-03 | SETUP.md step 6 curl snippet (macOS/Linux form) run under Git Bash | Pass |
| DOC-04 | using-the-api.md curl snippet | Pass |
| DOC-05 | using-the-api.md PowerShell snippet (hashtable + ConvertTo-Json), Windows PowerShell 5.1 | Pass |
| DOC-06 | using-the-api.md Python snippet (system + user message) | Pass |
| DOC-07 | using-the-api.md Python STREAMING snippet run on its own | Pass (after fix) |
| DOC-08 | using-the-api.md JavaScript snippet (non-streaming + streaming, Node + openai SDK) | Pass |
| DOC-09 | troubleshooting.md layer-1 checks: Invoke-RestMethod / curl.exe against Ollama /api/tags list models | Pass |
| DOC-10 | troubleshooting.md: Get-NetTCPConnection -LocalPort 4000 shows the gateway | Pass |
| DOC-11 | configuration.md key generator one-liner produces an sk- key that the gateway accepts as a master key format | Pass |
| DOC-12 | tunnels.md: cloudflared tunnel --config cloudflared/config.yml ingress validate accepts the shipped template | Pass |
| DOC-13 | troubleshooting.md: in Windows PowerShell 5.1, curl is an alias for Invoke-WebRequest | Pass |
| DOC-14 | SETUP.md step 9: pip install -U "litellm[proxy]" runs cleanly (venv) | Pass |
| DOC-15 | SETUP.md step 9: uv tool upgrade litellm runs cleanly (isolated uv dirs) | Pass |
| FAQ-01a | faq.md: after many runs, the script created nothing in the project folder except .env and logs/ (hp-fix) | Pass |
| FAQ-01b | faq.md: after many runs, the script created nothing in the project folder except .env and logs/ (hp-first) | Pass |
| UNI-01 | SETUP.md step 9: uv tool uninstall litellm removes the tool (isolated uv dirs) | Pass |
| UNI-02 | SETUP.md step 9: pip uninstall litellm removes the package and its command (throwaway venv) | Pass |

### Soak test (fixed scripts, real quick tunnel)

| ID | Check | Result |
|---|---|---|
| SOAK-01 | steady load through the public quick tunnel for ~50 minutes: every request succeeds — 45/45 tunnel requests ok; latency median 3.1s p95 4.4s; failures: [] | Pass |
| SOAK-02 | same load against localhost: every request succeeds — 45/45 local requests ok; latency median 1.0s p95 1.4s | Pass |
| SOAK-03 | after >5 min idle Ollama unloads the model, and the next request through the tunnel still succeeds (reload) — model unloaded during idle=True; first request after idle: tunnel 200 5.8s, local 200 0.9s (warm median ~0.9s). Tunnel connection survived 7 idle minutes | Pass |
| SOAK-04 | memory stays flat over the run (no leak in LiteLLM or cloudflared) — LiteLLM (single gateway): 288 MB at start, 304 MB at 10 min, 308 MB at the end (+20 MB over 50 minutes and ~100 requests); cloudflared 38-39 MB throughout. The samples at 30 and 40 minutes read ~610-650 MB because they also counted a SECOND LiteLLM instance th | Pass |
| SOAK-05 | tunnel URL and processes still alive at the end (same URL for the whole run) — final process sample (308, 38, 2); URL unchanged for 50 min | Pass |

### Performance notes

| ID | Check | Result |
|---|---|---|
| PERF-01 | startup time of the fixed script with a quick tunnel (Job Object compile included) — 8.9s to LiteLLM ready, 15.5s to tunnel URL printed (warm start of the unfixed script: ~7s to LiteLLM ready) | Info |

## Not tested

Being clear about the gaps matters more than a tidy report.

- **macOS and native Linux.** `start.sh` was run under Git Bash on Windows only (its logic works, including cleanup on SIGTERM), but not on a real Linux or macOS system. A foreground-terminal Ctrl+C for `start.sh` was not exercised either.
- **PowerShell 7, Windows 10, ARM Windows.** Only Windows PowerShell 5.1 on Windows 11 x64 was used.
- **A real named Cloudflare tunnel.** That needs a Cloudflare account and a domain. What *was* verified: the template validates, the scripts pick the right `cloudflared` arguments in all three modes, and they fail cleanly when cloudflared fails (NAMED-01 to NAMED-03, ARG-01).
- **Tailscale Funnel and the private Tailscale option.** Tailscale wasn't installed.
- **Reboot and the logon trigger.** The Scheduled Task was started and stopped by hand, not by an actual logon or restart.
- **Closing the console window with the X button, sleep/hibernate, and switching networks** while a tunnel is up.
- **Access from a genuinely different network** (for example a phone on mobile data). The public path was exercised over the internet from this machine, not from another location.
- **Other models and hardware.** One 12B "thinking" model on an NVIDIA GPU. CPU-only speed, other model families, image/tool-calling/embedding requests were not tested.
- **Newer Ollama and cloudflared.** Newer releases of both existed at the time of testing.
- **Windows firewall behaviour** with `-BindHost 0.0.0.0`: LAN access worked from the machine itself, but whether a firewall prompt appears for a first-time user wasn't observed.
- **Logging in to LiteLLM's admin UI.** The page is reachable without a key; using it wasn't tested.

## Re-running this

- **API checks:** `python tests/api_tests.py --base http://localhost:4000 --key <your key> --model <model>` (see [tests/README.md](../tests/README.md)).
- **Manual checklist** for the things a script can't check, including what to look for on macOS and Linux: [tests/README.md](../tests/README.md#checklist-for-the-things-a-script-cant-check).
- **Report a result** from a platform not listed above by opening an issue with your OS, versions and what you ran. Remove your API key and tunnel URL first.
