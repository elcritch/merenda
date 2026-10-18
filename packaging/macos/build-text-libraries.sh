#!/bin/bash
set -euo pipefail

prefix="${1:?usage: build-text-libraries.sh /absolute/install/prefix}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/kosmo-text.XXXXXX")"
cleanup() {
  local build_status=$?
  if [[ "$build_status" -ne 0 ]]; then
    for log in "$work_dir/"*-build/meson-logs/meson-log.txt; do
      if [[ -f "$log" ]]; then
        tail -80 "$log" >&2
      fi
    done
  fi
  rm -rf "$work_dir"
  exit "$build_status"
}
trap cleanup EXIT

# Homebrew verifies source checksums. Build minimal libraries rather than using
# bottles whose deployment targets can exceed Kosmo's macOS 13 minimum.
export MACOSX_DEPLOYMENT_TARGET=13.0
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export HOMEBREW_NO_AUTO_UPDATE=1
brew fetch --build-from-source harfbuzz fribidi
for formula in harfbuzz fribidi; do
  mkdir -p "$work_dir/$formula"
  tar -xf "$(brew --cache --build-from-source "$formula")" \
    -C "$work_dir/$formula" --strip-components 1
done

meson setup "$work_dir/harfbuzz-build" "$work_dir/harfbuzz" \
  --prefix="$prefix" --libdir=lib --buildtype=release --default-library=shared \
  --wrap-mode=nofallback --auto-features=disabled \
  -Dtests=disabled -Dutilities=disabled -Dsubset=disabled \
  -Draster=disabled -Dvector=disabled -Dgpu=disabled
meson compile -C "$work_dir/harfbuzz-build"
meson install -C "$work_dir/harfbuzz-build"

meson setup "$work_dir/fribidi-build" "$work_dir/fribidi" \
  --prefix="$prefix" --libdir=lib --buildtype=release --default-library=shared \
  --wrap-mode=nofallback -Ddocs=false -Dbin=false -Dtests=false
meson compile -C "$work_dir/fribidi-build"
meson install -C "$work_dir/fribidi-build"

for library in "$prefix/lib/libharfbuzz.dylib" "$prefix/lib/libfribidi.dylib"; do
  otool -l "$library" | awk '
    $1 == "cmd" { legacy = ($2 == "LC_VERSION_MIN_MACOSX") }
    ($1 == "minos" || (legacy && $1 == "version")) && $2 + 0 > 13.0 {
      print "Text library exceeds the macOS 13 deployment target: " $2 > "/dev/stderr"
      exit 1
    }'
done

mkdir -p "$prefix/share/licenses"
cp "$work_dir/harfbuzz/COPYING" "$prefix/share/licenses/harfbuzz.txt"
cp "$work_dir/fribidi/COPYING" "$prefix/share/licenses/fribidi.txt"
