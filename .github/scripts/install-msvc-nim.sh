#!/usr/bin/env bash

set -euo pipefail

# Start with the complete official distribution, verify both pinned fixes, then
# compile the corrected compiler once. No Git clone or csources build is needed.
nimMsvcRevision=705392dc03a3f8233f5f0f048acaa9b5267576f6
nimMsvcAtomicsChecksum=2d9c6b381ad09b09b64d29f2af5a6da693c7835d574075e238a8d8c4370ef05a
nimMsvcCompilerChecksum=22e3011e65906288373fc991d2abc9a06e6ebd348c7682f162a14f21b047451b
projectRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$projectRoot"
nimMsvcDir="$projectRoot/deps/nim-msvc-2.2.10-705392dc"
atomicsPath=lib/pure/concurrency/atomics.nim
compilerPath=compiler/ccgliterals.nim
stageDir=
probeDir=
nimMsvcCandidate="$nimMsvcDir"

cleanup() {
  if [[ -n "$stageDir" ]]; then rm -rf "$stageDir"; fi
  if [[ -n "$probeDir" ]]; then rm -rf "$probeDir"; fi
}
trap cleanup EXIT

verifyFile() {
  [[ -f "$1" ]] && [[ "$(sha256sum "$1" | cut -d ' ' -f 1)" == "$2" ]]
}

fetchPatch() {
  local relativePath="$1" expectedChecksum="$2"
  curl --fail --location --retry 3 \
    "https://raw.githubusercontent.com/elcritch/Nim/$nimMsvcRevision/$relativePath" \
    --output "$stageDir/$relativePath"
  if ! verifyFile "$stageDir/$relativePath" "$expectedChecksum"; then
    echo "The pinned $relativePath checksum does not match." >&2
    exit 1
  fi
}

if [[ ! -e "$nimMsvcDir" ]]; then
  atlas env 2.2.10 --binary
  stageDir="$(mktemp -d "$projectRoot/deps/.nim-msvc-XXXXXX")"
  cp -R "$projectRoot/deps/nim-2.2.10/." "$stageDir/"
  fetchPatch "$atomicsPath" "$nimMsvcAtomicsChecksum"
  fetchPatch "$compilerPath" "$nimMsvcCompilerChecksum"
  stageWindows="$(cygpath -m "$stageDir")"
  # Keep compiler/nim.cfg (booting/nimcore), but skip Merenda's parent config.
  "$projectRoot/deps/nim-2.2.10/bin/nim.exe" c --cc:vcc -d:release --mm:orc \
    --skipUserCfg:on --skipParentCfg:on --lib:"$stageWindows/lib" \
    --out:"$stageWindows/bin/nim.exe" "$stageDir/compiler/nim.nim"
  # Atlas activation scripts contain the original installation's absolute path.
  # Use the private compiler path printed below instead.
  rm -f "$stageDir/activate.bat" "$stageDir/activate.ps1" "$stageDir/activate.sh"
  nimMsvcCandidate="$stageDir"
fi

if [[ ! -f "$nimMsvcCandidate/bin/nim.exe" ]] ||
    ! verifyFile "$nimMsvcCandidate/$atomicsPath" "$nimMsvcAtomicsChecksum" ||
    ! verifyFile "$nimMsvcCandidate/$compilerPath" "$nimMsvcCompilerChecksum"; then
  echo "Incomplete MSVC Nim environment: remove $nimMsvcDir and retry." >&2
  exit 1
fi

# Use the compiler's default library lookup, including on cached installations.
probeDir="$(mktemp -d "$projectRoot/deps/.msvc-atomics-probe-XXXXXX")"
probeFile="$probeDir/msvc_atomics_probe.nim"
cat > "$probeFile" <<'NIM'
import std/atomics
static:
  doAssert declared(nimHasCorrectMsvcAtomics)
const binary = block:
  var data = newString(20_000)
  for i in 0 ..< data.len:
    data[i] = char(i mod 256)
  data
var value = binary
let original = value
for i, c in value:
  doAssert c == char(i mod 256)
value[0] = 'x'
doAssert original[0] == '\0'
NIM
"$nimMsvcCandidate/bin/nim.exe" c -r --cc:vcc --mm:arc \
  --skipUserCfg:on --skipParentCfg:on --skipProjCfg:on \
  --out:"$(cygpath -m "$probeDir")/msvc_probe.exe" "$probeFile"

if [[ -n "$stageDir" ]]; then
  mv "$stageDir" "$nimMsvcDir"
  stageDir=
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  cygpath -w "$nimMsvcDir/bin" >> "$GITHUB_PATH"
fi

nimMsvcCompilerWindows="$(cygpath -w "$nimMsvcDir/bin/nim.exe")"
echo "Patched MSVC compiler: $nimMsvcCompilerWindows"
