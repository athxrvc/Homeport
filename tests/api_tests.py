#!/usr/bin/env python3
"""Homeport API test suite.

Runs the same checks against any Homeport URL (http://localhost:4000 or a public tunnel) and prints
PASS / WARN / FAIL / INFO for each. Only Python 3.9+ is required (checked on 3.9, 3.13 and 3.14); the OpenAI SDK checks run if `openai` is installed.

    python tests/api_tests.py --base http://localhost:4000 --key sk-YOUR-KEY --model llama3.2:latest
    python tests/api_tests.py --base https://<your-url> --key sk-YOUR-KEY --model llama3.2:latest --json report.json

Exit code is 1 if any check FAILs. What each status means:
  PASS  behaved as documented
  FAIL  a Homeport / gateway problem (the structure of the API is wrong, auth is missing, Ollama is exposed, ...)
  WARN  depends on the model or on upstream behaviour (e.g. a model that ignores a system prompt); worth a look, not a bug
  INFO  recorded for reference (for example which endpoints answer without a key)

The checks send real requests to your model, so expect a minute or two of GPU time. Use --quick to skip the slowest ones.
"""
import argparse
import concurrent.futures as cf
import json
import sys
import time
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # Windows pipes default to cp1252
except Exception:
    pass

ap = argparse.ArgumentParser(description="Homeport API test suite")
ap.add_argument("--base", default="http://localhost:4000", help="gateway URL without /v1 (default: http://localhost:4000)")
ap.add_argument("--key", required=True, help="the LITELLM_MASTER_KEY from your .env")
ap.add_argument("--model", required=True, help="a model name from `ollama list`, e.g. llama3.2:latest")
ap.add_argument("--max-tokens", type=int, default=800, help="token budget for checks that read the answer (raise it for reasoning models)")
ap.add_argument("--quick", action="store_true", help="skip the concurrency and OpenAI SDK checks")
ap.add_argument("--json", metavar="FILE", help="also write the results to FILE as JSON")
args = ap.parse_args()

BASE, KEY, MODEL, MAXT = args.base.rstrip("/"), args.key, args.model, args.max_tokens
UA = {"User-Agent": "homeport-tests/1.0"}
results = []


def rec(tid, name, status, detail=""):
    results.append({"id": tid, "name": name, "status": status, "detail": detail})
    print(f"[{status}] {tid} {name}" + (f": {detail}" if detail else ""), flush=True)


def req(method, path, key=KEY, body=None, headers=None, timeout=300, raw=None):
    h = dict(UA)
    if key:
        h["Authorization"] = f"Bearer {key}"
    if body is not None or raw is not None:
        h["Content-Type"] = "application/json"
    if headers:
        h.update(headers)
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    r = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    t = time.time()
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace"), time.time() - t
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), time.time() - t
    except Exception as e:  # connection-level failure
        return 0, f"{type(e).__name__}: {e}", time.time() - t


def chat(prompt="Reply with exactly: pong", model=None, **kw):
    body = {"model": model or MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": MAXT}
    body.update(kw)
    return req("POST", "/v1/chat/completions", body=body)


def jl(s):
    try:
        return json.loads(s)
    except Exception:
        return {}


def text(resp):
    try:
        return jl(resp)["choices"][0]["message"].get("content") or ""
    except Exception:
        return ""


# ---- reachability ---------------------------------------------------------------------------
c, b, _ = req("GET", "/health/liveliness", key=None, timeout=30)
if c != 200:
    rec("00", "gateway is reachable", "FAIL", f"GET /health/liveliness -> HTTP {c} {b[:100]}. Is it running? Is the URL right?")
    if args.json:
        json.dump(results, open(args.json, "w"), indent=2)
    sys.exit(1)
rec("00", "gateway is reachable (GET /health/liveliness, no key needed)", "PASS", "HTTP 200")

# ---- authentication -------------------------------------------------------------------------
c, b, _ = chat()
rec("01", "chat with the correct key returns HTTP 200", "PASS" if c == 200 else "FAIL", f"HTTP {c}" + ("" if c == 200 else f": {b[:120]}"))
if c != 200:
    print("Cannot continue without a working chat request. Check the key and the model name.")
    if args.json:
        json.dump(results, open(args.json, "w"), indent=2)
    sys.exit(1)
d = jl(b)
shape = d.get("object") == "chat.completion" and d["choices"][0]["message"]["role"] == "assistant" and "usage" in d and d.get("id")
rec("02", "response has the OpenAI shape (id, object, choices[0].message.role, usage)", "PASS" if shape else "FAIL")
c, b, _ = req("POST", "/v1/chat/completions", key=None, body={"model": MODEL, "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5})
rec("03", "a request WITHOUT a key is rejected and no completion is served", "PASS" if c != 200 and "choices" not in b else "FAIL", f"HTTP {c} (500/400 rather than 401 is a known LiteLLM quirk)")
c, b, _ = req("POST", "/v1/chat/completions", key="sk-not-the-key", body={"model": MODEL, "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5})
rec("04", "a request with a WRONG key is rejected and no completion is served", "PASS" if c != 200 and "choices" not in b else "FAIL", f"HTTP {c}")
c, b, _ = req("POST", "/v1/chat/completions", key=None, body={"model": MODEL, "messages": [{"role": "user", "content": "hi"}], "max_tokens": 5}, headers={"Authorization": f"bearer {KEY}"})
rec("05", "lowercase 'bearer' scheme is accepted", "PASS" if c == 200 else "WARN", f"HTTP {c}")

# ---- Ollama must never be exposed ------------------------------------------------------------
leaks = []
for path, m in (("/api/tags", "GET"), ("/api/version", "GET"), ("/api/generate", "POST"), ("/api/chat", "POST")):
    for k in (None, KEY):
        c, b, _ = req(m, path, key=k, body={} if m == "POST" else None, timeout=30)
        if c == 200:
            leaks.append(f"{m} {path} (key={'yes' if k else 'no'})")
rec("06", "Ollama's own API (/api/*) is NOT reachable through the gateway, with or without the key", "PASS" if not leaks else "FAIL", "; ".join(leaks) or "all four probes refused")

# ---- model names -----------------------------------------------------------------------------
base_name = MODEL.split(":")[0] if MODEL.endswith(":latest") else None
if base_name:
    c, b, _ = chat(model=base_name)
    rec("07", f"the model name works without the ':latest' tag ({base_name})", "PASS" if c == 200 else "FAIL", f"HTTP {c}")
c, b, _ = chat(model="homeport-no-such-model:latest")
rec("08", "an unknown model gives an error that names the model (no hang, no 200)", "PASS" if c >= 400 and "not found" in b.lower() else "FAIL", f"HTTP {c}: {b[:100]}")

# ---- content (model-dependent, so mismatches are WARN not FAIL) --------------------------------
c, b, _ = chat("Reply with exactly: pong")
rec("09", "the model follows a trivial instruction ('pong')", "PASS" if "pong" in text(b).lower() else "WARN", repr(text(b))[:50])
c, b, _ = req("POST", "/v1/chat/completions", body={"model": MODEL, "max_tokens": MAXT, "messages": [
    {"role": "system", "content": "You always answer with the single word BANANA and nothing else."},
    {"role": "user", "content": "What is your favourite fruit?"}]})
rec("10", "a system message is passed through and honoured", "PASS" if "banana" in text(b).lower() else "WARN", repr(text(b))[:50])
c, b, _ = req("POST", "/v1/chat/completions", body={"model": MODEL, "max_tokens": MAXT, "messages": [
    {"role": "user", "content": "My secret word is PINEAPPLE. Remember it."},
    {"role": "assistant", "content": "Understood, I will remember PINEAPPLE."},
    {"role": "user", "content": "What was my secret word? Answer with the word only."}]})
rec("11", "multi-turn history is passed through (the model recalls the earlier turn)", "PASS" if "pineapple" in text(b).lower() else "WARN", repr(text(b))[:50])
c, b, _ = chat("Repeat exactly this text and nothing else: héllo wörld \U0001F680 Ω")
ok = all(x in text(b) for x in ("héllo", "wörld", "\U0001F680", "Ω"))
rec("12", "accents, an emoji and a Greek letter survive the round trip", "PASS" if ok else "WARN", repr(text(b))[:50])
c, b, _ = chat("Write a very long story.", max_tokens=5)
d = jl(b)
ok = c == 200 and d["choices"][0]["finish_reason"] == "length" and d["usage"]["completion_tokens"] <= 8
rec("13", "max_tokens is enforced (finish_reason=length, only a few tokens)", "PASS" if ok else "FAIL", f"HTTP {c}")

# ---- streaming -------------------------------------------------------------------------------
sr = urllib.request.Request(BASE + "/v1/chat/completions", method="POST", headers={**UA, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
                            data=json.dumps({"model": MODEL, "stream": True, "stream_options": {"include_usage": True}, "max_tokens": MAXT,
                                             "messages": [{"role": "user", "content": "Count from 1 to 8 separated by spaces."}]}).encode())
try:
    with urllib.request.urlopen(sr, timeout=300) as resp:
        ctype = resp.headers.get("Content-Type", "")
        lines = [raw.decode().strip() for raw in resp if raw.strip()]
    datas = [ln for ln in lines if ln.startswith("data:")]
    chunks = [json.loads(ln[5:]) for ln in datas if ln != "data: [DONE]"]
    rec("14", "streaming: text/event-stream, 'data:' lines, terminated by [DONE]", "PASS" if "event-stream" in ctype and datas and datas[-1] == "data: [DONE]" and len(chunks) > 1 else "FAIL", f"{len(chunks)} chunks")
    rec("15", "streaming: a final usage chunk is sent when stream_options.include_usage=true", "PASS" if any(c_.get("usage") for c_ in chunks) else "WARN")
except Exception as e:
    rec("14", "streaming works", "FAIL", f"{type(e).__name__}: {e}")

# ---- robustness ------------------------------------------------------------------------------
c, b, _ = req("POST", "/v1/chat/completions", raw=b"{not json")
rec("16", "malformed JSON gets a 4xx/5xx error, not a crash", "PASS" if 400 <= c < 600 else "FAIL", f"HTTP {c}")
c, b, _ = req("GET", "/v1/chat/completions")
rec("17", "GET on the chat endpoint returns 405", "PASS" if c == 405 else "WARN", f"HTTP {c}")
c, b, _ = chat()
rec("18", "the gateway is still healthy after the malformed requests", "PASS" if c == 200 else "FAIL", f"HTTP {c}")

# ---- what can a stranger with only the URL see? ----------------------------------------------------
openp = []
for p in ("/", "/redoc", "/openapi.json", "/routes", "/ui", "/health/liveliness", "/health/readiness", "/v1/models", "/metrics", "/key/generate", "/model/info"):
    c, b, _ = req("POST" if p == "/key/generate" else "GET", p, key=None, body={} if p == "/key/generate" else None, timeout=30)
    if c == 200:
        openp.append(p)
rec("19", "endpoints that answer 200 WITHOUT a key (for the security review)", "INFO", ", ".join(openp) or "none")
bad = [p for p in openp if p in ("/v1/models", "/metrics", "/key/generate", "/model/info")]
rec("20", "functional endpoints (/v1/models, /key/*, /model/*, /metrics) require the key", "PASS" if not bad else "FAIL", "; ".join(bad) or "all refused")
c, b, _ = req("GET", "/v1/models")
try:
    ids = [m["id"] for m in jl(b)["data"]]
except Exception:
    ids = []
rec("21", "/v1/models works with the key", "PASS" if c == 200 else "FAIL", f"ids: {ids[:4]}")

# ---- concurrency + SDK -----------------------------------------------------------------------
if not args.quick:
    def one(i):
        c_, b_, t_ = chat(f"Reply with exactly the number {i}")
        return c_ == 200 and bool(text(b_)), t_
    t0 = time.time()
    with cf.ThreadPoolExecutor(4) as ex:
        res = list(ex.map(one, range(1, 5)))
    rec("22", "4 simultaneous requests all complete", "PASS" if all(ok for ok, _ in res) else "FAIL", f"{sum(ok for ok, _ in res)}/4 ok in {time.time() - t0:.1f}s")
    try:
        from openai import OpenAI
        cl = OpenAI(base_url=BASE + "/v1", api_key=KEY, timeout=300)
        rec("23", "openai SDK: models.list()", "PASS" if cl.models.list().data is not None else "FAIL")
        r = cl.chat.completions.create(model=MODEL, messages=[{"role": "user", "content": "Reply with exactly: pong"}], max_tokens=MAXT)
        rec("24", "openai SDK: chat.completions.create()", "PASS" if r.choices else "FAIL", repr(r.choices[0].message.content)[:40])
        n = sum(1 for _ in cl.chat.completions.create(model=MODEL, messages=[{"role": "user", "content": "Count 1 to 5"}], max_tokens=MAXT, stream=True))
        rec("25", "openai SDK: streaming iterator", "PASS" if n > 3 else "FAIL", f"{n} events")
        try:
            OpenAI(base_url=BASE + "/v1", api_key="sk-wrong", timeout=60).chat.completions.create(model=MODEL, messages=[{"role": "user", "content": "hi"}], max_tokens=5)
            rec("26", "openai SDK with a wrong key raises an exception", "FAIL", "no exception")
        except Exception as e:
            rec("26", "openai SDK with a wrong key raises an exception", "PASS", type(e).__name__)
    except ImportError:
        rec("23", "openai SDK checks", "INFO", "skipped: `pip install openai` to enable")

# ---- summary ---------------------------------------------------------------------------------
counts = {s: sum(1 for r in results if r["status"] == s) for s in ("PASS", "WARN", "FAIL", "INFO")}
print(f"\nSummary: {counts['PASS']} pass, {counts['WARN']} warn, {counts['FAIL']} fail, {counts['INFO']} info")
if args.json:
    json.dump({"base": BASE, "model": MODEL, "counts": counts, "results": results}, open(args.json, "w"), indent=2)
sys.exit(1 if counts["FAIL"] else 0)
