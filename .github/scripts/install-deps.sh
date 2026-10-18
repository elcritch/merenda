#!/usr/bin/env bash

set -euo pipefail

# A failed fetch can leave Atlas reporting unloaded packages as version conflicts.
# Restart resolution so a transient network failure can recover.
for depsAttempt in 1 2 3; do
  if atlas install "$@"; then
    exit 0
  else
    depsStatus=$?
  fi
  if ((depsAttempt < 3)); then
    echo "Atlas dependency installation attempt $depsAttempt failed; retrying" >&2
    sleep "$((depsAttempt * 5))"
  fi
done

echo "Atlas dependency installation failed after 3 attempts" >&2
exit "$depsStatus"
