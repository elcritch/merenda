# Sigils 0.33 size review

This branch depends on the Sigils `perf/share-signal-dispatch` branch and its
0.33.0 release. Merge/release that dependency before installing this branch's
updated manifest with Atlas.

## Changes and compatibility

Resource property discovery now reads ProtocolRequirement.valueType, generated
from the setter AST. It no longer parses verbose diagnostic signature strings.
The existing getter pairing, namespace handling, value-type registration, aliases,
conversion, and setter dispatch remain intact. The minimum Sigils version is
0.33.0 and config.nims disables generated protocol signatures.

The library still defaults to verbose signatures; this application opts out.
Routing names and resource action selectors remain strings. No numeric IDs,
transport changes, stripping, debug-symbol changes, or unsafe copying are added.

## Validation

- `nim c --opt:size examples/hello.nim`, with separate /tmp output paths, succeeded
  before and after. File bytes: 13,102,616 -> 12,315,696 (6.0% smaller).
  Machine code: 5,065,436 -> 4,641,728 bytes (8.4% smaller).
- The modified hello demo initialized its native Metal window and remained running
  for a five-second smoke test before deliberate termination.
- The shared `tests/tnimkit.nim` runner compiled; all 15 tests selected by
  `NimKit resources::*` passed with signatures disabled. Other suites compiled
  but were not executed in this run.

## Investigation notes

A compiler --path override did not replace the installed Sigils checkout.
`atlas link ../sigils` then failed resolving the existing Variant
`#fix/ic-type-ids` requirement. For validation, the installed checkout was
preserved and a temporary dependency-path symlink selected the sibling Sigils
branch. This is local validation setup, not a committed dependency workaround.

One initial baseline build overlapped an edit and was discarded/rebuilt. I also
mistook repeated `nim ic` frontend passes for a stall and restarted the test build
using `nim c`. The user clarified that the passes are normal and initial ic
builds take roughly three minutes; this is not a confirmed compiler issue.

The Sigils summary in `docs/binary-size-review.md` on its companion branch covers
each implementation block, ownership constraints, measurements, deferred choices,
and the RChan specialization follow-up. The Sigils suite has one baseline RChan
hook-count failure reproducible on the unmodified dependency; it is unrelated to
the resource metadata migration.

## Final Kosmo rebuild

Both builds succeeded using `nim c --opt:size --debugger:native --lineTrace:off
--stackTrace:off -d:moe.embedded --out:/tmp/kosmo-size-{before,after}
src/merenda/kosmo/kosmo.nim`. Baseline used Sigils 0.32.1 and original resource
metadata/config; after used this branch and compact metadata. Symbols verify
that only the after executable contains dispatchLocalPayload. No stripping or
LTO was used. Outputs and dSYMs are in /tmp; the existing Kosmo executable and
installed app were not overwritten.

| Metric | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| File bytes | 31,707,696 | 30,417,968 | 1,289,728 (4.1%) |
| Machine code (`__text`) | 11,817,508 | 11,011,100 | 806,408 (6.8%) |
| Text constants | 4,745,288 | 4,674,184 | 71,104 (1.5%) |

The temporary Sigils symlink and Atlas link metadata were removed after validation;
the original dependency checkout/config were restored. To rebuild the companion
Merenda branch, first install/link Sigils 0.33.0. It is intentionally an ordered
cross-repository change, not a published dependency release yet.
