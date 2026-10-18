#!/usr/bin/env bash

set -euo pipefail

# Stable Nim 2.2.10 with corrected MSVC atomic exchange/CAS/arithmetic.
# Keep the environment name tied to the immutable source revision.
nimMsvcRevision=31511ba12d9d9333fdf886b4ae2fe78b5b398645
nimMsvcEnvironment=msvc-2.2.10-31511ba1
githubPathArgs=()
if [[ -n "${GITHUB_PATH:-}" ]]; then
  githubPathArgs=(--github-path)
fi
atlas env "$nimMsvcEnvironment" \
  --git-url=https://github.com/elcritch/Nim \
  --git-ref="$nimMsvcRevision" \
  "${githubPathArgs[@]}"

echo "Patched MSVC compiler: deps/nim-$nimMsvcEnvironment/bin/nim.exe"
