#!/bin/bash

set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'install-local.sh: a macOS host is required' >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

for required_command in atlas nim git awk sips iconutil xcrun nm plutil codesign ditto meson ninja cmake; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "install-local.sh: missing required command: $required_command" >&2
    exit 1
  fi
done

version="$(awk -F '"' '/^version[[:space:]]*=/ { print $2; exit }' merenda.nimble)"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "install-local.sh: invalid macOS bundle version: $version" >&2
  exit 1
fi
revision="$(git rev-parse --short=12 HEAD)"
build_number="$(date -u '+%Y%m%d%H%M%S')"
install_dir="${KOSMO_INSTALL_DIR:-$HOME/Applications}"
bin_dir="${KOSMO_BIN_DIR:-$HOME/.local/bin}"
installed_app="$install_dir/Kosmo.app"
installed_command="$bin_dir/kosmo"

if [[ -d "$installed_command" && ! -L "$installed_command" ]]; then
  echo "install-local.sh: cannot replace directory: $installed_command" >&2
  exit 1
fi

build_root="$(mktemp -d "${TMPDIR:-/tmp}/kosmo-build.XXXXXX")"
app_path="$build_root/Kosmo.app"
iconset_path="$build_root/Kosmo.iconset"
staged_app=""
staged_command=""
backup_app=""
restore_install=0

cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$restore_install" -eq 1 ]]; then
    rm -rf "$installed_app"
    if [[ -n "$backup_app" ]]; then
      mv "$backup_app" "$installed_app"
    fi
  fi
  if [[ -n "$staged_app" ]]; then
    rm -rf "$staged_app"
  fi
  if [[ -n "$staged_command" ]]; then
    rm -f "$staged_command"
  fi
  rm -rf "$build_root"
  exit "$status"
}
trap cleanup EXIT

echo "install-local.sh: resolving Kosmo dependencies with Atlas"
atlas install -tuk --features:kosmo

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$iconset_path"
cp packaging/macos/Info.plist "$app_path/Contents/Info.plist"
cp data/FONT-LICENSES.md "$app_path/Contents/Resources/FONT-LICENSES.md"
cp -R data/font-licenses "$app_path/Contents/Resources/font-licenses"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
  "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" \
  "$app_path/Contents/Info.plist"

for size in 16 32 128 256 512; do
  retina_size=$((size * 2))
  sips -z "$size" "$size" data/kosmo-icon.png \
    --out "$iconset_path/icon_${size}x${size}.png" >/dev/null
  sips -z "$retina_size" "$retina_size" data/kosmo-icon.png \
    --out "$iconset_path/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_path" -o "$app_path/Contents/Resources/Kosmo.icns"

echo "install-local.sh: building Kosmo.app $version ($revision)"
export MACOSX_DEPLOYMENT_TARGET=13.0
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
KOSMO_TEXT_LICENSE_DIR="$app_path/Contents/Resources/text-library-licenses" \
  nim e packaging/macos/staticTextLicenses.nims
nim c \
  --passC:-mmacosx-version-min=13.0 \
  --passL:-mmacosx-version-min=13.0 \
  --opt:size \
  --debugger:native \
  --lineTrace:off \
  --stackTrace:off \
  -d:nimStackTraceOverride \
  -d:moe.embedded \
  -d:harfbuzzyStatic \
  -d:KosmoVersion="$version" \
  -d:KosmoGitHashOverride="$revision" \
  --out:"$app_path/Contents/MacOS/kosmo" \
  src/merenda/kosmo/kosmo.nim
xcrun dsymutil "$app_path/Contents/MacOS/kosmo" \
  -o "$app_path/Contents/MacOS/kosmo.dSYM"
binary_uuid="$(xcrun dwarfdump --uuid "$app_path/Contents/MacOS/kosmo" | awk '{ print $2 }')"
dsym_uuid="$(xcrun dwarfdump --uuid "$app_path/Contents/MacOS/kosmo.dSYM" | awk '{ print $2 }')"
if [[ -z "$binary_uuid" || "$binary_uuid" != "$dsym_uuid" ]]; then
  echo 'install-local.sh: Kosmo binary and dSYM UUIDs do not match' >&2
  exit 1
fi
nm "$app_path/Contents/MacOS/kosmo" |
  awk '$NF == "_backtrace_create_state" { found = 1 } END { exit !found }'
"$app_path/Contents/MacOS/kosmo" --help >/dev/null
plutil -lint "$app_path/Contents/Info.plist"
codesign --force --options runtime --sign - \
  --entitlements packaging/macos/debug.entitlements "$app_path"
codesign --verify --deep --strict "$app_path"
"$app_path/Contents/MacOS/kosmo" --help >/dev/null

mkdir -p "$install_dir" "$bin_dir"
staged_app="$install_dir/.Kosmo.app.install.$$"
staged_command="$bin_dir/.kosmo.install.$$"
ditto "$app_path" "$staged_app"
codesign --verify --deep --strict "$staged_app"
"$staged_app/Contents/MacOS/kosmo" --help >/dev/null

if [[ -e "$installed_app" || -L "$installed_app" ]]; then
  backup_app="$install_dir/.Kosmo.app.backup.$$"
  mv "$installed_app" "$backup_app"
fi
restore_install=1
mv "$staged_app" "$installed_app"
staged_app=""
ln -s "$installed_app/Contents/MacOS/kosmo" "$staged_command"
"$staged_command" --help >/dev/null
mv -f "$staged_command" "$installed_command"
staged_command=""
restore_install=0

if [[ -n "$backup_app" ]]; then
  rm -rf "$backup_app"
fi
echo "install-local.sh: installed $installed_app"
echo "install-local.sh: linked $installed_command"
