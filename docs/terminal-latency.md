# Terminal latency diagnostics

Build the optional timing probe from the repository root:

```sh
nim c -d:nimkitTerminalTrace tests/benchmark_terminal_native.nim
tests/benchmark_terminal_native cmatrix terminal /tmp/terminal-cmatrix.jsonl
tests/benchmark_terminal_native ps terminal /tmp/terminal-ps.jsonl
tests/benchmark_terminal_native cmatrix kosmo /tmp/kosmo-cmatrix.jsonl
tests/benchmark_terminal_native ps kosmo /tmp/kosmo-ps.jsonl
tests/benchmark_terminal_native burst kosmo /tmp/kosmo-burst.jsonl
python3 tests/benchmarks/terminal_trace_summary.py /tmp/kosmo-cmatrix.jsonl /tmp/kosmo-ps.jsonl
```

`cmatrix` must be installed. Run the probes sequentially, with no concurrent
builds or GUI tests, to avoid contention. Each probe opens a real window, waits
for a PTY handshake, measures one second of idle process CPU, then observes
three seconds of output through `Application.run()` and its blocking native
event loop. The terminal has no keyboard focus, excluding cursor blinking from
the idle sample. The `ps` workload runs twelve commands separated by 150 ms; those
intentional gaps must not be interpreted as presentation stalls. The `burst`
workload emits 10,000 lines and a final marker without intentional gaps. The
probe reports both idle and active process CPU as a percentage of one core.

The trace records monotonic timestamps, thread IDs, object identities and byte
counts. It never records terminal contents. Instrumentation compiles out unless
`nimkitTerminalTrace` is defined. Its bounded buffer reports overflow rather
than silently producing an incomplete measurement.

Stages include PTY readiness, delivery to the UI queue, read/parse work, grid
synchronization, frame construction/submission, renderer work, and native
presentation submission. `poll-start` to `poll-end` includes the nonblocking
read, parsing, input/reply flushing and child-exit check. `present` is recorded
after `endFrame()` returns; it measures submission, **not display scanout or
GPU completion**. The summary correlates cumulative render IDs so skipped
submissions are included in the next frame that presents their output. Its
end-to-end correlation assumes one terminal and one native window, using the
dedicated renderer's render IDs. A fallback renderer still exposes individual
stage timings.

## Historical row batching and shared-lock worker measurements

These measurements describe `6b891cca` and the shared-lock worker in `bcdf6907`.
The subsequent exclusive-ownership/RChan design has not been benchmarked.

The rendering/frame-pacing changes are isolated in `6b891cca`. On the same
machine and Kosmo `cmatrix` workload, row batching reduced p95 frame
construction/submission from 8.90 ms to about 2 ms. This is the main measured
improvement for continuous animation.

Comparing that commit with the separate PTY worker change:

- `cmatrix` readiness-to-presentation p95 was 5.92 ms in a successful committed
  baseline sample and 5.89 ms with the worker. The worker sample used 53.65% of
  one CPU core during animation; idle samples remained around 2%.
- A paired `ps` sample measured p95 11.51 ms versus 12.43 ms. Moving these small
  reads to a worker does not demonstrate a latency improvement.
- Draining a 10,000-line burst took 117.12 ms versus 120.02 ms. The worker's
  read-to-presentation maximum was 18.72 ms and its viewport-update maximum was
  2.19 ms. Worker parsing can continue without UI read jobs; this sample shows
  comparable throughput, not a throughput gain.

The first worker implementation exposed unfair lock reacquisition during floods,
delaying a viewport update by 78.31 ms. Giving waiting UI access priority reduced
that maximum to 2.19 ms in the final burst sample. Each contended continuation
waits 1 ms; idle samples contained no PTY reads, grid updates, or continuations.

These are short three-second observations. An additional committed-baseline
`cmatrix` run hit a 997.97 ms renderer stall, consistent with the intermittent
presentation issue described below. Its absence in the worker sample does not
establish that the worker fixes that issue. Presentation timings measure native
submission, not scanout; burst CPU averages include the quiet remainder of the
three-second observation.

## Earlier native measurements

Measured on an Apple M3 Pro, macOS 15.7.9, Nim 2.2.12, using the automatic Metal
renderer. The baseline is Merenda `2e3c2cb7` with tracing added and Terminex
`176ff0e`; the comparison used UI-thread read budgets and coalesced output frames. Both use the same
probe and window sizes. Each row is one three-second sample, not a statistical
performance guarantee. Latency is per readiness notification that produced
output, through its first grid synchronization and presentation submission.

| Window / workload | Before p95 | After p95 | Before / after presentations |
| --- | ---: | ---: | ---: |
| Kosmo / `ps` | 30.81 ms | 11.59 ms | 46 / 28 |
| Standalone / `ps` | 26.17 ms | 10.81 ms | 54 / 24 |
| Kosmo / `cmatrix -u 1` | 16.92 ms | 17.49 ms | 237 / 236 |
| Standalone / `cmatrix -u 1` | 20.24 ms | 22.19 ms | 236 / 233 |

In these paired samples, coalescing reduced redundant `ps` frames and its latency
tail. Continuous
`cmatrix` throughput stays approximately unchanged; this change does not remove
its rendering cost. In the Kosmo baseline, p95 readiness-to-UI delivery was
0.15 ms, read/parse was 0.09 ms and grid synchronization was 0.31 ms, versus
8.74 ms for frame construction/submission and 6.34 ms for renderer work. These
stages overlap across frames, so their percentiles should not be added.
The sampled path does not show a systematic 500 ms native-wakeup stall.

A later validation run caught a **693.96 ms renderer stall** in Kosmo `ps`:
that run's end-to-end p95 was 706.01 ms. Meanwhile, read/parse never exceeded
0.14 ms, grid synchronization 0.39 ms, or an application frame 14.01 ms. Output
continued to be read, synchronized, and submitted while the renderer stalled.
Option 1 therefore does not eliminate every visible pause. This outlier points
to the renderer/presentation path, rather than terminal parsing or UI wakeup.
The trace now also separates resource preparation, backend frame setup,
scene rendering, and the final backend presentation hook. FigDraw's Metal
scene-rendering path includes GPU completion waits and drawable acquisition;
those are follow-up investigation targets, not established causes of the stall.

Two further paired Kosmo `ps` runs measured p95 22.40 → 11.78 ms and
24.65 → 11.98 ms. The long renderer stall did not recur in those runs. With the
finer instrumentation, resource preparation stayed below 0.40 ms and scene
rendering below 4.57 ms. The intermittent presentation issue remains open.

The updated idle traces contain zero PTY polls and no terminal grid updates.
Kosmo still wakes for its other work (23 application frames in the measured
idle second, both before and after). Short process-CPU samples varied with
native window activity, so they do not establish an absolute idle-CPU saving.
The scheduling guarantee is that terminal output adds no periodic fast timer.

If continuous animation still feels chunky, the next measured target is frame
construction and renderer work. Moving parsing to a worker is more relevant to
large output floods than to the ordinary `cmatrix` batches measured here.

## Scheduling

`TerminalViewSession` is NimKit's alias for Terminex's `ThreadedTerminalSession`.
Terminex owns the generic session facade, snapshots, commands, trace recorder,
and worker lifecycle; NimKit adds viewport anchoring, subscriptions, rendering,
and native event-loop integration. The macOS tracking/modal-loop wakeup fix
remains in NimKit.

Every `TerminalViewSession` owns a worker proxy on the dedicated Sigils terminal
readiness dispatcher. The worker exclusively owns its raw Terminex session,
including parsing, input, resize, startup, signals, and process cleanup. Multiple
terminals share this dispatcher, separate from the timer dispatcher and general
worker pool. POSIX readiness reads use a cooperative 2 ms budget between chunks;
a single chunk can exceed that budget. Rearming never waits for the UI.

Commands use Sigils `sink` arguments. Screen snapshots cross a capacity-one
RChan as isolated owned values. The UI acknowledges each received snapshot;
normal publication has one outstanding snapshot and at least 8 ms between
publications during continuous output. The first update after idle is immediate.
While publication is waiting for an acknowledgement, the worker keeps reading
and parsing. EOF and lifecycle changes may replace an unread snapshot. Snapshots
carry cumulative byte counts and history since the last acknowledgement, so
replacement cannot lose retained output. Publication timers are one-shot and
exist only while there is dirty state to publish.

The UI holds its own compact history and live rows. It applies newly retained
history and replaces live rows, then builds visible rows from this local cache.
Neither queries nor rendering acquire a parser lock. RChan holds its internal
lock only while transferring an owned message; parsing, copying rows, applying
history, and rendering occur outside that lock. There is no UI-priority lock
workaround or synchronous session fallback.

Presentation retains its own coalesced frame deadline. Final output is
synchronized before process-exit notification. Detaching a view cancels its UI
subscription and pending frame; the session worker continues draining output.
Closing or restarting increments the session epoch, so an earlier snapshot
cannot overwrite the new lifecycle state.

Healthy idle PTYs have no periodic reads. The worker schedules maintenance for
backpressured input or an EOF whose child exit is not yet observable. If native
readiness registration fails, polling stays on the worker with a 16 ms fallback;
it never moves parsing onto the UI. The view's 500 ms heartbeat handles blinking
and observes direct close. Windows builds use the same worker API, but Terminex
currently rejects native shell startup there because it lacks ConPTY support.

`worker-poll-start` to `worker-poll-end` measures worker read/parse work;
`poll-start` to `poll-end` measures UI consumption of snapshots. Cumulative worker
read serials accompany viewport snapshots for trace correlation. Traces contain
no terminal text.

## Frame construction and row drawing

A changed row groups nonadjacent glyphs with matching color, weight and italic
style into the same text operation, preserving each cell's horizontal position.
Blank and hidden cells still paint backgrounds and decorations but allocate no
glyph arrangement. Unchanged rows retain their existing render slots.

Native windows defer construction of another frame while a dedicated renderer
submission is outstanding. Dirty views and native damage remain pending;
renderer completion wakes the application to build the newest state. An older
completion cannot mark a newer submission complete. This gate avoids building
frames merely to replace them in the renderer's latest-frame queue, without a
new periodic idle timer.

## Session API and ownership

Use `newTerminalViewSession()` for an idle, worker-owned session, or
`spawnTerminalViewSession(options)` to queue startup. `newTerminalView()` and
`newTerminalView(options)` use the same path. Raw `CompactTerminalSession` aliases
are no longer accepted by views: they cannot establish exclusive worker ownership.
Terminex's standalone raw API remains available for its own callers.

`screenInfo()` and `lineAtAbsolute()` return owned values from the UI cache.
`screen()` returns a `TerminalScreenSnapshot` containing owned screen/history,
so prefer smaller queries for frequent inspection. A viewport snapshot captures
metadata and visible rows together without waiting on the worker.

`processOutput`, `write`, `resize`, `clearScrollback`, limit changes, signals,
`start`, and `close` enqueue ordered commands. `poll()` only consumes available
snapshots; it does not wait for command completion or read the PTY. Pump the owning
Sigils event loop to receive automatic updates. `pendingCommands()` reaches zero
when all submitted commands have been applied and acknowledged in a snapshot.
`running()` includes pending startup. Startup failures arrive through `state()`
and `lastError()`. Signal methods return whether delivery was queued, not whether
the OS accepted it. `close()` marks the facade closed immediately; process
termination and reaping complete on the worker.

A snapshot owns value fields, strings, and cell sequences. It contains no live
session references. Previously returned snapshots remain unchanged by later
worker output, including scrollback eviction, clear, and resize.

## Dependency

Terminex 0.4.0 adds the optional `sigils` feature and `terminex/threaded` API used
by NimKit. Merenda requires Terminex 0.4.0 or newer with that feature enabled.
Use the requirement configured in Merenda's Atlas dependencies. The core
`import terminex` remains independent of Sigils and works with threads disabled;
it exposes synchronous parsing, budgeted PTY polling, and owned snapshot helpers.
Merenda's `-d:nimkitTerminalTrace` also enables `-d:terminexTrace`, preserving the
existing diagnostic command across both libraries.

## Terminex extraction validation

- Terminex PR #6 passes the core and optional Sigils suites on Linux and macOS,
  including core builds with threads disabled and worker tests under ORC.
- In an independent local Atlas workspace, all eight Terminex runners passed.
  Worker and automatic-shutdown tests also passed with ORC + AddressSanitizer/
  UBSan and tracing enabled, and with ARC in release mode.
- Core tests and examples passed with threads disabled and only core dependency
  paths configured. The threaded example bundle also compiled, and Windows
  amd64 C generation passed; Windows native execution was not tested.
- Merenda's four shared runners passed against the extracted modules, the
  example bundle compiled, and the existing trace probe passed semantic checking.

No performance benchmark was run for the extraction.

## Exclusive-ownership validation

- All four normal shared runners passed, including the final integration rerun.
- The example bundle compiled with
  `atlas-run tests --compile-only examples/all_compile.nim`.
- Windows amd64 semantic checking and C generation passed for the terminal
  session/worker modules. Windows native execution was not tested.
- All 90 focused terminal checks passed with ORC and AddressSanitizer/UBSan:
  79 integration checks and 11 snapshot, worker, and geometry checks. This does
  not claim a clean full ORC sanitizer suite; the historical workspace-watcher
  teardown defect below remains outside this change.
- Tests cover offline worker commands, independent sessions, immutable snapshots,
  overlapping and skipped history updates, alternate screens, retained clipboard
  requests, input queue limits, resize/write ordering, close/restart epochs, and
  final output. A blocked-dispatcher test checks that UI queries and command
  submission finish without worker access. A withheld-ACK test verifies that
  PTY draining and final snapshot delivery continue while the UI is stalled.
- Deferred UI work now uses a lifetime-tracked `BackRef`. A destruction
  regression verifies that draining queued callbacks after ORC collects their
  view is harmless; this fixes a use-after-free found during sanitizer validation.

No new performance benchmark was run for this ownership design.

## Historical shared-lock worker validation

- The normal full suite passed all four shared runners; the example bundle
  compiled with `atlas-run tests --compile-only examples/all_compile.nim`.
- After adding lock fairness and cumulative trace correlation, the terminal
  output-watch, parser, session, view, and worker-shutdown suites passed all 76
  checks with ORC and AddressSanitizer/UBSan enabled.
- The final normal `atlas-run tests integrations` rerun also passed.
- The full ORC sanitizer integration run found a workspace-watcher timer
  use-after-free in Sigils reference collection during Kosmo teardown. The same
  allocation/free stacks reproduce on `6b891cca` without the PTY worker. This is
  an unresolved teardown defect; the full ORC sanitizer suite is not clean.

Worker coverage includes a 10,000-line flood parsed without UI read jobs,
coalesced notifications, immutable prior snapshots, cancellation before startup
acknowledgement, detach/reattach, direct session close, final output/exit status,
and shutdown of both readiness and timer dispatchers.

## Earlier validation

- Merenda's full `atlas-run tests` suite: 4/4 runners passed.
- Terminex's full suite: 5/5 runners passed.
- Final integration/session regression run: 2/2 runners passed.
- `atlas-run tests --compile-only examples/all_compile.nim`: compiled.

Coverage includes yielding before parsing, fixed presentation deadlines, no
idle read scheduling, draining final output across multiple budgets, pending
input at exit, and cancellation when closing, detaching, or replacing sessions.
An initial full run failed the existing Bash Ctrl-C interaction check; subsequent
focused and full runs passed. The new scheduling regressions passed throughout.
