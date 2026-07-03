#!/usr/bin/env bash
# Installs a specific .NET SDK version using dnvm and wires up the environment
# for subsequent GitHub Actions steps (PATH, DOTNET_ROOT) and step outputs.
set -euo pipefail

DOTNET_VERSION="${INPUT_DOTNET_VERSION:?dotnet-version input is required}"
DNVM_VERSION="${INPUT_DNVM_VERSION:-1.1.2}"

# --- Resolve the dnvm runtime identifier (RID) for this runner ---------------
os="${RUNNER_OS:-$(uname -s)}"
arch="${RUNNER_ARCH:-$(uname -m)}"

case "$os" in
  Linux)              rid_os=linux; ext=tar.gz; exe=dnvm ;;
  macOS|Darwin)       rid_os=osx;   ext=tar.gz; exe=dnvm ;;
  Windows*|MINGW*|MSYS*|CYGWIN*) rid_os=win; ext=zip; exe=dnvm.exe ;;
  *) echo "::error::Unsupported OS: $os" >&2; exit 1 ;;
esac

case "$arch" in
  X64|x64|x86_64|amd64)   rid_arch=x64 ;;
  ARM64|arm64|aarch64)    rid_arch=arm64 ;;
  *) echo "::error::Unsupported architecture: $arch" >&2; exit 1 ;;
esac

if [ "$rid_os" = "win" ] && [ "$rid_arch" != "x64" ]; then
  echo "::error::dnvm only publishes a win-x64 build; '$rid_os-$rid_arch' is unsupported." >&2
  exit 1
fi

rid="$rid_os-$rid_arch"
url="https://github.com/dn-vm/dnvm/releases/download/v${DNVM_VERSION}/dnvm-${DNVM_VERSION}-${rid}.${ext}"

# --- Download and extract the dnvm binary -----------------------------------
# Use a POSIX-style base dir for bash-side file ops. On Windows, RUNNER_TEMP is
# a Windows path (e.g. D:\a\_temp); bsdtar would treat the "D:" as a remote host,
# so convert it to a POSIX path first.
base_tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
[ "$rid_os" = "win" ] && base_tmp="$(cygpath -u "$base_tmp")"
tooldir="$base_tmp/dnvm-bin"
mkdir -p "$tooldir"
archive="$tooldir/dnvm.${ext}"

echo "Downloading dnvm ${DNVM_VERSION} for ${rid}"
curl -fsSL -o "$archive" "$url"
# Git Bash's `tar` is GNU tar (no zip support), so extract the Windows .zip with
# PowerShell's Expand-Archive; use tar for the Unix .tar.gz.
if [ "$ext" = "zip" ]; then
  powershell -NoProfile -NonInteractive -Command \
    "Expand-Archive -LiteralPath '$(cygpath -w "$archive")' -DestinationPath '$(cygpath -w "$tooldir")' -Force"
else
  tar -xzf "$archive" -C "$tooldir"
fi
dnvm_bin="$tooldir/$exe"
[ "$rid_os" = "win" ] || chmod +x "$dnvm_bin"

# --- Resolve DNVM_HOME ------------------------------------------------------
home_input="${INPUT_INSTALL_DIR:-}"
home_posix="${home_input:-$HOME/.dnvm}"
[ "$rid_os" = "win" ] && home_posix="$(cygpath -u "$home_posix")"
mkdir -p "$home_posix"

if [ "$rid_os" = "win" ]; then
  # dnvm and the GitHub env files need native Windows paths; local bash calls
  # use the POSIX form.
  dnvm_home="$(cygpath -w "$home_posix")"
  dotnet_root="${dnvm_home}\\dn"
  dotnet_exe="$home_posix/dn/dotnet.exe"
else
  dnvm_home="$home_posix"
  dotnet_root="$home_posix/dn"
  dotnet_exe="$dotnet_root/dotnet"
fi

# --- Install the requested SDK (idempotent: dnvm skips if already present) ---
echo "Installing .NET SDK ${DOTNET_VERSION} into ${dnvm_home}"
DNVM_HOME="$dnvm_home" "$dnvm_bin" install "$DOTNET_VERSION"

# --- Wire up the environment for subsequent steps ---------------------------
if [ -n "${GITHUB_PATH:-}" ]; then echo "$dotnet_root" >> "$GITHUB_PATH"; fi
if [ -n "${GITHUB_ENV:-}" ]; then echo "DOTNET_ROOT=$dotnet_root" >> "$GITHUB_ENV"; fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "dotnet-version=$DOTNET_VERSION" >> "$GITHUB_OUTPUT"
  echo "dotnet-root=$dotnet_root" >> "$GITHUB_OUTPUT"
fi

echo "Installed .NET SDK ${DOTNET_VERSION}"
"$dotnet_exe" --version
