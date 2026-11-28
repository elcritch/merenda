## Defer binding disconnections while a source's synchronous signal is in flight.
## All operations occur on the owning thread.
import sigils/core

type DeferredSourceWork = object
  source: Agent
  work: proc() {.closure.}

var activeSources {.threadvar.}: seq[Agent]
var deferredSourceWork {.threadvar.}: seq[DeferredSourceWork]

proc beginSourceDispatch*(source: Agent) =
  activeSources.add source

proc sourceDispatchActive*(source: Agent): bool =
  source in activeSources

proc deferSourceWork*(source: Agent, work: sink proc() {.closure.}): bool =
  if source in activeSources:
    deferredSourceWork.add DeferredSourceWork(source: source, work: work)
    result = true

proc endSourceDispatch*(source: Agent) =
  doAssert activeSources.len > 0 and activeSources[^1] == source
  activeSources.setLen(activeSources.len - 1)
  if source notin activeSources:
    var pending: seq[proc() {.closure.}]
    var remaining: seq[DeferredSourceWork]
    for item in deferredSourceWork:
      if item.source == source:
        pending.add item.work
      else:
        remaining.add item
    deferredSourceWork = move remaining
    for work in pending:
      work()
