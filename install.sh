#!/bin/bash

set -eu

KOSMO_GITHUB_REPO="${KOSMO_GITHUB_REPO:-elcritch/merenda}"
KOSMO_VERSION="${KOSMO_VERSION:-}"
KOSMO_RELEASE_BASE_URL="${KOSMO_RELEASE_BASE_URL:-}"
KOSMO_TMP_ROOT="${KOSMO_TMP_ROOT:-${TMPDIR:-/tmp}}"
KOSMO_STAGED_PATH=""

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "install.sh: missing required command: $1" >&2
    exit 1
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

cleanup() {
  if [ -n "$KOSMO_STAGED_PATH" ] && [ -e "$KOSMO_STAGED_PATH" ]; then
    rm -rf "$KOSMO_STAGED_PATH"
  fi
  if [ -n "${KOSMO_TMP_DIR:-}" ] && [ -d "$KOSMO_TMP_DIR" ]; then
    rm -rf "$KOSMO_TMP_DIR"
  fi
}

detect_release_archive() {
  local os
  local arch

  os="$(uname -s 2>/dev/null || true)"
  arch="$(uname -m 2>/dev/null || true)"

  case "$os" in
    Linux)
      case "$arch" in
        x86_64 | amd64) echo "linux:kosmo-linux-amd64.tar.gz" ;;
        *) return 1 ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        arm64 | aarch64) echo "macos:kosmo-macos-arm64.zip" ;;
        *) return 1 ;;
      esac
      ;;
    MINGW* | MSYS* | CYGWIN*)
      case "$arch" in
        x86_64 | amd64) echo "windows:kosmo-windows-amd64.zip" ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

calculate_sha256() {
  if has_cmd sha256sum; then
    sha256sum "$1" | awk '{ print $1 }'
  elif has_cmd shasum; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    echo "install.sh: sha256sum or shasum is required to verify the download" >&2
    exit 1
  fi
}

install_command() {
  local source_bin="$1"
  local target_name="$2"
  local installed_bin="$KOSMO_INSTALL_DIR/$target_name"

  if [ -d "$installed_bin" ] && [ ! -L "$installed_bin" ]; then
    echo "install.sh: cannot replace directory: $installed_bin" >&2
    exit 1
  fi

  mkdir -p "$KOSMO_INSTALL_DIR"
  KOSMO_STAGED_PATH="$KOSMO_INSTALL_DIR/.$target_name.install.$$"
  cp "$source_bin" "$KOSMO_STAGED_PATH"
  chmod +x "$KOSMO_STAGED_PATH"
  mv -f "$KOSMO_STAGED_PATH" "$installed_bin"
  KOSMO_STAGED_PATH=""

  echo "install.sh: installed Kosmo to $installed_bin" >&2
  case ":$PATH:" in
    *":$KOSMO_INSTALL_DIR:"*) ;;
    *) echo "install.sh: add $KOSMO_INSTALL_DIR to PATH to run kosmo directly" >&2 ;;
  esac
}

install_notices() {
  local extract_dir="$1"

  if [ ! -f "$extract_dir/FONT-LICENSES.md" ]; then
    return
  fi

  mkdir -p "$KOSMO_DOC_DIR"
  cp "$extract_dir/FONT-LICENSES.md" "$KOSMO_DOC_DIR/FONT-LICENSES.md"
  if [ -d "$extract_dir/font-licenses" ]; then
    rm -rf "$KOSMO_DOC_DIR/font-licenses"
    cp -R "$extract_dir/font-licenses" "$KOSMO_DOC_DIR/font-licenses"
  fi
  echo "install.sh: installed bundled-font notices to $KOSMO_DOC_DIR" >&2
}

install_macos_app() {
  local source_app="$1"
  local installed_app="$KOSMO_INSTALL_DIR/Kosmo.app"
  local installed_command="$KOSMO_BIN_DIR/kosmo"

  if [ -d "$installed_command" ] && [ ! -L "$installed_command" ]; then
    echo "install.sh: cannot replace directory: $installed_command" >&2
    exit 1
  fi

  mkdir -p "$KOSMO_INSTALL_DIR" "$KOSMO_BIN_DIR"
  KOSMO_STAGED_PATH="$KOSMO_INSTALL_DIR/.Kosmo.app.install.$$"
  ditto "$source_app" "$KOSMO_STAGED_PATH"
  rm -rf "$installed_app"
  mv "$KOSMO_STAGED_PATH" "$installed_app"
  KOSMO_STAGED_PATH=""

  rm -f "$installed_command"
  ln -s "$installed_app/Contents/MacOS/kosmo" "$installed_command"

  echo "install.sh: installed Kosmo.app to $installed_app" >&2
  echo "install.sh: installed Kosmo command link to $installed_command" >&2
  case ":$PATH:" in
    *":$KOSMO_BIN_DIR:"*) ;;
    *) echo "install.sh: add $KOSMO_BIN_DIR to PATH to run kosmo directly" >&2 ;;
  esac
}

need_cmd uname
need_cmd curl
need_cmd mktemp
need_cmd mkdir
need_cmd awk
need_cmd cp
need_cmd chmod
need_cmd mv
need_cmd rm
need_cmd tr

platform_archive="$(detect_release_archive)" || {
  echo "install.sh: no Kosmo release is available for $(uname -s)/$(uname -m)" >&2
  exit 1
}
platform="${platform_archive%%:*}"
archive="${platform_archive#*:}"

case "$platform" in
  macos)
    KOSMO_INSTALL_DIR="${KOSMO_INSTALL_DIR:-$HOME/Applications}"
    KOSMO_BIN_DIR="${KOSMO_BIN_DIR:-$HOME/.local/bin}"
    need_cmd ditto
    need_cmd ln
    ;;
  *)
    KOSMO_INSTALL_DIR="${KOSMO_INSTALL_DIR:-$HOME/.local/bin}"
    KOSMO_DOC_DIR="${KOSMO_DOC_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/doc/kosmo}"
    ;;
esac

if [ -z "$KOSMO_RELEASE_BASE_URL" ]; then
  if [ -n "$KOSMO_VERSION" ]; then
    KOSMO_RELEASE_BASE_URL="https://github.com/$KOSMO_GITHUB_REPO/releases/download/$KOSMO_VERSION"
  else
    KOSMO_RELEASE_BASE_URL="https://github.com/$KOSMO_GITHUB_REPO/releases/latest/download"
  fi
fi

KOSMO_TMP_DIR="$(mktemp -d "$KOSMO_TMP_ROOT/kosmo-install.XXXXXX")"
trap cleanup EXIT INT TERM

archive_path="$KOSMO_TMP_DIR/$archive"
checksums_path="$KOSMO_TMP_DIR/SHA256SUMS.txt"
extract_dir="$KOSMO_TMP_DIR/release"

echo "install.sh: downloading $archive" >&2
curl -fL --retry 3 --retry-delay 2 \
  "$KOSMO_RELEASE_BASE_URL/$archive" \
  -o "$archive_path"
curl -fL --retry 3 --retry-delay 2 \
  "$KOSMO_RELEASE_BASE_URL/SHA256SUMS.txt" \
  -o "$checksums_path"

expected_checksum="$(
  tr -d '\r' < "$checksums_path" |
    awk -v archive="$archive" '$2 == archive || $2 == "*" archive { print $1; exit }'
)"
if [ -z "$expected_checksum" ]; then
  echo "install.sh: SHA256SUMS.txt has no entry for $archive" >&2
  exit 1
fi
actual_checksum="$(calculate_sha256 "$archive_path")"
if [ "$actual_checksum" != "$expected_checksum" ]; then
  echo "install.sh: checksum verification failed for $archive" >&2
  exit 1
fi
echo "install.sh: verified SHA-256 checksum" >&2

mkdir -p "$extract_dir"
case "$platform" in
  linux)
    need_cmd tar
    tar -xzf "$archive_path" -C "$extract_dir"
    if [ ! -f "$extract_dir/kosmo" ]; then
      echo "install.sh: release archive did not contain kosmo" >&2
      exit 1
    fi
    install_command "$extract_dir/kosmo" kosmo
    install_notices "$extract_dir"
    ;;
  macos)
    ditto -x -k "$archive_path" "$extract_dir"
    if [ ! -f "$extract_dir/Kosmo.app/Contents/MacOS/kosmo" ]; then
      echo "install.sh: release archive did not contain Kosmo.app" >&2
      exit 1
    fi
    install_macos_app "$extract_dir/Kosmo.app"
    ;;
  windows)
    need_cmd unzip
    unzip -q "$archive_path" -d "$extract_dir"
    if [ ! -f "$extract_dir/kosmo.exe" ]; then
      echo "install.sh: release archive did not contain kosmo.exe" >&2
      exit 1
    fi
    install_command "$extract_dir/kosmo.exe" kosmo.exe
    install_notices "$extract_dir"
    ;;
esac
