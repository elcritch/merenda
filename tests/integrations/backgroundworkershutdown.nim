## An in-flight parser must finish during Nim global destruction, before the
## parser's globals disappear. C atexit hooks are too late under ARC/ORC.
import std/[atomics, monotimes, os, strtabs, strutils, times, unittest]

import sigils/[core, threads]
import terminex/workerthreads
import merenda/nimkit/foundation/[backgroundprocesses, backgroundworkers]
import ./fixtures/markdownworkerlifetime
import merenda/nimkit/text/markdownparsing

type
  ExitParseWorker = ref object of AgentActor
  ReleaseWorkerAtExit = object

proc `=destroy`(release: var ReleaseWorkerAtExit) =
  discard release
  exitStarted.store(true, moRelease)

var
  # Keep a lifetime guard in this module so the shared integration runner
  # stops the worker pool before the fixture checks it during teardown.
  integrationWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
  releaseWorkerAtExit {.used.}: ReleaseWorkerAtExit

proc releaseWorkerForFailedExit*() =
  ## quit bypasses the module destructor that normally releases this worker.
  if workerStarted.load(moAcquire):
    exitStarted.store(true, moRelease)
    shutdownNimkitBackgroundWorkers()

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
  test "explicit shutdown joins readiness and timer dispatchers and allows repeated shutdown":
    discard nimkitTimerThread()
    discard terminalWorkerThread()
    shutdownNimkitBackgroundWorkers()
    shutdownNimkitBackgroundWorkers()

  test "a failed test releases the active worker before process exit":
    if getEnv("MERENDA_TEST_FORCE_SHUTDOWN_FAILURE") != "1":
      let environment = newStringTable(modeCaseSensitive)
      for key, value in envPairs():
        environment[key] = value
      environment["MERENDA_TEST_FORCE_SHUTDOWN_FAILURE"] = "1"
      let child = runBackgroundCommand(
        getAppFilename(),
        [
          "NimKit direct-import worker shutdown::joins active parsing before dependency globals are destroyed"
        ],
        timeoutMilliseconds = 60_000,
        environment = environment,
        diagnosticName = "Shutdown failure regression",
      )
      check child.output != "Shutdown failure regression timed out"
      check child.exitCode == 1
      check "Check failed: false" in child.output
      check "main thread did not begin shutdown" notin child.output

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
    if getEnv("MERENDA_TEST_FORCE_SHUTDOWN_FAILURE") == "1":
      check false
    # Deliberately leave the task active. ReleaseWorkerAtExit lets it parse
    # during teardown; CheckWorkerExit asserts that the module guard joined it.
