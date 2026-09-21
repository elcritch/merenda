#!/usr/bin/env bash

set -euo pipefail

atlasInstallDir="${ATLAS_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$atlasInstallDir"

for atlasAttempt in 1 2 3 4 5; do
  if curl \
      --connect-timeout 30 \
      --max-time 180 \
      --retry 3 \
      --retry-delay 2 \
      -fsSL \
      https://raw.githubusercontent.com/nim-lang/atlas/HEAD/install.sh |
      ATLAS_INSTALL_DIR="$atlasInstallDir" bash -; then
    exit 0
  fi
  if ((atlasAttempt < 5)); then
    echo "Atlas installation attempt $atlasAttempt failed; retrying" >&2
    sleep "$((atlasAttempt * 2))"
  fi
done

echo "Atlas installation failed after 5 attempts" >&2
exit 1
