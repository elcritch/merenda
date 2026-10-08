#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r -d '' exampleFile; do
  if ! git ls-files --error-unmatch -- "$exampleFile" >/dev/null 2>&1; then
    rm -- "$exampleFile"
  fi
done < <(find examples -maxdepth 1 -type f ! -name '*.nim' ! -name '*.nims' -print0)
