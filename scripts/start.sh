#!/usr/bin/env bash
# Start the gateway: LiteLLM in front of your local Ollama, plus an optional public tunnel.
#
# Usage: scripts/start.sh [--tunnel quick|named|none] [--port 4000]
#   quick  (default) Free Cloudflare quick tunnel. No account, random URL each run.
#   named  Cloudflare named tunnel. Stable URL on your own domain (see SETUP.md).
#   none   Local only, no public URL.
# Options: --port N   (default 4000)
#          --host H   (default 127.0.0.1 = this machine only; 0.0.0.0 also allows your LAN)
set -euo pipefail

TUNNEL=quick
PORT=4000
HOST=127.0.0.1
while [ $# -gt 0 ]; do
  case "$1" in
    --tunnel) TUNNEL="${2:-}"; shift 2 ;;
    --port)   PORT="${2:-}"; shift 2 ;;
    --host)   HOST="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
done
case "$TUNNEL" in quick|named|none) ;; *) echo "--tunnel must be quick, named or none" >&2; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "'$1' not found. $2"; }

# --- 1. Prerequisites ---------------------------------------------------------
need litellm 'Install it with: pip install "litellm[proxy]"'
need curl 'Install curl.'
[ "$TUNNEL" = none ] || need cloudflared 'Install it from https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/'

if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/"; then
  fail "Port $PORT is already in use. Stop whatever is using it, or pass --port <other>."
fi

TAGS="$(curl -s --max-time 5 http://127.0.0.1:11434/api/tags)" \
  || fail "Can't reach Ollama at http://localhost:11434. Start it ('ollama serve') and retry."
# First model name, without needing jq.
EXAMPLE_MODEL="$(printf '%s' "$TAGS" | grep -o '"name":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
[ -n "$EXAMPLE_MODEL" ] || fail "Ollama has no models yet. Pull one first, e.g.: ollama pull llama3.2"

# --- 2. .env (create with a fresh master key on first run) --------------------
if [ ! -f .env ]; then
  KEY="sk-$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=\n')"
  sed "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=$KEY|" .env.example > .env
  echo "Created .env with a new master key."
fi
set -a; . ./.env; set +a
[ -n "${LITELLM_MASTER_KEY:-}" ] || fail "LITELLM_MASTER_KEY is empty in .env. Refusing to start without auth."

# LiteLLM prints a Unicode banner; on Windows (Git Bash) redirected output defaults to cp1252 and crashes without this.
export PYTHONUTF8=1

mkdir -p logs
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

# --- 3. LiteLLM ---------------------------------------------------------------
echo "Starting LiteLLM on port $PORT ..."
litellm --config LiteLLM/config.yaml --host "$HOST" --port "$PORT" >logs/litellm.log 2>&1 &
LITE_PID=$!; PIDS+=("$LITE_PID")

ready=0
for _ in $(seq 1 60); do
  kill -0 "$LITE_PID" 2>/dev/null || break
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/health/readiness"; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || fail "LiteLLM didn't come up. See logs/litellm.log"

# --- 4. Tunnel ----------------------------------------------------------------
PUBLIC_URL_OUT=""
if [ "$TUNNEL" = quick ]; then
  echo "Opening quick tunnel ..."
  cloudflared tunnel --config cloudflared/quick-tunnel.yml --url "http://127.0.0.1:$PORT" --no-autoupdate >logs/cloudflared.log 2>&1 &
  CF_PID=$!; PIDS+=("$CF_PID")
  for _ in $(seq 1 40); do
    kill -0 "$CF_PID" 2>/dev/null || break
    # Skip api.trycloudflare.com: when cloudflared can't reach the internet it prints Cloudflare's API address in its
    # error message, and that must never be mistaken for the tunnel's public URL.
    PUBLIC_URL_OUT="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' logs/cloudflared.log | grep -v '^https://api\.' | head -n1 || true)"
    [ -n "$PUBLIC_URL_OUT" ] && break
    sleep 1
  done
  kill -0 "$CF_PID" 2>/dev/null || fail "cloudflared exited before the tunnel was ready (no internet connection?). See logs/cloudflared.log"
  [ -n "$PUBLIC_URL_OUT" ] || fail "Tunnel didn't report a URL (no internet connection?). See logs/cloudflared.log"
elif [ "$TUNNEL" = named ]; then
  echo "Starting named tunnel ..."
  if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" >logs/cloudflared.log 2>&1 &
  elif [ -f cloudflared/config.yml ] && ! grep -q '<TUNNEL-UUID>' cloudflared/config.yml; then
    cloudflared tunnel --no-autoupdate --config cloudflared/config.yml run >logs/cloudflared.log 2>&1 &
  else
    # Repo template not filled in: use cloudflared's own default config (~/.cloudflared/config.yml).
    cloudflared tunnel --no-autoupdate run >logs/cloudflared.log 2>&1 &
  fi
  CF_PID=$!; PIDS+=("$CF_PID")
  sleep 4
  kill -0 "$CF_PID" 2>/dev/null || fail "cloudflared exited. See logs/cloudflared.log"
  PUBLIC_URL_OUT="${PUBLIC_URL:-}"   # cloudflared can't tell us the hostname, so it's optional in .env
fi

# --- 5. Summary ---------------------------------------------------------------
BASE="http://localhost:$PORT"
[ -n "$PUBLIC_URL_OUT" ] && BASE="${PUBLIC_URL_OUT%/}"

echo
echo "Gateway is up."
echo "  Local URL : http://localhost:$PORT/v1"
if [ -n "$PUBLIC_URL_OUT" ]; then
  echo "  Public URL: $BASE/v1"
elif [ "$TUNNEL" = named ]; then
  echo "  Public URL: (the hostname you mapped to the tunnel, add /v1; set PUBLIC_URL in .env to see it here)"
fi
echo "  API key   : $LITELLM_MASTER_KEY"
echo
echo "Try it:"
echo "  curl $BASE/v1/chat/completions \\"
echo "    -H 'Authorization: Bearer <key>' -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\":\"$EXAMPLE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
echo
echo "Any OpenAI SDK: base_url = $BASE/v1 , api_key = <key above> , model = $EXAMPLE_MODEL"
[ "$TUNNEL" != quick ] || echo "Quick-tunnel URLs change every run; use --tunnel named for a permanent one."
echo "Press Ctrl+C to stop."

CF_PID="${CF_PID:-}"
while kill -0 "$LITE_PID" 2>/dev/null; do
  if [ -n "$CF_PID" ] && ! kill -0 "$CF_PID" 2>/dev/null; then
    echo "The tunnel (cloudflared) stopped, so the public URL no longer works. See logs/cloudflared.log. Stopping; start the script again for a new URL." >&2
    exit 1
  fi
  sleep 2
done
echo "LiteLLM exited. See logs/litellm.log" >&2
exit 1
