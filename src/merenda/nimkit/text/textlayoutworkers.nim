## Internal Sigils worker for expensive attributed-text reflow.

import std/isolation

import sigils/[core, threads]
import threading/smartptrs

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

import ../drawing
import ../foundation/types
import ../foundation/backgroundworkers
import ../themes
import ./textstorage
import ./texttypes
import ./textlayouttypes

type
  TextLayoutWorkerResult* = object
    generation*: uint64
    arrangement*: GlyphArrangement
    snapshot*: TextLayoutSnapshot
    snapshotThreadId*: int

  TextLayoutSnapshotBuilder* = proc(
    arrangement: var GlyphArrangement,
    storage: TextStorage,
    containers: seq[TextContainer],
    style: TextStyle,
    alignment: TextAlignment,
  ): TextLayoutSnapshot {.nimcall.}

  TextLayoutWorker* = ref object of AgentActor
    snapshotBuilder: TextLayoutSnapshotBuilder

proc requestTextLayout*(
  worker: AgentProxy[TextLayoutWorker],
  generation: uint64,
  layoutRect: Rect,
  source: string,
  runs: seq[TextAttributeRun],
  style: TextStyle,
  alignment: TextAlignment,
  wraps: bool,
  containers: seq[TextContainer],
  buildSnapshot: bool,
) {.signal.}

proc textLayoutFinished*(
  worker: TextLayoutWorker, layoutResult: SharedPtr[TextLayoutWorkerResult]
) {.signal.}

proc requestTextLayout(
    worker: TextLayoutWorker,
    generation: uint64,
    layoutRect: Rect,
    source: string,
    runs: seq[TextAttributeRun],
    style: TextStyle,
    alignment: TextAlignment,
    wraps: bool,
    containers: seq[TextContainer],
    buildSnapshot: bool,
) {.slot.} =
  var
    ownedSource = source
    ownedRuns = runs
    layoutResult = TextLayoutWorkerResult(generation: generation)
  let storage = newTextStorage(move ownedSource, move ownedRuns)
  layoutResult.arrangement = textLayout(layoutRect, storage, style, alignment, wraps)
  if buildSnapshot and not worker.snapshotBuilder.isNil:
    layoutResult.snapshot = worker.snapshotBuilder(
      layoutResult.arrangement, storage, containers, style, alignment
    )
    layoutResult.snapshotThreadId = getThreadId()
  emit worker.textLayoutFinished(newSharedPtr(unsafeIsolate(move layoutResult)))

proc newTextLayoutWorker*(
    snapshotBuilder: TextLayoutSnapshotBuilder
): AgentProxy[TextLayoutWorker] =
  var worker = TextLayoutWorker(snapshotBuilder: snapshotBuilder)
  result = worker.moveToThread(nimkitWorkerPool())
  connectThreaded(result, requestTextLayout, result, requestTextLayout)
