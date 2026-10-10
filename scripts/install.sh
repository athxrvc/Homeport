#!/usr/bin/env bash
# Install everything Homeport needs: Ollama, LiteLLM (in a private .venv) and cloudflared.
# Safe to run again: anything already installed is kept, and LiteLLM is upgraded.
# On macOS everything is downloaded from its official source: no Homebrew, no sudo.
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
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VENV="$ROOT/.venv"
TOOLS="$ROOT/.tools"   # private downloads (uv and its Python on macOS); delete the folder to remove them

fail() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
case "$OS" in Darwin|Linux) ;; *) fail "Unsupported OS '$OS'. On Windows, run scripts\\install.ps1 in PowerShell." ;; esac
have curl || fail "'curl' not found. Install curl and run this again."

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
    # No Homebrew and no installer that asks for a password: use uv (from astral.sh) to download a private
    # copy of Python 3.12 into .tools. uv's installer is told not to touch PATH or your shell profile.
    echo "No Python 3.10+ found. Downloading a private Python 3.12 into .tools (via uv, from astral.sh) ..."
    # Keep everything uv does inside .tools: its Python, and its download cache (otherwise ~/.cache/uv).
    export UV_PYTHON_INSTALL_DIR="$TOOLS/python"
    export UV_CACHE_DIR="$TOOLS/cache"
    # Always use our own copy of uv, so the version doesn't depend on whatever the user may have installed.
    UVBIN="$TOOLS/uv"
    if [ ! -x "$UVBIN" ]; then
      mkdir -p "$TOOLS"
      curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="$TOOLS" UV_NO_MODIFY_PATH=1 sh \
        || fail "Couldn't download uv from astral.sh. Check your internet connection, or install Python 3.10+ yourself (https://www.python.org/downloads/) and run this again."
      [ -x "$UVBIN" ] || fail "uv was downloaded but couldn't be found in $TOOLS."
    fi
    # --no-bin: don't also link python3.12 into ~/.local/bin (that would put a file outside the project).
    "$UVBIN" python install --no-bin 3.12 \
      || fail "Couldn't download Python 3.12. Check your internet connection, or install Python 3.10+ yourself (https://www.python.org/downloads/) and run this again."
    PY="$("$UVBIN" python find 3.12)"
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
  rm -rf "$VENV"   # a leftover or broken .venv (for example one whose Python was removed)
  if [ -n "${UVBIN:-}" ]; then
    # The Python came from uv, so create the environment with uv too. --seed installs pip into it.
    "$UVBIN" venv --python "$PY" --seed "$VENV" \
      || fail "Couldn't create a virtual environment with uv."
  else
    "$PY" -m venv "$VENV" \
      || fail "Couldn't create a virtual environment. On Debian/Ubuntu: sudo apt install python3-venv"
  fi
fi
"$VENV/bin/python" -m pip install --quiet --upgrade pip
"$VENV/bin/python" -m pip install --quiet --upgrade "litellm[proxy]"
echo "LiteLLM $("$VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("litellm"))') installed."

# --- 3. cloudflared -----------------------------------------------------------
if [ "$TUNNEL" = 1 ]; then
  step "cloudflared"
  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download"
  if have cloudflared || [ -x "$VENV/bin/cloudflared" ]; then
    echo "Already installed."
  elif [ "$OS" = Darwin ]; then
    case "$(uname -m)" in
      arm64|aarch64) ARCH=arm64 ;;
      x86_64)        ARCH=amd64 ;;
      *) fail "No cloudflared download for $(uname -m). See https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" ;;
    esac
    # Into .venv/bin so it needs no sudo; start.sh looks there.
    echo "Downloading cloudflared (macOS $ARCH) ..."
    CF_TMP="$(mktemp -d)"
    curl -fsSL -o "$CF_TMP/cloudflared.tgz" "$CF_URL/cloudflared-darwin-$ARCH.tgz" \
      || { rm -rf "$CF_TMP"; fail "Couldn't download cloudflared. Check your internet connection, or run with --no-tunnel for local-only use."; }
    tar -xzf "$CF_TMP/cloudflared.tgz" -C "$CF_TMP" \
      || { rm -rf "$CF_TMP"; fail "Couldn't unpack the cloudflared download."; }
    [ -f "$CF_TMP/cloudflared" ] || { rm -rf "$CF_TMP"; fail "The cloudflared download didn't contain the cloudflared program."; }
    mv "$CF_TMP/cloudflared" "$VENV/bin/cloudflared"
    chmod +x "$VENV/bin/cloudflared"
    rm -rf "$CF_TMP"
  else
    case "$(uname -m)" in
      x86_64|amd64)  ARCH=amd64 ;;
      aarch64|arm64) ARCH=arm64 ;;
      armv7l|armhf)  ARCH=arm ;;
      *) fail "No cloudflared download for $(uname -m). See https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" ;;
    esac
    # Into .venv/bin so it needs no sudo; start.sh looks there.
    echo "Downloading cloudflared ($ARCH) ..."
    curl -fsSL -o "$VENV/bin/cloudflared" "$CF_URL/cloudflared-linux-$ARCH"
    chmod +x "$VENV/bin/cloudflared"
  fi
fi

# --- 4. Ollama ----------------------------------------------------------------
step "Ollama"
OLLAMA_APP=""   # macOS: the Ollama.app bundle, if there is one
if [ "$OS" = Darwin ]; then
  for a in /Applications/Ollama.app "$HOME/Applications/Ollama.app"; do
    if [ -d "$a" ]; then OLLAMA_APP="$a"; break; fi
  done
fi

if have ollama || [ -n "$OLLAMA_APP" ]; then
  echo "Already installed."
elif [ "$OS" = Darwin ]; then
  # The official download from ollama.com: a zip with Ollama.app. Put it in /Applications, or in
  # ~/Applications if that isn't writable (so no password is needed).
  echo "Downloading Ollama for macOS from ollama.com (about 200 MB) ..."
  OL_TMP="$(mktemp -d)"
  curl -fL --progress-bar -o "$OL_TMP/Ollama-darwin.zip" https://ollama.com/download/Ollama-darwin.zip \
    || { rm -rf "$OL_TMP"; fail "Couldn't download Ollama. Download it from https://ollama.com/download and run this again."; }
  ditto -x -k "$OL_TMP/Ollama-darwin.zip" "$OL_TMP/unpacked" \
    || { rm -rf "$OL_TMP"; fail "Couldn't unpack the Ollama download."; }
  [ -d "$OL_TMP/unpacked/Ollama.app" ] || { rm -rf "$OL_TMP"; fail "The Ollama download didn't contain Ollama.app."; }
  DEST=/Applications
  if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
  mv "$OL_TMP/unpacked/Ollama.app" "$DEST/Ollama.app"
  rm -rf "$OL_TMP"
  OLLAMA_APP="$DEST/Ollama.app"
  echo "Installed $OLLAMA_APP"
else
  echo "Running Ollama's official installer (it may ask for your password) ..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

# The ollama command: on PATH, or inside the app bundle on macOS.
ollama_bin() {
  if have ollama; then command -v ollama; return 0; fi
  if [ -n "$OLLAMA_APP" ] && [ -x "$OLLAMA_APP/Contents/Resources/ollama" ]; then
    echo "$OLLAMA_APP/Contents/Resources/ollama"; return 0
  fi
  return 1
}

ollama_up() { curl -s -o /dev/null --max-time 2 http://127.0.0.1:11434/api/tags; }
if ! ollama_up; then
  echo "Starting Ollama ..."
  if [ "$OS" = Darwin ] && [ -n "$OLLAMA_APP" ]; then
    open "$OLLAMA_APP"
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
  OLLAMA_BIN="$(ollama_bin || true)"
  if [ -n "$OLLAMA_BIN" ]; then
    "$OLLAMA_BIN" pull "$MODEL"
  else
    # No command-line tool to hand: ask the running Ollama to pull it (no progress bar).
    echo "Pulling through Ollama's API ..."
    curl -fsS -X POST http://127.0.0.1:11434/api/pull -d "{\"model\":\"$MODEL\",\"stream\":false}" | grep -q success \
      || fail "Couldn't pull $MODEL. Check the model name and your internet connection."
    echo "Pulled $MODEL."
  fi
else
  echo "Ollama has no models yet. Pull one before starting, e.g.: ollama pull llama3.2"
fi

echo
echo "All set. Start the gateway with:"
echo "  ./scripts/start.sh"
