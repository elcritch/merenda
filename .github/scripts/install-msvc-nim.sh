#!/usr/bin/env bash

set -euo pipefail

# The compiler is unchanged: install the official binary and overlay the one
# corrected standard-library module in a private copy of the distribution.
nimMsvcRevision=31511ba12d9d9333fdf886b4ae2fe78b5b398645
nimMsvcChecksum=2d9c6b381ad09b09b64d29f2af5a6da693c7835d574075e238a8d8c4370ef05a
projectRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$projectRoot"
nimMsvcDir="$projectRoot/deps/nim-msvc-2.2.10-31511ba1-bin"
atomicsPath=lib/pure/concurrency/atomics.nim
stageDir=
probeDir=
nimMsvcCandidate="$nimMsvcDir"

cleanup() {
  if [[ -n "$stageDir" ]]; then rm -rf "$stageDir"; fi
  if [[ -n "$probeDir" ]]; then rm -rf "$probeDir"; fi
}
trap cleanup EXIT

verifyAtomics() {
  [[ -f "$1" ]] && [[ "$(sha256sum "$1" | cut -d ' ' -f 1)" == "$nimMsvcChecksum" ]]
}

if [[ ! -e "$nimMsvcDir" ]]; then
  atlas env 2.2.10 --binary
  stageDir="$(mktemp -d "$projectRoot/deps/.nim-msvc-XXXXXX")"
  cp -R "$projectRoot/deps/nim-2.2.10/." "$stageDir/"
  curl --fail --location --retry 3 \
    "https://raw.githubusercontent.com/elcritch/Nim/$nimMsvcRevision/$atomicsPath" \
    --output "$stageDir/$atomicsPath"
  if ! verifyAtomics "$stageDir/$atomicsPath"; then
    echo 'The MSVC atomics module checksum does not match.' >&2
    exit 1
  fi
  # Atlas activation scripts contain the original installation's absolute path.
  # Use the private compiler path printed below instead.
  rm -f "$stageDir/activate.bat" "$stageDir/activate.ps1" "$stageDir/activate.sh"
  nimMsvcCandidate="$stageDir"
fi

if [[ ! -f "$nimMsvcCandidate/bin/nim.exe" ]] || ! verifyAtomics "$nimMsvcCandidate/$atomicsPath"; then
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
NIM
"$nimMsvcCandidate/bin/nim.exe" check --cc:vcc --os:windows \
  --skipUserCfg:on --skipParentCfg:on --skipProjCfg:on "$probeFile"

if [[ -n "$stageDir" ]]; then
  mv "$stageDir" "$nimMsvcDir"
  stageDir=
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  cygpath -w "$nimMsvcDir/bin" >> "$GITHUB_PATH"
fi

nimMsvcCompilerWindows="$(cygpath -w "$nimMsvcDir/bin/nim.exe")"
echo "Patched MSVC compiler: $nimMsvcCompilerWindows"
