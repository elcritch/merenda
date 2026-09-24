# Reliability and memory checks

Run the shared suites with `atlas-run tests`. CI checks that every component test
module is imported by its runner; helper modules belong in a fixtures directory.
Live terminal processes and native window lifecycles run in `tests/tintegrations.nim`.

## Repeated resource lifetimes

`tests/integrations/resourcelifetimes.nim` warms the application infrastructure,
then repeats six cycles of two Kosmo windows, five live terminals, Git queries,
workspace refreshes, and Markdown parsing/layout. Every cycle closes the manager,
pumps the owning application loop, and waits for children and descriptors to
return to their warmed baseline. A small descriptor tolerance allows native
runtime housekeeping.
RSS and total threads are diagnostic checkpoints: native drivers create
housekeeping threads lazily, so thread count is not an owned-worker count.

`processResourceUsage()` in `merenda/nimkit/app/diagnostics` reports current and
peak resident bytes, open descriptor count, child count, and thread count on
macOS and Linux. Unavailable fields are `-1`. These are observations of the
current process, not its children or a count of live Nim allocations. Sampling
uses native APIs or `/proc`, without starting diagnostic subprocesses.

Run a standalone memory workload with:

```sh
nim r tests/benchmark_memory.nim
```

It prints checkpoints for UTF-8 gap storage, repeated edits, four Markdown views,
and a 1,001-view retained render scene. It also reports the lower-bound array
sizes of full and incremental renderer updates. The estimate excludes resource
payloads, allocator capacity/headers, and nested glyph data. It is useful for
comparing the same workload before and after a change, not as total memory usage.
In the 2026-09-24 macOS/arm64 run, compacting unchanged frame metadata reduced
one-view updates from 1,145,272 to 25,296 bytes (97.8%). Full updates grew from
1,273,272 to 1,297,296 bytes because they also carry the explicit placement list.
The receiving thread expands the list temporarily while reconciling; the savings
apply to queued snapshots, not every allocation in a rendered frame.

RSS can stay high after objects are freed because allocators retain pages;
compare repeated warmed runs and resource counts before calling that a leak.

## Bounded URL loading

`newUrlAssetLoader` accepts `maximumAssetBytes`, `maximumConcurrentLoads`, and
`maximumPendingLoads`. Defaults are 64 MiB per asset, four network transfers, and
256 active plus queued distinct URLs. Duplicate URLs share a handle. Queue
admission happens on the caller thread, bounding queued worker messages as well
as downloads. A full queue returns a finished failed handle.

Bodies stream to temporary files through a 32 KiB application buffer per active
transfer. The byte limit applies during reading, including chunked responses and
cached files. A one-byte probe detects overflow at the exact boundary. HTTP
errors, cancellation, and overflow remove partial files; successful downloads
replace the cache entry only after the response is complete. Chronos connection
buffers and decoded image memory are additional costs.

These are per-loader limits. Disk-cache capacity and aggregate budgets across
independent image, Markdown, and Git-diff caches remain separate follow-up work.

## Ownership sanitizers

The ownership subset uses the existing NimKit runner:

```sh
atlas-run tests nimkit -- --cc:clang --mm:arc -d:nimkitOwnershipTests -d:nimkitSanitizers
atlas-run tests nimkit -- --cc:clang --mm:orc -d:nimkitOwnershipTests -d:nimkitSanitizers
```

The define enables AddressSanitizer, UndefinedBehaviorSanitizer, native stack
symbols, and malloc-backed Nim allocation. CI runs both configurations on Linux.
The subset covers back references, modal lifetimes, gap/text storage, text layout,
fragment updates, and renderer-thread resource ownership. Full GUI integration still
runs separately. Sanitizers complement the observable lifecycle assertions;
they do not establish a universal RSS ceiling or prove absence of every leak.

Under ORC, native FigDraw renderers remain on the UI thread. Moving a renderer
created on the UI thread caused an ORC cycle-root unregister crash on the receiving
thread during sanitizer testing. `dedicatedRendererSupported()` reports this
restriction, and automatic mode uses UI-thread rendering. Explicitly requesting
dedicated mode raises the existing unsupported-backend error. ARC keeps dedicated
rendering. The ORC sanitizer subset exercises native renderer exception cleanup
through automatic mode and checks the actual drawing-error message.
