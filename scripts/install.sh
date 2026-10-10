#!/usr/bin/env bash
# Install everything Homeport needs: Ollama, LiteLLM (in a private .venv) and cloudflared.
# Safe to run again: anything already installed is kept, and LiteLLM is upgraded.
#
# Usage: scripts/install.sh [--model NAME] [--no-model] [--no-tunnel]
#   --model NAME  Model to pull if Ollama has none yet (default llama3.2, about 2 GB)
#   --no-model    Don't pull a model
#   --no-tunnel   Skip cloudflared (local-only use)
set -euo pipefail

MODEL=llama3.2
PULL_MODEL=1
TUNNEL=1
while [ $# -gt 0 ]; do
  case "$1" in
    --model)     MODEL="${2:-}"; shift 2 ;;
    --no-model)  PULL_MODEL=0; shift ;;
    --no-tunnel) TUNNEL=0; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VENV="$ROOT/.venv"

fail() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
case "$OS" in Darwin|Linux) ;; *) fail "Unsupported OS '$OS'. On Windows, run scripts\\install.ps1 in PowerShell." ;; esac
have curl || fail "'curl' not found. Install curl and run this again."
if [ "$OS" = Darwin ] && ! have brew; then
  fail "Homebrew not found. Install it from https://brew.sh and run this again."
fi

# --- 1. Python 3.10+ ----------------------------------------------------------
# LiteLLM needs 3.10 or newer. macOS ships 3.9, which half-works and prints TypeErrors.
step "Python 3.10 or newer"
py_ok() { "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; }
PY=""
# Prefer the versions LiteLLM is most tested on, then anything newer.
for c in python3.12 python3.13 python3.11 python3.10 python3.14 python3.15 python3; do
  if have "$c" && py_ok "$c"; then PY="$(command -v "$c")"; break; fi
done
if [ -z "$PY" ]; then
  if [ "$OS" = Darwin ]; then
    echo "Installing Python 3.12 with Homebrew ..."
    brew install python@3.12
    PY="$(brew --prefix python@3.12)/bin/python3.12"
  else
    fail "Python 3.10+ not found. Install it with your package manager (e.g. 'sudo apt install python3 python3-venv') and run this again."
  fi
fi
echo "Using $PY ($("$PY" --version))"

# --- 2. LiteLLM in .venv ------------------------------------------------------
step "LiteLLM (into .venv)"
if [ -x "$VENV/bin/python" ] && ! py_ok "$VENV/bin/python"; then
  echo "Existing .venv uses an old Python; recreating it."
  rm -rf "$VENV"
fi
if [ ! -x "$VENV/bin/python" ]; then
  "$PY" -m venv "$VENV" \
    || fail "Couldn't create a virtual environment. On Debian/Ubuntu: sudo apt install python3-venv"
fi
"$VENV/bin/python" -m pip install --quiet --upgrade pip
"$VENV/bin/python" -m pip install --quiet --upgrade "litellm[proxy]"
echo "LiteLLM $("$VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("litellm"))') installed."

# --- 3. cloudflared -----------------------------------------------------------
if [ "$TUNNEL" = 1 ]; then
  step "cloudflared"
  if have cloudflared || [ -x "$VENV/bin/cloudflared" ]; then
    echo "Already installed."
  elif [ "$OS" = Darwin ]; then
    brew install cloudflared
  else
    case "$(uname -m)" in
      x86_64|amd64)  ARCH=amd64 ;;
      aarch64|arm64) ARCH=arm64 ;;
      armv7l|armhf)  ARCH=arm ;;
      *) fail "No cloudflared download for $(uname -m). See https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" ;;
    esac
    # Into .venv/bin so it needs no sudo; start.sh looks there.
    echo "Downloading cloudflared ($ARCH) ..."
    curl -fsSL -o "$VENV/bin/cloudflared" \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH"
    chmod +x "$VENV/bin/cloudflared"
  fi
fi

# --- 4. Ollama ----------------------------------------------------------------
step "Ollama"
if have ollama; then
  echo "Already installed."
elif [ "$OS" = Darwin ]; then
  brew install ollama
  brew services start ollama
else
  echo "Running Ollama's official installer (it may ask for your password) ..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

ollama_up() { curl -s -o /dev/null --max-time 2 http://127.0.0.1:11434/api/tags; }
if ! ollama_up; then
  echo "Starting Ollama ..."
  if [ "$OS" = Darwin ] && [ -d /Applications/Ollama.app ]; then
    open -a Ollama
  else
    nohup ollama serve >/dev/null 2>&1 &
  fi
  for _ in $(seq 1 20); do ollama_up && break; sleep 1; done
fi

# --- 5. A model ---------------------------------------------------------------
if ! ollama_up; then
  echo "Ollama is installed but not running. Start it (open the Ollama app or run 'ollama serve') before scripts/start.sh."
elif curl -s --max-time 5 http://127.0.0.1:11434/api/tags | grep -q '"name"'; then
  echo "Ollama is running and has models."
elif [ "$PULL_MODEL" = 1 ]; then
  step "Pulling $MODEL (first model; this can take a while)"
  ollama pull "$MODEL"
else
  echo "Ollama has no models yet. Pull one before starting, e.g.: ollama pull llama3.2"
fi

echo
echo "All set. Start the gateway with:"
echo "  ./scripts/start.sh"
