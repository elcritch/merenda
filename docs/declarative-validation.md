# Declarative views: integration validation

This record distinguishes integration results from focused passes. The historical
branch attempts below preceded the final source changes; their exact commit and
worktree state were not recorded. The tests ran on macOS arm64 (Apple M3 Pro),
with Nim 2.4.2 (`b27dcb4f70883978e984e427cc24b64eeb7c875f`) and the local
Atlas dependency tree. The comparison baseline is `origin/main`
`b51cd0790a02ff0ab290b9c14b1b7ea5e29ba470`, using that same dependency tree.

## Branch integration attempts

- `nim integration` failed in `tests/tkosmo`: the independent Git diff viewer
  test received `Bad file descriptor` while listing changed files. The first
  failed assertion was `tests/kosmo/gitdiff.nim:2237`; see
  `/tmp/merenda-mvc-integration.log`. The run stopped before integration tests.
- A second `nim integration` passed Kosmo but failed in `tests/tintegrations`:
  the native modal activation test twice found that its owner was not the key
  window after ending the modal session (`nativewindowactivation.nim:101`).
  Subsequently, the worker shutdown fixture timed out waiting for the main
  thread to begin shutdown. See `/tmp/merenda-mvc-integration-retry.log`.
- Running the built integration binary separately with the filters
  `./tests/tintegrations 'NimKit native window activation::*'` and
  `./tests/tintegrations 'NimKit direct-import worker shutdown::*'` passed
  (`/tmp/merenda-native-activation.log` and
  `/tmp/merenda-worker-shutdown.log`). These focused passes do not make the
  full integration run green.

The worker timeout is a secondary failure mechanism: after any unittest failure,
`tests/tintegrations.nim` calls `quit(getProgramResult())`. The worker fixture
waits for the `ReleaseWorkerAtExit` module destructor to set `exitStarted`,
but Nim documents that `quit` bypasses destructors. At the time of the
historical failures, the runner and fixture were unchanged from the baseline. This explains why a preceding failure can block
this fixture during teardown; it does not establish the cause of the earlier
native activation failure.

## Git descriptor investigation

Nim 2.4.2's POSIX `osproc` aliases `outHandle` and `errHandle` for
`poStdErrToStdOut`, then closes each in `Process.close`. A scratch probe
(`/tmp/merenda_osproc_alias_probe.nim`, output
`/tmp/merenda-osproc-probe.log`) called
`nim ic -r --nimcache:/tmp/merenda-osproc-probe-cache /tmp/merenda_osproc_alias_probe.nim`.
It arranged for a new descriptor to reuse the output descriptor between those
closes; output was `output=5 error=5 reused=5 fcntl=-1 errno=9`, demonstrating
that the second close closed the reused descriptor. The unchanged baseline
`backgroundprocesses.nim` uses merged output and closes `Process` objects, so
concurrent subprocesses can encounter this pre-existing mechanism. The failed
Git run did not capture descriptor ownership or ordering, so this is a concrete
plausible cause, not proof of the particular failure.

The scratch probe was the following POSIX program. The two initial opens fill
lower free descriptor slots in this run; verify `reused` equals `output` before
interpreting the final `fcntl` result on another system.

```nim
import std/[osproc, streams, posix]
var oldClose: typeof(StreamObj.closeImpl)
var reusedFd: cint = -1
proc interceptClose(s: Stream) {.gcsafe, raises: [IOError, OSError].} =
  discard posix.open("/dev/null", O_RDONLY)
  discard posix.open("/dev/null", O_RDONLY)
  oldClose(s)
  reusedFd = posix.open("/dev/null", O_RDONLY)
let p = startProcess("/usr/bin/true", options = {poStdErrToStdOut})
discard p.waitForExit()
let outputFd = p.outputHandle()
let errorFd = p.errorHandle()
let output = p.outputStream()
oldClose = output.closeImpl
output.closeImpl = interceptClose
p.close()
echo "output=", outputFd, " error=", errorFd, " reused=", reusedFd,
  " fcntl=", fcntl(reusedFd, F_GETFD), " errno=", errno
```


## Baseline comparison

A clean detached worktree at `b51cd0790a02ff0ab290b9c14b1b7ea5e29ba470`
used the branch's Atlas `deps/` and `nim.cfg`, with a separate cache.
`NIMFLAGS='--nimcache:/tmp/merenda-baseline-nimcache' nim integration` failed
before executing tests: Nim IC reported that modules stopped for imports
without rescheduling progress while compiling `tests/tnimkit.nim`. See
`/tmp/merenda-baseline-integration.log`. This is a compiler/build failure, not
a passing or failing comparison of the affected runtime tests.

`nim ic --nimcache:/tmp/merenda-baseline-nimcache -r tests/tintegrations.nim`
failed with the same IC scheduling error before executing tests
(`/tmp/merenda-baseline-tintegrations.log`). A standard C backend fallback,
`nim c --nimcache:/tmp/merenda-baseline-c-cache -r tests/tintegrations.nim`,
passed both native activation tests in the full shared runner
(`/tmp/merenda-baseline-tintegrations-c.log`). A passing single baseline run
cannot establish whether the branch's intermittent native activation failure
is a regression; its cause remains unresolved.

The C-backend baseline runner ultimately failed at
`tests/integrations/resourcelifetimes.nim:239`: the observed child-process count
was 0, equal to the initial 0, when the test expected an increase. It did not
complete the remaining integration tests. This baseline failure is separate
from the branch failures listed above.

## Shutdown failure-path regression

A controlled branch reproduction set `MERENDA_TEST_FORCE_SHUTDOWN_FAILURE=1`
and ran the shared integration binary filtered to the active parsing shutdown
test, with an intentional `check false` immediately after its existing worker
readiness assertion. It reproduced the failed check followed by the same
60-second `main thread did not begin shutdown` assertion
(`/tmp/merenda-forced-shutdown-before.log`). The runner now releases and joins
the waiting worker before `quit` on a failed suite. A bounded child-process
regression checks the intentional failure path, while the ordinary successful
path continues to test global destructor ordering. The focused suite passed
(`/tmp/merenda-shutdown-fix-tests.log`); the full integration result is
recorded separately when available.

## Final component checks

At source commit `e87815f0` (with only pending documentation edits), the
following independent checks ran on macOS arm64. They do not constitute a
single successful `nim integration` invocation:

- `nim ic -r tests/tnimkit.nim`: 1,623 tests passed with Nim 2.4.2 IC
  (`/tmp/merenda-premerge-nimkit.log`).
- `nim ic -r tests/ttekton.nim`: 49 tests passed with Nim 2.4.2 IC
  (`/tmp/merenda-premerge-tekton-final.log`).
- `atlas-run tests --nimcache:deps/.nimcache/ --backend:ic --compile-only examples/all_compile.nim`:
  example bundle compiled with Nim 2.4.2 IC (`/tmp/merenda-premerge-examples.log`).
- The final integration runner compiled with
  `nim ic --nimcache:deps/.nimcache/ tests/tintegrations.nim`, and
  `./tests/tintegrations 'NimKit direct-import worker shutdown::*'` passed all
  three shutdown tests (`/tmp/merenda-final-shutdown.log`).
- The Kosmo runner built with Nim 2.2.10's C backend and ran as
  `MERENDA_BACKGROUND=1 /tmp/merenda-tkosmo-ci`: 587 tests passed (`/tmp/merenda-tkosmo-ci.log`).
- `./tests/tintegrations` ran the full shared integration runner built above:
  176 tests passed, including both native activation tests, resource settlement,
  and the shutdown tests (`/tmp/merenda-final-tintegrations.log`). The earlier
  native focus failure did not recur in this run.

## CI failures on the earlier head

On `fd98fefbc3953fbb53eedad42cf9abd9c123a0b0`, the
[build-full run 43634788625](https://github.com/elcritch/merenda/actions/runs/43634788625)
failed its macOS and Linux Nim 2.2.10 shared-runner coverage checks because
`tests/nimkit/taskdemochecks.nim` was not imported. Commit `5f7edc72` added the
missing import. In the same run, macOS job 132569105560 and Linux job
132569105419 failed compiling Kosmo: `settings.nim:1144` supplied a closure
handler where `newReceiverActionTarget` expected `nimcall`. The
[release-kosmo run 43634788516](https://github.com/elcritch/merenda/actions/runs/43634788516)
failed with the same signature on macOS, Linux, and Windows (jobs 132569105042,
132569105200, and 132569105140). Commit `e5e5ee26` fixed the action macro.
The earlier head's Linux ARC and ORC sanitizer jobs and macOS/Linux example
jobs passed. Final-head CI results must be checked separately after pushing.

The baseline `b51cd079` also compiled `tests/tkosmo.nim` successfully with
Nim 2.2.10 using `nim c --compileOnly --hints:off --warnings:off
--nimcache:/tmp/merenda-base-kosmo-cache tests/tkosmo.nim` (the Nim binary was
`/Users/elcritch/.local/share/grabnim/nim-2.2.10/bin/nim`). This was a
compile-only comparison, not a baseline runtime pass.

To investigate the earlier native focus failure, the baseline shared runner was
rebuilt with Nim 2.4.2's C backend after adding only failure-diagnostic
checkpoints to `nativewindowactivation.nim`. Ten sequential runs of
`./tests/tintegrations 'NimKit native window activation::*'` all passed both
tests (`/tmp/merenda-baseline-native-repeat-{1..10}.log`). These focused runs
and the passing full branch runner narrow the observation but do not reproduce
or explain the historical failure. The checkpoints remain in the branch test
to capture the owner, pre-session key window, saved key window, and restored
key window if it recurs.

## Later Linux Kosmo CI failure

The [build-full run 43637983423](https://github.com/elcritch/merenda/actions/runs/43637983423)
at `fa78d0e2714d40254bc49eac610b675ab4f0207b` failed Linux Kosmo job
[132578923897](https://github.com/elcritch/merenda/actions/runs/43637983423/job/132578923897)
on Ubuntu 26.04, Nim 2.2.10, and X11. The test `diff shortcut finds the
nearest repository of the selected editor file` failed `siblingIncluded` at
`tests/kosmo/gitdiff.nim:2316`.

The same test and assertion had already failed on `main` with the same Linux,
Nim, and X11 configuration in [run 42834219040](https://github.com/elcritch/merenda/actions/runs/42834219040)
at `2356437eca145cacfb60472884de9d1f858cecfd`, and twice in
[run 41943714107](https://github.com/elcritch/merenda/actions/runs/41943714107)
at `dd4163b492718796ca41bd2d4022620bbcb0c156`. Both commits are ancestors of
baseline `b51cd079`; the test file is unchanged between `2356437` and that
baseline. Thus this matching CI failure predates the branch. Its underlying
cause is unknown, and the logs do not establish a connection to the separately
investigated `Bad file descriptor` failure above.

### Linux Git subprocess investigation and repair

On a Linux x86_64 container with Nim 2.2.10 and Xvfb, the original failing
Kosmo test reproduced on iteration 14. Its Git snapshot reported `Bad file
descriptor` while running `rev-parse` and contained no files
(`/tmp/merenda-linux-kosmo-repro.log`). That observation identifies a failed
Git command rather than a successful listing that omitted `sibling.txt`.

Merenda now starts POSIX background commands with separate stdout and stderr
pipes and drains both non-blockingly, avoiding Nim's aliased-handle close in
its own command wrapper. Its combined output preserves all bytes subject to the
existing output limit; relative ordering between the two streams is not
promised. Focused lifecycle tests cover large stdout-only, stderr-only, and
simultaneous output, concurrent commands, output limits, timeout, and cleanup.
The macOS Nim 2.4.2 suite passed (`/tmp/merenda-process-fix-macos-final.log`),
and the Linux Nim 2.2.10 suite passed with the same production wrapper
(`/tmp/merenda-linux-process-green.log`). GitHub CLI integration also passed
on macOS (`/tmp/merenda-process-fix-macos-github.log`).

The wrapper change alone did not eliminate the failure: the same test failed
on Linux iteration 30 with an empty Git error and, with a diagnostic Git
wrapper, on iteration 6 with `Bad file descriptor`
(`/tmp/merenda-linux-kosmo-fixed-repeat.log` and
`/tmp/merenda-linux-kosmo-traced-repeat.log`). Moe's editor Git diff and branch
jobs also used merged osproc handles while the test ran. Its POSIX Git jobs
were changed in fork commit `bbbd4247df78b7a536ba25ec269dfd6ebef043ca` to
avoid those aliased handles and parent working-directory changes. With both
fixes, the original Linux test passed 30 consecutive runs
(`/tmp/merenda-linux-kosmo-combined-repeat.log`). The fork's focused Git diff
and cache tests passed on Nim 2.2.10. These observations and the independent
osproc probe support the descriptor-race diagnosis; the repetitions are finite
and the failure was not captured with a syscall trace.

## DirectView lifetime and sanitizer follow-up

The macOS job on `29ddf452`
([132582482949](https://github.com/elcritch/merenda/actions/runs/43639132954/job/132582482949))
reported allocator free-block corruption during HarfBuzz allocation while the
README Markdown test waited for layout. That allocation is the detection site,
not proof of the corrupting write.

A full local Nim 2.2.10 sanitizer run found a concrete earlier use-after-free in
`DirectNode.flushBindings`: a child binding called `host.clear()`, releasing the
root while the active traversal still borrowed it. The existing reentrant-clear
lifetime test exposed the invalid access. Commit `0be531c1` makes the traversal
own its node through a `sink` parameter. Generated C retains the root before the
call and releases it on exit; weak-root assertions verify survival during the
callback and release afterwards.

UBSan also exposed nil base-object conversions in table removal, document
notifications, and menu removal. Commits `ba2ffe70` and `78d75b2b` guard those
specific boundaries. These are separate findings, not evidence that the nil
conversions caused the allocator crash.

The full suite then passed **1,624 tests**, with no ASan or UBSan diagnostics,
using these commands from the Merenda checkout:

```sh
/Users/elcritch/.local/share/grabnim/nim-2.2.10/bin/nim c \
  --nimcache:/tmp/merenda-macos-asan-cache \
  -o:/tmp/merenda-macos-asan-tnimkit -d:nimkitSanitizers tests/tnimkit.nim
UBSAN_OPTIONS=halt_on_error=1 MERENDA_BACKGROUND=1 /tmp/merenda-macos-asan-tnimkit
```

Project/test configuration selected ARC, threads, release, `useMalloc`,
`noSignalHandler`, and address/undefined sanitizers with frame pointers. The
successful run is `/tmp/merenda-macos-asan-strict-full.log`; the original ASan
failure is `/tmp/merenda-macos-asan-full.log`. The host was macOS 15 / Darwin
24.6.0 arm64, whereas CI used macOS 26 / Darwin 25. The repaired use-after-free
could explain subsequent heap damage, but this does not conclusively identify
the writer behind the CI allocator report. Final-revision CI remains the merge
gate, with its current results recorded in PR #224.
