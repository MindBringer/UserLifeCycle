#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -gt 0 ]]; then
  if [[ "${ULC_COMPANION_NO_BROWSER:-0}" == "1" ]]; then
    exec python3 tools/companion/server.py --port "$1" --no-browser
  fi
  exec python3 tools/companion/server.py --port "$1"
fi

if [[ "${ULC_COMPANION_NO_BROWSER:-0}" == "1" ]]; then
  exec python3 tools/companion/server.py --no-browser
fi

exec python3 tools/companion/server.py
