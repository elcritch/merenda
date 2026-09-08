## An in-flight parser must finish during Nim global destruction, before the
## parser's globals disappear. C atexit hooks are too late under ARC/ORC.
import std/[atomics, monotimes, os, times, unittest]

import sigils/[core, threads]
import merenda/nimkit/foundation/backgroundworkers
import ./fixtures/markdownworkerlifetime
import merenda/nimkit/text/markdownparsing

type
  ExitParseWorker = ref object of AgentActor
  ReleaseWorkerAtExit = object

proc `=destroy`(release: var ReleaseWorkerAtExit) =
  discard release
  exitStarted.store(true, moRelease)

var releaseWorkerAtExit {.used.}: ReleaseWorkerAtExit

proc parseAtExit(worker: AgentProxy[ExitParseWorker]) {.signal.}

proc parseAtExit(worker: ExitParseWorker) {.slot.} =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  workerStarted.store(true, moRelease)
  while not exitStarted.load(moAcquire) and getMonoTime() < deadline:
    sleep(1)
  doAssert exitStarted.load(moAcquire), "main thread did not begin shutdown"
  let config = initCommonmarkConfig()
  for index in 0 ..< 1000:
    let root =
      parseMarkdownRoot("![image](image.png) [link](https://example.com)", config)
    doAssert not root.children.head.isNil
  workerFinished.store(true, moRelease)

suite "NimKit direct-import worker shutdown":
  test "explicit shutdown joins the timer and allows repeated shutdown":
    discard nimkitTimerThread()
    shutdownNimkitBackgroundWorkers()
    shutdownNimkitBackgroundWorkers()

  test "joins active parsing before dependency globals are destroyed":
    var actor = ExitParseWorker()
    workerPool = nimkitWorkerPool()
    let worker = actor.moveToThread(workerPool)
    connectThreaded(worker, parseAtExit, worker, parseAtExit)
    emit worker.parseAtExit()
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not workerStarted.load(moAcquire) and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(1)
    require workerStarted.load(moAcquire)
    check not workerFinished.load(moAcquire)
    # Deliberately leave the task active. ReleaseWorkerAtExit lets it parse
    # during teardown; CheckWorkerExit asserts that the module guard joined it.
