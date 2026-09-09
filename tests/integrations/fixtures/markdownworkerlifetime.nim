## Imported before markdownparsing so this exit check runs after its guard,
## but before nim-markdown's parser globals are destroyed.
import std/atomics
import markdown
import sigils/threads

export markdown

var
  workerStarted*: Atomic[bool]
  exitStarted*: Atomic[bool]
  workerFinished*: Atomic[bool]
  workerPool*: SigilThreadPoolPtr

type CheckWorkerExit = object

proc `=destroy`(check: var CheckWorkerExit) =
  discard check
  if workerStarted.load(moAcquire):
    doAssert not workerPool.isNil and workerPool[].stopping,
      "Markdown module guard must stop the shared worker pool"
    doAssert workerFinished.load(moAcquire),
      "background worker must finish before imported parser globals are destroyed"

var checkWorkerExit {.used.}: CheckWorkerExit
