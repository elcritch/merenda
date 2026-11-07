# Allocation profiling on macOS

The allocation probes retain their results and wait for one line on standard
input at the measured checkpoint. The driver starts a fresh process with
`MallocStackLogging=1`, waits up to 120 seconds for the reported checkpoint,
captures a full-history memory graph with `leaks`, and writes live and peak
call trees using `malloc_history`. It resumes and reaps the child even on an
error or timeout. Graphs may contain application memory; store them locally.

Build the same probe in each Atlas-configured checkout, using matching Nim,
flags, and dependency versions. The recorded Markdown results use `nim c
-d:release --mm:arc` with separate nimcache directories. The baseline's
incremental build failed with an IC rescheduling error, so both variants used
the same classic backend for a matched comparison:

```sh
nim c -d:release --mm:arc --nimcache:/tmp/probe-cache \
  --out:/tmp/markdown-probe tests/benchmarks/markdownallocationprobe.nim
python3 tests/benchmarks/capture_allocations.py markdown /tmp/markdown-probe \
  /tmp/table-storage table storage 2000
python3 tests/benchmarks/capture_allocations.py markdown /tmp/markdown-probe \
  /tmp/table-view table view 500
```

Use a new output prefix for each sample. The Markdown storage checkpoint is
after `markdownTextStorage` returns, with storage and source alive. The view
checkpoint is after the first render with the view and render tree alive. The
driver releases the checkpoint after recording the graph; subsequent log lines
such as `resized` do not belong to that graph.

For SynEdit, build `syneditallocationprobe.nim` with the same command pattern,
then run `capture_allocations.py synedit /tmp/synedit-probe /tmp/synedit-graph`.
The recorded baseline used `-d:syneditProfileBaseline` with the original
SynEdit module copied alongside it as `syneditviews_profile_baseline.nim`; the
changed build uses the normal module. Both source versions and the exact
harness are identified by SHA-256 in the results file. The probe retains the
8 MiB source at its post-tokenization checkpoint.

For undo history, build `textundoallocationprobe.nim` after placing the exact
TextView variant to profile in `src/merenda/nimkit/text/textviews_profile_baseline.nim`.
Use identical module filenames for each variant, record their hashes, and run,
for example, `capture_allocations.py undo /tmp/undo-probe /tmp/undo-graph 32
enabled redo plain`. The probe retains the source and view at the checkpoint.
The separate `textundogroupallocationprobe.nim` reproduces the grouped-edit
comparison with `32 enabled group plain`.

The matched committed undo and replacement comparisons, including exact source
revisions, build commands, binary hashes, controls, and traced allocation
totals, are in [text-edit-allocations-2026-11-06.json](results/text-edit-allocations-2026-11-06.json).
Earlier intermediate-implementation measurements are labeled separately in
[textundo-allocations-2026-11-06.json](results/textundo-allocations-2026-11-06.json).

For the Kosmo preview gate, compile `kosmomarkdownrefreshmemory.nim` in each
checkout and run `capture_allocations.py preview /tmp/preview-probe
/tmp/preview-graph 20`. Repeat with zero refreshes to distinguish initial
preview setup from refresh work. Its large whitespace-only tail keeps rendered
layout small while exercising full source-buffer extraction. Full event history
can be inspected with `malloc_history /tmp/preview-graph.memgraph -allEvents`;
the full history can be very large, and global heap or RSS alone does not
identify the source-extraction allocations.

For smart insertion, compile `textsmartallocationprobe.nim` after copying the
chosen TextView source to `textviews_profile_baseline.nim`, as for the undo
probe. Run `capture_allocations.py smart /tmp/smart-probe /tmp/smart-graph
small middle enabled`. The checkpoint reports source and insertion lengths,
result length, and a streamed checksum, so each before/after pair can be
checked for identical output. The matched source revisions, build commands,
five case pairs and stack totals are in
[text-smart-insertion-allocations-2026-11-06.json](results/text-smart-insertion-allocations-2026-11-06.json).

The separate `matterhandoffmemory.nim` fixture measures an 8 MiB oversized
line submitted to a standalone Matter worker, retaining one source fixture in
both versions. Build each variant with Nim IC release/ARC and identical
dependencies, then run each binary with `8388608` in alternating fresh
processes. Three-sample medians, hashes, and commands are recorded in
[matter-handoff-memory-2026-11-06.json](results/matter-handoff-memory-2026-11-06.json).
Request-return RSS varies with asynchronous timing; this fixture does not
measure full Moe fallback extraction or an edit burst.

The `.memgraph` and text reports provide allocation stacks and logged live,
high-water and cumulative allocation totals. Stack logging can change memory
and timing, and its reported no-stack blocks are separate from logged totals.
RSS is a process measurement and is not live object memory. Results should
include the exact source, binary and harness hashes, the checkpoint, and any
logging limitations; use repeated untraced processes to assess variation.

The pinned mixed-line-break layout comparison, event-stack attribution and
three paired untraced table-view samples are recorded in
[markdown-layout-churn-2026-11-06.json](results/markdown-layout-churn-2026-11-06.json).
Its allocation-request total is cumulative traffic, not retained memory; the
live process also includes font, theme and layout caches.

For compact code-highlight keys, compile `markdownkeymemory.nim` in matched
checkouts, then run `capture_allocations.py keys /tmp/key-probe /tmp/key-graph
16 8192`. This fixture polls only Sigils until parsed structure is applied;
it asserts rendering is queued and no render chunks have run. The worker still
owns pending code strings at that checkpoint. Traced and three-pair untraced
measurements, source/binary hashes, and limits are in
[markdown-code-keys-memory-2026-11-06.json](results/markdown-code-keys-memory-2026-11-06.json).

For shared document owners, build `markdownownermemory.nim` from matched
checkouts, adding `-d:sharedMarkdownOwner` only to the shared-owner build.
Both variants initialize two empty views, then poll only Sigils until the new
structures are applied and rendering is queued; highlighting has not started.
For example, capture a fresh graph with `capture_allocations.py owner
/tmp/merenda-owner-after /tmp/owner-after 16 8192`.

`markdownembeddedmemory.nim` measures the same quoted and overflowing content
and viewport roundtrip in fresh processes, waiting for observable main and
child layout work. `markdownpreviewcachememory.nim` compares three Kosmo
previews with a nonempty isolated installed grammar; build the changed variant
with `-d:previewBudget -d:markdownPreviewProbe` to select a zero-byte soft
budget and assert one retained active view. Capture a graph with
`capture_allocations.py cache /tmp/merenda-cache-after /tmp/cache-after`.
The budget is an estimated retained-payload policy, not an RSS or native-memory
cap. Source revisions, build commands, checkpoints, raw paired samples and
limitations are in [Markdown sharing memory evidence](results/markdown-sharing-memory-2026-11-07.json).

For the embedded RSS investigation, `markdownembeddedtrace.nim` adds an
optional checkpoint pause to the same workload, and
`markdownembeddedcycles.nim` repeats the viewport roundtrip ten times. Build
both fixtures in the matched checkouts with `nim c -d:release -d:useMalloc` and
separate caches, using output names `/tmp/merenda-embedded-trace-before`,
`/tmp/merenda-embedded-trace-after`, `/tmp/merenda-embedded-cycles-before`,
and `/tmp/merenda-embedded-cycles-after`. The wrappers preserve their original
capture commands, deadlines, cleanup and output paths. For the ABBA first
render check, run:

```sh
python3 tests/benchmarks/embedded_vm_capture.py after firstRender A1
python3 tests/benchmarks/embedded_vm_capture.py before firstRender B1
python3 tests/benchmarks/embedded_vm_capture.py before firstRender B2
python3 tests/benchmarks/embedded_vm_capture.py after firstRender A2
python3 tests/benchmarks/embedded_highwater_capture.py before firstRender B
python3 tests/benchmarks/embedded_highwater_capture.py after firstRender A
python3 tests/benchmarks/embedded_stack_capture.py before firstRender Bfirst
python3 tests/benchmarks/embedded_stack_capture.py after firstRender Afirst
python3 tests/benchmarks/embedded_stack_capture.py before restored Brestored
python3 tests/benchmarks/embedded_stack_capture.py after restored Arestored
/tmp/merenda-embedded-cycles-before 12
/tmp/merenda-embedded-cycles-after 12
```

The pause wrapper uses `vmmap -summary`; the high-water wrapper uses
`MallocStackLogging=all` and `malloc_history` on the live process. The stack
wrapper captures current-live call trees at the selected checkpoint. Each sample
has its own startup and native allocator state, so compare the within-process
cycle trend separately from absolute values between processes. The measured
cycle source and its subsequently formatted equivalent have separate hashes
in the evidence file.
