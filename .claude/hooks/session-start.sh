#!/bin/bash
# SessionStart hook for Claude Code cloud sessions (registered in .claude/settings.json).
# Makes tools/check, tools/shoot and the python tests runnable in a fresh cloud container:
#   - Godot 4.5.1 stable Linux editor as `godot` on PATH (same release as .github/workflows/ios.yml)
#   - xvfb-run (tools/shoot, tools/art_preview and other rendered runs)
#   - numpy, Pillow and PyYAML (tools/artgen, tools/comfy, tools/art_*.py tests and scripts;
#     torch/diffusers are only for the GitHub art runners and are not installed here)
#   - one `godot --headless --path . --import` (via tools/gd) when .godot/ is missing
#
# Runs only when CLAUDE_CODE_REMOTE=true, so a local PC is never touched. Safe to re-run: when
# everything is present it only checks and takes about a second. It never fails the session
# start: problems are logged and the script still exits 0. A one-line status goes to stdout
# (the new session sees it); details go to the log file.
#
# Overrides (used to test this script without touching the real install):
#   HALO_GODOT_DIR  where the Godot binary is unpacked    (default /opt/godot-4.5.1)
#   HALO_BIN_DIR    where the `godot` link is created     (default /usr/local/bin)
#   HALO_PYTHON     python interpreter to check/install   (default python3)
#   HALO_HOOK_LOG   log file                               (default /tmp/halo-session-start.log)
set -u

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

GODOT_VERSION=4.5.1
GODOT_FILE="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${GODOT_FILE}.zip"
# From SHA512-SUMS.txt on the 4.5.1-stable release page.
GODOT_SHA512=5bccbed65a94b82c7c319fdb15719ee8113a6e503976cc54e16f1c61fe95f3d74e5e40b8449b5bb89ff7f424574c20af01a4f5ef08b389e4dc338b245185b0b9
GODOT_DIR="${HALO_GODOT_DIR:-/opt/godot-${GODOT_VERSION}}"
BIN_DIR="${HALO_BIN_DIR:-/usr/local/bin}"
PY="${HALO_PYTHON:-python3}"
LOG="${HALO_HOOK_LOG:-/tmp/halo-session-start.log}"
REPO="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
APT_PKGS="xvfb xauth libgl1 libgl1-mesa-dri libglx-mesa0 libfontconfig1 libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0"
PY_PKGS="numpy pillow pyyaml"
NOISE='ALSA|audio_driver_alsa|All audio drivers failed|audio_server.cpp|init_output_device|Condition "status < 0" is true|^\s*at: (init_output_device|initialize) '

STATUS=()
TMP_DL=""
trap '[ -n "$TMP_DL" ] && rm -rf "$TMP_DL"' EXIT

log() { echo "[session-start $(date +%H:%M:%S)] $*" >>"$LOG" 2>/dev/null; echo "session-start: $*" >&2; }

# True when the given binary is Godot $GODOT_VERSION stable.
godot_ok() {
  [ -n "${1:-}" ] && [ -x "$1" ] || return 1
  timeout 30 "$1" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"
}

download_godot() {
  TMP_DL=$(mktemp -d "${TMPDIR:-/tmp}/halo-godot-dl.XXXXXX") || { log "mktemp failed"; return 1; }
  log "downloading $GODOT_URL"
  if ! curl -fsSL --retry 3 --retry-delay 3 --connect-timeout 30 --max-time 300 \
      -o "$TMP_DL/godot.zip" "$GODOT_URL" >>"$LOG" 2>&1; then
    log "Godot download failed (see $LOG)"; return 1
  fi
  local sum
  sum=$(sha512sum "$TMP_DL/godot.zip" | cut -d' ' -f1)
  if [ "$sum" != "$GODOT_SHA512" ]; then
    log "Godot zip checksum mismatch (got ${sum:0:16}...), not installing"; return 1
  fi
  mkdir -p "$TMP_DL/x"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q -o "$TMP_DL/godot.zip" -d "$TMP_DL/x" >>"$LOG" 2>&1
  else
    python3 -I -m zipfile -e "$TMP_DL/godot.zip" "$TMP_DL/x" >>"$LOG" 2>&1
  fi
  [ -f "$TMP_DL/x/$GODOT_FILE" ] || { log "zip did not contain $GODOT_FILE"; return 1; }
  mkdir -p "$GODOT_DIR" || { log "cannot create $GODOT_DIR"; return 1; }
  chmod +x "$TMP_DL/x/$GODOT_FILE"
  mv -f "$TMP_DL/x/$GODOT_FILE" "$GODOT_DIR/$GODOT_FILE" || { log "cannot write $GODOT_DIR"; return 1; }
  rm -rf "$TMP_DL"; TMP_DL=""
  log "unpacked to $GODOT_DIR/$GODOT_FILE"
}

ensure_godot() {
  local cur bin="$GODOT_DIR/$GODOT_FILE"
  cur=$(command -v godot 2>/dev/null)
  if godot_ok "$cur"; then STATUS+=("godot $GODOT_VERSION ok"); return 0; fi
  [ -n "$cur" ] && log "godot on PATH ($cur) is not $GODOT_VERSION stable; installing $GODOT_VERSION"
  if ! godot_ok "$bin"; then
    download_godot || { STATUS+=("godot MISSING (install failed, see $LOG)"); return 1; }
    godot_ok "$bin" || { log "$bin does not run or is not $GODOT_VERSION"; STATUS+=("godot MISSING (see $LOG)"); return 1; }
  fi
  if ! { mkdir -p "$BIN_DIR" && ln -sfn "$bin" "$BIN_DIR/godot"; } >>"$LOG" 2>&1; then
    log "cannot link $BIN_DIR/godot"; STATUS+=("godot installed at $bin but not linked"); return 1
  fi
  hash -r
  if [ "$(command -v godot 2>/dev/null)" != "$BIN_DIR/godot" ]; then
    # BIN_DIR is not on PATH, or another godot comes first: put BIN_DIR first for this session.
    export PATH="$BIN_DIR:$PATH"
    if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
      echo "export PATH=\"$BIN_DIR:\$PATH\"" >>"$CLAUDE_ENV_FILE" 2>/dev/null || log "cannot write CLAUDE_ENV_FILE"
    fi
  fi
  STATUS+=("godot $GODOT_VERSION installed ($BIN_DIR/godot)")
}

ensure_xvfb() {
  if command -v xvfb-run >/dev/null 2>&1; then STATUS+=("xvfb-run ok"); return 0; fi
  if [ "$(id -u)" -ne 0 ] || ! command -v apt-get >/dev/null 2>&1; then
    log "xvfb-run missing and cannot be installed here (needs root and apt-get)"
    STATUS+=("xvfb-run MISSING (tools/shoot will not work)"); return 1
  fi
  log "installing xvfb and GL libraries with apt-get"
  export DEBIAN_FRONTEND=noninteractive
  timeout 180 apt-get update -qq >>"$LOG" 2>&1 || log "apt-get update failed; trying the install anyway"
  # shellcheck disable=SC2086
  timeout 300 apt-get install -y -qq --no-install-recommends $APT_PKGS >>"$LOG" 2>&1 || log "apt-get install failed (see $LOG)"
  if command -v xvfb-run >/dev/null 2>&1; then STATUS+=("xvfb-run installed")
  else STATUS+=("xvfb-run MISSING (see $LOG)"); return 1; fi
}

ensure_python() {
  if ! command -v "$PY" >/dev/null 2>&1; then
    log "$PY not found"; STATUS+=("python MISSING"); return 1
  fi
  if "$PY" -c "import numpy, PIL, yaml" >/dev/null 2>&1; then STATUS+=("python numpy/Pillow/PyYAML ok"); return 0; fi
  log "installing python packages: $PY_PKGS"
  # shellcheck disable=SC2086
  timeout 300 "$PY" -m pip install --quiet --disable-pip-version-check $PY_PKGS >>"$LOG" 2>&1 ||
    timeout 300 "$PY" -m pip install --quiet --disable-pip-version-check --break-system-packages $PY_PKGS >>"$LOG" 2>&1 ||
    log "pip install failed (see $LOG)"
  if "$PY" -c "import numpy, PIL, yaml" >/dev/null 2>&1; then STATUS+=("python numpy/Pillow/PyYAML installed")
  else STATUS+=("python packages MISSING (see $LOG)"); return 1; fi
}

ensure_import() {
  if [ -d "$REPO/.godot" ]; then STATUS+=(".godot present, import skipped"); return 0; fi
  if ! godot_ok "$(command -v godot 2>/dev/null)"; then STATUS+=("import skipped (no godot)"); return 1; fi
  log "first Godot import of $REPO (no .godot/ yet)"
  local out errs
  out=$(cd "$REPO" && timeout 600 tools/gd --headless --path . --import 2>&1 | grep -vE "$NOISE")
  echo "$out" | grep -vE '^\[ *[0-9]+% \]|\[ DONE \]|^.\[0m$' >>"$LOG" 2>/dev/null
  if [ ! -d "$REPO/.godot" ]; then STATUS+=("import FAILED (see $LOG)"); return 1; fi
  errs=$(echo "$out" | grep -cE "SCRIPT ERROR|Parse Error|ERROR:")
  if [ "$errs" -gt 0 ]; then STATUS+=("import done with $errs error line(s), see $LOG; tools/check re-imports")
  else STATUS+=("import done"); fi
}

log "start (repo $REPO)"
ensure_godot
ensure_xvfb
ensure_python
ensure_import
line=$(printf '%s; ' "${STATUS[@]}")
log "done: ${line%; }"
echo "Cloud session setup: ${line%; }. Log: $LOG"
exit 0
