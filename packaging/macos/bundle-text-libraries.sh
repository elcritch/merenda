#!/bin/bash
set -euo pipefail

app_path="${1:?usage: bundle-text-libraries.sh /path/to/Kosmo.app /text/library/prefix}"
text_prefix="${2:?text library prefix required}"
library_dir="$app_path/Contents/Frameworks"
mkdir -p "$library_dir"

bundle_library() {
  local source="$1" name destination dependency
  name="$(basename "$source")"
  destination="$library_dir/$name"
  if [[ -f "$destination" ]]; then
    return
  fi
  cp -L "$source" "$destination"
  chmod u+w "$destination"
  install_name_tool -id "@loader_path/$name" "$destination"
  while IFS= read -r dependency; do
    case "$dependency" in
      /usr/lib/*|/System/Library/*) continue ;;
    esac
    # The first entry is the source library's own install name.
    if [[ "$dependency" -ef "$source" ]]; then
      continue
    fi
    if [[ ! -f "$dependency" ]]; then
      echo "Cannot bundle text-library dependency: $dependency" >&2
      exit 1
    fi
    bundle_library "$dependency"
    install_name_tool -change "$dependency" \
      "@loader_path/$(basename "$dependency")" "$destination"
  done < <(otool -L "$source" | sed -E '1d; s/^[[:space:]]+//; s/ \(compatibility version.*$//')
  if [[ -n "${KOSMO_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
      --sign "$KOSMO_SIGNING_IDENTITY" "$destination"
  else
    codesign --force --sign - "$destination"
  fi
}

bundle_library "$text_prefix/lib/libharfbuzz.dylib"
bundle_library "$text_prefix/lib/libfribidi.dylib"
mkdir -p "$app_path/Contents/Resources/text-library-licenses"
cp "$text_prefix/share/licenses/"*.txt "$app_path/Contents/Resources/text-library-licenses/"
