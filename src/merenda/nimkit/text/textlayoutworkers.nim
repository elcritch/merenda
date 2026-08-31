## Internal Sigils worker for expensive attributed-text reflow.

import std/[exitprocs, isolation]

import sigils/[core, threads]
import threading/smartptrs

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

import ../drawing
import ../foundation/types
import ../themes
import ./textstorage
import ./texttypes

type
  TextLayoutWorkerResult* = object
    generation*: uint64
    arrangement*: GlyphArrangement

  TextLayoutWorker* = ref object of AgentActor

var
  defaultTextLayoutPool {.threadvar.}: SigilThreadPoolPtr
  defaultTextLayoutPoolExitRegistered {.threadvar.}: bool

proc requestTextLayout*(
  worker: AgentProxy[TextLayoutWorker],
  generation: uint64,
  layoutRect: Rect,
  source: string,
  runs: seq[TextAttributeRun],
  style: TextStyle,
  alignment: TextAlignment,
  wraps: bool,
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
) {.slot.} =
  var
    ownedSource = source
    ownedRuns = runs
    layoutResult = TextLayoutWorkerResult(generation: generation)
  let storage = newTextStorage(move ownedSource, move ownedRuns)
  layoutResult.arrangement = textLayout(layoutRect, storage, style, alignment, wraps)
  emit worker.textLayoutFinished(newSharedPtr(unsafeIsolate(move layoutResult)))

proc stopDefaultTextLayoutPool() {.noconv.} =
  if not defaultTextLayoutPool.isNil:
    defaultTextLayoutPool.stop(immediate = true)
    defaultTextLayoutPool.join()
    defaultTextLayoutPool = nil

proc resolvedDefaultTextLayoutPool(): SigilThreadPoolPtr =
  startLocalThreadDefault()
  if defaultTextLayoutPool.isNil:
    defaultTextLayoutPool = newSigilThreadPool(workers = 2)
    defaultTextLayoutPool.start()
  if not defaultTextLayoutPoolExitRegistered:
    addExitProc(stopDefaultTextLayoutPool)
    defaultTextLayoutPoolExitRegistered = true
  defaultTextLayoutPool

proc newTextLayoutWorker*(): AgentProxy[TextLayoutWorker] =
  var worker = TextLayoutWorker()
  result = worker.moveToThread(resolvedDefaultTextLayoutPool())
  connectThreaded(result, requestTextLayout, result, requestTextLayout)
