#!/usr/bin/env bash
# Start the Shazam backend daemon
# Called by launchd or `shazam daemon start`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SHAZAM_DAEMON=true
export SHAZAM_PORT="${SHAZAM_PORT:-4040}"
export MIX_ENV=prod

# Ensure logs directory
mkdir -p "$HOME/.shazam/logs"

cd "$SCRIPT_DIR"

# Source elixir if installed via asdf/mise
if [ -f "$HOME/.asdf/asdf.sh" ]; then
  source "$HOME/.asdf/asdf.sh"
fi

exec elixir -S mix run --no-halt
