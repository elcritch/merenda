## Versioned development-control messages shared by apps, CLI clients and adapters.
import std/[json, math, strutils]
import sigils/selectors
import sigils/rpcs/jsonrpc

export jsonrpc

const
  DevProtocolVersion* = 1
  DevMaxRequestBytes* = 128 * 1024
  DevMaxResponseBytes* = 32 * 1024 * 1024

type
  DevCommand* = enum
    dcInfo
    dcWindows
    dcScreenshot
    dcPointer
    dcKey
    dcText
    dcThemeLoad
    dcThemeReload

  DevRequest* = object
    id*: string
    command*: DevCommand
    window*: string
    action*: string
    x*, y*, deltaX*, deltaY*: float32
    button*: string
    key*: string
    text*: string
    file*: string
    modifiers*: seq[string]

  DevResponse* = object
    id*: string
    result*: JsonNode
    errorCode*, errorMessage*: string

  DevProtocolError* = object of CatchableError
    code*: string

  DevPendingQuery* = object
    token*: string

let
  DevRequestSelector* = selector[DevRequest, JsonNode]("request")
  DevResultSelector* = selector[DevPendingQuery, JsonNode]("result")

const CommandNames = [
  "info", "windows", "screenshot", "pointer", "key", "text", "theme-load",
  "theme-reload",
]

proc reject(code, message: string) {.noreturn.} =
  let error = newException(DevProtocolError, message)
  error.code = code
  raise error

proc stringField(node: JsonNode, name: string, required = false): string =
  if not node.hasKey(name):
    if required:
      reject("invalid_request", "Missing string: " & name)
    return
  if node[name].kind != JString:
    reject("invalid_request", "Expected string: " & name)
  node[name].getStr()

proc numberField(node: JsonNode, name: string, required = false): float32 =
  if not node.hasKey(name):
    if required:
      reject("invalid_request", "Missing number: " & name)
    return
  if node[name].kind notin {JInt, JFloat}:
    reject("invalid_request", "Expected number: " & name)
  let value = node[name].getFloat()
  if value.classify in {fcNan, fcInf, fcNegInf} or abs(value) > 1_000_000:
    reject("invalid_request", "Number out of range: " & name)
  value.float32

proc parseDevRequest*(line: string): DevRequest =
  ## Validates the wire format before application dispatch or enum conversion.
  if line.len > DevMaxRequestBytes:
    reject("invalid_request", "Request is too large")
  var root: JsonNode
  try:
    root = parseJson(line)
  except JsonParsingError:
    reject("invalid_request", "Expected a JSON object")
  if root.kind != JObject:
    reject("invalid_request", "Expected a JSON object")
  result.id = root.stringField("id")
  let command = root.stringField("command", true)
  var found = false
  for candidate in DevCommand:
    if CommandNames[candidate.ord] == command:
      result.command = candidate
      found = true
  if not found:
    reject("unknown_command", "Unknown command: " & command)
  let params = root
  if result.command notin {dcInfo, dcWindows, dcThemeLoad, dcThemeReload}:
    result.window = params.stringField("window", true)
  result.file = params.stringField("file", result.command == dcThemeLoad)
  if result.command == dcThemeLoad and result.file.len == 0:
    reject("invalid_request", "Expected CSS file path")
  result.action = params.stringField("action")
  result.text = params.stringField("text", result.command == dcText)
  result.key = params.stringField("key", result.command == dcKey)
  result.button = params.stringField("button")
  result.x = params.numberField("x", result.command == dcPointer)
  result.y = params.numberField("y", result.command == dcPointer)
  result.deltaX = params.numberField("deltaX")
  result.deltaY = params.numberField("deltaY")
  if params.hasKey("modifiers"):
    if params["modifiers"].kind != JArray:
      reject("invalid_request", "Expected modifiers array")
    for modifier in params["modifiers"]:
      if modifier.kind != JString or
          modifier.getStr() notin ["shift", "control", "option", "command"]:
        reject("invalid_request", "Unknown modifier")
      result.modifiers.add modifier.getStr()
  if result.command == dcPointer:
    if result.action notin ["move", "down", "up", "drag", "click", "scroll"]:
      reject("invalid_request", "Unknown pointer action")
    if result.button notin ["", "primary", "secondary", "other"]:
      reject("invalid_request", "Unknown pointer button")
  if result.command == dcKey and result.action notin ["down", "up"]:
    reject("invalid_request", "Unknown key action")

proc requestJson*(request: DevRequest): JsonNode =
  ## Named parameters for the registered merenda.request selector.
  %*{
    "id": request.id,
    "command": CommandNames[request.command.ord],
    "window": request.window,
    "action": request.action,
    "x": request.x,
    "y": request.y,
    "deltaX": request.deltaX,
    "deltaY": request.deltaY,
    "button": request.button,
    "key": request.key,
    "text": request.text,
    "file": request.file,
    "modifiers": request.modifiers,
  }

proc fromJsonHook*(request: var DevRequest, node: JsonNode) =
  request = parseDevRequest($node)

proc toJsonHook*(request: DevRequest): JsonNode =
  request.requestJson()

proc rpcRequestJson*(request: DevRequest): JsonNode =
  ## Standard JSON-RPC request accepted by Sigils' registered endpoint.
  newJsonRpcRequest(%request.id, "merenda.request", request.requestJson())

proc devSuccess*(id: string, payload: JsonNode): DevResponse =
  DevResponse(id: id, result: payload)

proc devFailure*(id, code, message: string): DevResponse =
  DevResponse(id: id, errorCode: code, errorMessage: message)

proc responseJson*(response: DevResponse): JsonNode =
  result = %*{
    "version": DevProtocolVersion, "id": response.id, "ok": response.errorCode.len == 0
  }
  if response.errorCode.len > 0:
    result["error"] = %*{"code": response.errorCode, "message": response.errorMessage}
  else:
    result["result"] =
      if response.result.isNil:
        newJNull()
      else:
        response.result
