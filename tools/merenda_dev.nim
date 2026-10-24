## Small command-line client; no GUI dependencies or window-system permissions.
import std/[base64, json, os, strutils]
import merenda/nimkit/devcontrol/[protocol, transport]

const Usage = """Usage: merenda-dev (--pid PID | --socket PATH) COMMAND [options]
Commands: info, windows, screenshot, pointer, key, text, theme-load, theme-reload
Options:
  --window ID       Target ID returned by windows
  --file PATH       CSS file to load; theme-reload rereads the last loaded file
  --output PATH     Write screenshot PNG in this client process
  --action NAME     pointer: move/down/up/drag/click/scroll; key: down/up
  --x N --y N       Logical content coordinates
  --delta-x N --delta-y N   Scroll deltas
  --button NAME     primary/secondary/other
  --key NAME        e.g. a, enter, arrowleft, escape
  --text TEXT       Committed text
  --modifiers LIST  Comma-separated shift/control/option/command
  --timeout MS      Request deadline (default 15000)
A timeout may mean input was already delivered. Mutating requests are never retried.
"""

proc main() =
  let arguments = commandLineParams()
  var request = DevRequest(id: "cli", command: dcInfo)
  var socketPath, output: string
  var pid, targets: int
  var timeout = 15000
  var commandFound = false
  var index = 0
  proc value(): string =
    inc index
    if index >= arguments.len:
      raise newException(ValueError, "Missing option value")
    arguments[index]

  while index < arguments.len:
    let argument = arguments[index]
    case argument
    of "--help", "-h":
      echo Usage
      return
    of "--pid":
      pid = parseInt(value())
      if pid <= 0:
        raise newException(ValueError, "PID must be positive")
      inc targets
    of "--socket":
      socketPath = value()
      inc targets
    of "--window":
      request.window = value()
    of "--file":
      request.file = absolutePath(value())
    of "--output":
      output = value()
    of "--action":
      request.action = value()
    of "--x":
      request.x = parseFloat(value()).float32
    of "--y":
      request.y = parseFloat(value()).float32
    of "--delta-x":
      request.deltaX = parseFloat(value()).float32
    of "--delta-y":
      request.deltaY = parseFloat(value()).float32
    of "--button":
      request.button = value()
    of "--key":
      request.key = value()
    of "--text":
      request.text = value()
    of "--modifiers":
      request.modifiers = value().split(',')
    of "--timeout":
      timeout = parseInt(value())
    else:
      if commandFound:
        raise newException(ValueError, "Unexpected argument: " & argument)
      request.command =
        case argument
        of "info":
          dcInfo
        of "windows":
          dcWindows
        of "screenshot":
          dcScreenshot
        of "pointer":
          dcPointer
        of "key":
          dcKey
        of "text":
          dcText
        of "theme-load":
          dcThemeLoad
        of "theme-reload":
          dcThemeReload
        else:
          raise newException(ValueError, "Unknown command: " & argument)
      commandFound = true
    inc index
  if targets != 1 or not commandFound:
    raise
      newException(ValueError, "Specify one --pid or --socket and a command\n" & Usage)
  if pid > 0:
    socketPath = devSocketPath(pid.Positive)
  # Apply the same validation locally as the server.
  request = parseDevRequest($request.requestJson())
  var response = sendDevRequest(socketPath, request, timeout)
  if response["ok"].getBool() and request.command == dcScreenshot and output.len > 0:
    writeFile(output, decode(response["result"]["data"].getStr()))
    response["result"].delete("data")
    response["result"]["output"] = %output
  echo response
  if not response["ok"].getBool():
    quit(1)

when isMainModule:
  try:
    main()
  except CatchableError as error:
    stderr.writeLine(error.msg)
    quit(1)
