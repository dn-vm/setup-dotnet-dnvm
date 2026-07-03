#!/usr/bin/env bash
# Installs a .NET SDK using dnvm and wires up the environment for subsequent
# GitHub Actions steps (PATH, DOTNET_ROOT) and step outputs. Linux/macOS
# implementation; the Windows equivalent is setup.ps1.
set -euo pipefail

DOTNET_VERSION="${INPUT_DOTNET_VERSION:-}"
GLOBAL_JSON_FILE="${INPUT_GLOBAL_JSON_FILE:-}"

if [ -z "$DOTNET_VERSION" ] && [ -z "$GLOBAL_JSON_FILE" ]; then
  echo "::error::One of 'dotnet-version' or 'global-json-file' is required." >&2
  exit 1
fi
if [ -n "$DOTNET_VERSION" ] && [ -n "$GLOBAL_JSON_FILE" ]; then
  echo "::error::'dotnet-version' and 'global-json-file' are mutually exclusive." >&2
  exit 1
fi

# --- Resolve DNVM_HOME ------------------------------------------------------
dnvm_home="${INPUT_INSTALL_DIR:-$HOME/.dnvm}"
mkdir -p "$dnvm_home"
export DNVM_HOME="$dnvm_home"
dotnet_root="$dnvm_home/dn"
dotnet_exe="$dotnet_root/dotnet"
dnvm_bin="$dnvm_home/dnvm"

# --- Bootstrap the dnvm binary via the hosted installer ---------------------
# https://dnvm.net/install.sh handles RID detection, TLS-hardened download and
# archive extraction for us. '-y --skip-tracking' installs only the dnvm binary
# (under DNVM_HOME) without prompting or installing any SDK. selfinstall errors
# if dnvm is already present, so skip the bootstrap on a cache hit.
if [ ! -x "$dnvm_bin" ]; then
  echo "Bootstrapping dnvm into ${dnvm_home}"
  curl --proto '=https' -sSf https://dnvm.net/install.sh | sh -s -- -y --skip-tracking
fi

# --- Install the requested SDK (idempotent: dnvm skips if already present) ---
if [ -n "$GLOBAL_JSON_FILE" ]; then
  if [ ! -f "$GLOBAL_JSON_FILE" ]; then
    echo "::error::global-json-file not found: $GLOBAL_JSON_FILE" >&2
    exit 1
  fi
  # dnvm restore reads a file named 'global.json' from the current directory
  # upward. Point the cwd at the file's directory; if the file has a different
  # name, stage a copy named global.json in a temp dir.
  gj_dir="$(cd "$(dirname "$GLOBAL_JSON_FILE")" && pwd)"
  if [ "$(basename "$GLOBAL_JSON_FILE")" != "global.json" ]; then
    gj_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dnvm-globaljson"
    mkdir -p "$gj_dir"
    cp "$GLOBAL_JSON_FILE" "$gj_dir/global.json"
  fi

  echo "Restoring SDK from ${GLOBAL_JSON_FILE} into ${dnvm_home}"
  ( cd "$gj_dir" && "$dnvm_bin" restore )
  # The resolved SDK (after roll-forward) is what the muxer selects for that
  # global.json, so query it from the restore directory.
  resolved_version="$( cd "$gj_dir" && DOTNET_ROOT="$dotnet_root" "$dotnet_exe" --version )"
else
  echo "Installing .NET SDK ${DOTNET_VERSION} into ${dnvm_home}"
  "$dnvm_bin" install "$DOTNET_VERSION"
  resolved_version="$DOTNET_VERSION"
fi

# --- Wire up the environment for subsequent steps ---------------------------
if [ -n "${GITHUB_PATH:-}" ]; then echo "$dotnet_root" >> "$GITHUB_PATH"; fi
if [ -n "${GITHUB_ENV:-}" ]; then echo "DOTNET_ROOT=$dotnet_root" >> "$GITHUB_ENV"; fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "dotnet-version=$resolved_version" >> "$GITHUB_OUTPUT"
  echo "dotnet-root=$dotnet_root" >> "$GITHUB_OUTPUT"
fi

echo "Installed .NET SDK ${resolved_version}"
"$dotnet_exe" --version
