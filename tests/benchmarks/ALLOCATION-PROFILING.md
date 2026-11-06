# Allocation profiling on macOS

The allocation probes retain their results and wait for one line on standard
input at the measured checkpoint. The driver starts a fresh process with
`MallocStackLogging=1`, waits up to 120 seconds for the reported checkpoint,
captures a full-history memory graph with `leaks`, and writes live and peak
call trees using `malloc_history`. It resumes and reaps the child even on an
error or timeout. Graphs may contain application memory; store them locally.

Build the same probe in each Atlas-configured checkout, using matching Nim,
flags, and dependency versions. For example, the recorded results use `nim c
-d:release --mm:arc` with separate nimcache directories and these probe files:
The baseline's incremental build failed with an IC rescheduling error, so both
variants used the same classic backend for a matched comparison.

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

The `.memgraph` and text reports provide allocation stacks and logged live,
high-water and cumulative allocation totals. Stack logging can change memory
and timing, and its reported no-stack blocks are separate from logged totals.
RSS is a process measurement and is not live object memory. Results should
include the exact source, binary and harness hashes, the checkpoint, and any
logging limitations; use repeated untraced processes to assess variation.
