## Native terminal latency diagnostic. Run from the repository root:
## nim c -d:nimkitTerminalTrace tests/benchmark_terminal_native.nim
## tests/benchmark_terminal_native cmatrix terminal /tmp/terminal-trace.jsonl
## tests/benchmark_terminal_native ps kosmo /tmp/kosmo-trace.jsonl
## Uses the blocking application event loop and the normal automatic renderer.
## `present` means native presentation was submitted, not physical scanout.

when not defined(nimkitTerminalTrace):
  {.error: "compile with -d:nimkitTerminalTrace".}

import std/[json, monotimes, os, times]
import sigils/core
import merenda/nimkit/app/[animations, application, windows]
import merenda/nimkit/foundation/[terminaltrace, types]
import merenda/nimkit/terminal/terminalviews
import merenda/nimkit/responder/responders
import merenda/nimkit/view/views
import merenda/kosmo/application as kosmo
import terminex

type NativeTerminalProbe = ref object of Agent
  app: Application
  view: TerminalView
  window: Window
  frontend: KosmoApplication
  timer: Animation
  command: string
  ready: bool
  stage: int
  idleCpu: float
  idleStart: MonoTime
  activeCpu: float
  activeStart: MonoTime

proc advance(probe: NativeTerminalProbe) {.slot.}

proc schedule(probe: NativeTerminalProbe, milliseconds: int) =
  probe.timer = newAnimation(duration = initDuration(milliseconds = milliseconds))
  probe.timer.cadence = eventCadence()
  probe.timer.connect(finished, probe, advance)
  discard probe.app.startAnimation(probe.timer)

proc titleChanged(probe: NativeTerminalProbe, title: string) {.slot.} =
  if title == "trace-ready" and not probe.ready:
    probe.ready = true
    discard probe.app.stopAnimation(probe.timer)
    probe.schedule(1000)

proc advance(probe: NativeTerminalProbe) {.slot.} =
  case probe.stage
  of 0:
    doAssert probe.ready, "PTY readiness handshake did not arrive"
    probe.idleCpu = cpuTime()
    probe.idleStart = getMonoTime()
    recordTerminalTrace("idle-start")
    probe.schedule(1000)
  of 1:
    let wall = (getMonoTime() - probe.idleStart).inNanoseconds.float / 1e9
    echo "idle CPU percent of one core: ", (cpuTime() - probe.idleCpu) / wall * 100
    probe.activeCpu = cpuTime()
    probe.activeStart = getMonoTime()
    recordTerminalTrace("workload-start")
    probe.view.session().write(probe.command & "\n")
    probe.schedule(3000)
  else:
    let wall = (getMonoTime() - probe.activeStart).inNanoseconds.float / 1e9
    echo "active CPU percent of one core: ", (cpuTime() - probe.activeCpu) / wall * 100
    recordTerminalTrace("workload-end")
    probe.view.close()
    probe.app.stop()
  inc probe.stage

let args = commandLineParams()
doAssert args.len == 3, "expected: cmatrix|ps|burst terminal|kosmo output.jsonl"
doAssert args[0] in ["cmatrix", "ps", "burst"]
doAssert args[1] in ["terminal", "kosmo"]
let probe = NativeTerminalProbe(app: newApplication("Terminal latency probe"))
let options = initTerminalSpawnOptions(
  shell = "/bin/sh",
  command =
    "stty -echo; printf '\\033]2;trace-ready\\007'; IFS= read -r command; eval \"$command\"; IFS= read -r finish",
)
if args[0] == "cmatrix":
  let executable = findExe("cmatrix")
  doAssert executable.len > 0, "cmatrix must be installed"
  probe.command = "exec " & quoteShell(executable) & " -u 1"
elif args[0] == "burst":
  probe.command =
    "i=0; while [ $i -lt 10000 ]; do printf 'output-line-%s\\n' \"$i\"; i=$((i+1)); done; printf 'burst-finished\\n'"
else:
  probe.command = "i=0; while [ $i -lt 12 ]; do ps; i=$((i+1)); sleep 0.15; done"
if args[1] == "kosmo":
  probe.frontend = newKosmoApplication(app = probe.app)
  probe.frontend.show()
  doAssert probe.frontend.openTerminal(options)
  probe.window = probe.frontend.window
  probe.view = TerminalView(probe.frontend.editorGroups()[0].pane.contentView)
else:
  probe.view = newTerminalView(options, frame = rect(0, 0, 1000, 640))
  probe.window = newWindow("Terminal latency probe", frame = rect(140, 100, 1000, 640))
  discard probe.app.showWindow(probe.window, probe.view)
discard probe.window.makeFirstResponder(nil)
probe.view.connect(terminalTitleDidChange, probe, titleChanged)
# The title callback starts warmup; this timer is only a readiness deadline.
probe.schedule(5000)
try:
  probe.app.run()
finally:
  probe.view.close()
  if not probe.frontend.isNil:
    probe.frontend.close()
  probe.window.close()
let trace = takeTerminalTrace()
doAssert trace.dropped == 0, "trace capacity exceeded"
let output = open(args[2], fmWrite)
for event in trace.events:
  output.writeLine $(
    %*{
      "stage": event.stage,
      "ticks": event.ticks,
      "thread": event.thread,
      "identity": event.identity,
      "detail": event.detail,
    }
  )
output.close()
echo "saved ", trace.events.len, " events to ", args[2]
