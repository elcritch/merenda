## Standalone Windows coverage for shared ownership and contended atomics.

when isMainModule:
  import std/[atomics, monotimes, os, times]
  import threading/smartptrs
  import sigils/[threadChronos, threadPool]

  when not defined(windows):
    {.error: "Compile this fixture for Windows".}
  var destructions: Atomic[int]

  type Tracked = object
    value: int

  proc `=destroy`(value: var Tracked) =
    if value.value != 0:
      discard destructions.fetchAdd(1)

  var before: int
  block:
    let owner = newSharedPtr(Tracked(value: 42))
    before = destructions.load()
    block:
      let copy = owner
      doAssert copy[].value == 42
    doAssert owner[].value == 42
    doAssert destructions.load() == before
  doAssert destructions.load() == before + 1

  const
    workerCount = 4
    iterations = 20_000
  var completed: Atomic[int]

  proc increment(counter: ptr Atomic[int]) {.thread.} =
    for index in 0 ..< iterations:
      let previous = counter[].fetchAdd(1, moRelaxed)
      doAssert previous >= 0 and previous < workerCount * iterations
    discard completed.fetchAdd(1, moRelease)

  var
    counter: Atomic[int]
    workers: array[workerCount, Thread[ptr Atomic[int]]]
  for worker in workers.mitems:
    createThread(worker, increment, addr counter)
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while completed.load(moAcquire) != workerCount and getMonoTime() < deadline:
    sleep(1)
  doAssert completed.load(moAcquire) == workerCount
  joinThreads(workers)
  doAssert counter.load() == workerCount * iterations
  let pool = newSigilThreadPool(workers = 2)
  pool.start()
  pool.stop()
  pool.join()
  let dispatcher = newSigilChronosThread()
  dispatcher.start()
  dispatcher.stop()
  dispatcher.join()
  echo "Windows shared ownership and contended atomic increments passed"
