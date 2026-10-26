#!/usr/bin/env bash

# Bound retained GUI resources while reusing the compiled unittest runner.
set -euo pipefail

testExecutable=${1:?Usage: run-test-suites.sh TEST_EXECUTABLE}

# unittest prints every suite even when the test-name filter matches nothing.
# Discover from the executable so newly imported suites are included automatically.
suiteOutput=$(NIMTEST_COLOR=never NIMTEST_OUTPUT_LVL=PRINT_ALL \
  "$testExecutable" '::__merenda_discover_suites__')
suiteFilters=()
while IFS= read -r suite; do
  suiteFilters+=("$suite::*")
done < <(printf '%s\n' "$suiteOutput" | sed -n 's/^\[Suite\] //p' | awk '!seen[$0]++')

if (( ${#suiteFilters[@]} == 0 )); then
  echo "No unittest suites found in $testExecutable" >&2
  exit 1
fi

for ((offset = 0; offset < ${#suiteFilters[@]}; offset += 8)); do
  "$testExecutable" "${suiteFilters[@]:offset:8}"
done
