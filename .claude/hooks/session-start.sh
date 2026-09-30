#!/bin/bash
# Installs the Godot engine in Claude Code on the web sessions, so the runners
# (run_tests.py, run_scratch.py, capture.py) find `godot` on PATH. Keep
# GODOT_VERSION in step with the engine AGENTS.md names.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.7.2"
INSTALL_DIR="/opt/godot/${GODOT_VERSION}"
BINARY="${INSTALL_DIR}/godot"

if [ ! -x "${BINARY}" ]; then
  mkdir -p "${INSTALL_DIR}"
  archive="$(mktemp --suffix=.zip)"
  curl -sSfL --retry 4 -o "${archive}" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  unzip -q -o "${archive}" -d "${INSTALL_DIR}"
  rm -f "${archive}"
  mv "${INSTALL_DIR}/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "${BINARY}"
  chmod +x "${BINARY}"
fi

ln -sf "${BINARY}" /usr/local/bin/godot
