#!/usr/bin/env bash
# Installs a .NET SDK using dnvm and wires up the environment for subsequent
# GitHub Actions steps (PATH, DOTNET_ROOT) and step outputs. Linux/macOS
# implementation; the Windows equivalent is setup.ps1.
set -euo pipefail

DOTNET_VERSION="${INPUT_DOTNET_VERSION:-}"
GLOBAL_JSON_FILE="${INPUT_GLOBAL_JSON_FILE:-}"
DNVM_VERSION="${INPUT_DNVM_VERSION:-1.1.2}"

if [ -z "$DOTNET_VERSION" ] && [ -z "$GLOBAL_JSON_FILE" ]; then
  echo "::error::One of 'dotnet-version' or 'global-json-file' is required." >&2
  exit 1
fi
if [ -n "$DOTNET_VERSION" ] && [ -n "$GLOBAL_JSON_FILE" ]; then
  echo "::error::'dotnet-version' and 'global-json-file' are mutually exclusive." >&2
  exit 1
fi

# --- Resolve the dnvm runtime identifier (RID) for this runner ---------------
os="${RUNNER_OS:-$(uname -s)}"
arch="${RUNNER_ARCH:-$(uname -m)}"

case "$os" in
  Linux)        rid_os=linux ;;
  macOS|Darwin) rid_os=osx ;;
  *) echo "::error::Unsupported OS: $os" >&2; exit 1 ;;
esac

case "$arch" in
  X64|x64|x86_64|amd64) rid_arch=x64 ;;
  ARM64|arm64|aarch64)  rid_arch=arm64 ;;
  *) echo "::error::Unsupported architecture: $arch" >&2; exit 1 ;;
esac

rid="$rid_os-$rid_arch"
url="https://github.com/dn-vm/dnvm/releases/download/v${DNVM_VERSION}/dnvm-${DNVM_VERSION}-${rid}.tar.gz"

# --- Download and extract the dnvm binary -----------------------------------
tooldir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dnvm-bin"
mkdir -p "$tooldir"
archive="$tooldir/dnvm.tar.gz"

echo "Downloading dnvm ${DNVM_VERSION} for ${rid}"
curl -fsSL -o "$archive" "$url"
tar -xzf "$archive" -C "$tooldir"
dnvm_bin="$tooldir/dnvm"
chmod +x "$dnvm_bin"

# --- Resolve DNVM_HOME ------------------------------------------------------
dnvm_home="${INPUT_INSTALL_DIR:-$HOME/.dnvm}"
mkdir -p "$dnvm_home"
dotnet_root="$dnvm_home/dn"
dotnet_exe="$dotnet_root/dotnet"

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
  ( cd "$gj_dir" && DNVM_HOME="$dnvm_home" "$dnvm_bin" restore )
  # The resolved SDK (after roll-forward) is what the muxer selects for that
  # global.json, so query it from the restore directory.
  resolved_version="$( cd "$gj_dir" && DOTNET_ROOT="$dotnet_root" "$dotnet_exe" --version )"
else
  echo "Installing .NET SDK ${DOTNET_VERSION} into ${dnvm_home}"
  DNVM_HOME="$dnvm_home" "$dnvm_bin" install "$DOTNET_VERSION"
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
