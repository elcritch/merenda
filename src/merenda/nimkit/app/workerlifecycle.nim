## Application shutdown for NimKit's shared dispatchers.

from ../../foundation/backgroundworkers import
  registerBackgroundWorkerShutdownHook, shutdownBackgroundWorkers

when defined(features.merenda.terminal) or defined(features.merenda.kosmo):
  from terminex/workerthreads import shutdownTerminalWorkers

proc shutdownNimkitBackgroundWorkers*() {.noconv.} =
  ## Stop the terminal dispatcher before joining the Foundation workers.
  when defined(features.merenda.terminal) or defined(features.merenda.kosmo):
    registerBackgroundWorkerShutdownHook(shutdownTerminalWorkers)
  shutdownBackgroundWorkers()

type NimkitBackgroundWorkerLifetime* = object
  ## Join application workers before NimKit's module globals are destroyed.

proc `=destroy`*(lifetime: NimkitBackgroundWorkerLifetime) {.raises: [].} =
  discard lifetime
  try:
    shutdownNimkitBackgroundWorkers()
  except Exception:
    discard
