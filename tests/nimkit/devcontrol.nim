import std/[json, options, unittest]
import sigils/selectors
import sigils/rpcs/jsonrpc
import merenda/nimkit/devcontrol/protocol

suite "Development control protocol":
  test "typed requests round trip with stable wire names":
    let request = DevRequest(
      id: "input-1",
      command: dcPointer,
      window: "w2",
      action: "click",
      x: 12.5,
      y: 20,
      modifiers: @["shift"],
    )
    let parsed = parseDevRequest($request.requestJson())
    check parsed.id == request.id
    check parsed.command == dcPointer
    check parsed.x == 12.5
    check parsed.modifiers == @["shift"]
    check request.requestJson()["command"].getStr() == "pointer"

  test "invalid types and unsupported commands fail before GUI dispatch":
    for input in [
      "[]", "null", "{", "{\"version\":true}", "{\"command\":true}",
      "{\"command\":\"text\",\"window\":\"w1\",\"text\":3}",
      "{\"command\":\"pointer\",\"window\":\"w1\",\"action\":\"click\",\"x\":1e100,\"y\":0}",
    ]:
      expect DevProtocolError:
        discard parseDevRequest(input)
    try:
      discard parseDevRequest("{\"version\":1,\"command\":\"quit\"}")
      check false
    except DevProtocolError as error:
      check error.code == "unknown_command"

  test "Sigils JSON RPC routes typed requests and validates parameters":
    let endpoint = DynamicAgent()
    proc invoke(self: DynamicAgent, request: DevRequest): JsonNode =
      request.requestJson()

    discard endpoint.addMethod(DevRequestSelector, toDynamicMethod(invoke))
    let adapter = newJsonRpcAdapter()
    adapter.registerSelector("merenda", endpoint, DevRequestSelector)
    let request = DevRequest(id: "rpc-1", command: dcInfo)
    let reply = parseJson(adapter.handleJsonRpc($request.rpcRequestJson()).get())
    check reply["jsonrpc"].getStr() == "2.0"
    check reply["id"].getStr() == "rpc-1"
    check reply["result"]["command"].getStr() == "info"
    let invalid = parseJson(
      adapter
        .handleJsonRpc(
          """{"jsonrpc":"2.0","id":7,"method":"merenda.request","params":{"command":"text","window":"w1","text":3}}"""
        )
        .get()
    )
    check invalid["error"]["code"].getInt() == RpcInvalidParams
    let missing = parseJson(
      adapter
        .handleJsonRpc("""{"jsonrpc":"2.0","id":8,"method":"merenda.missing"}""")
        .get()
    )
    check missing["error"]["code"].getInt() == RpcMethodNotFound

  test "errors and successful unhandled events have distinct representations":
    let failure = devFailure("r1", "window_not_found", "Closed").responseJson()
    check not failure["ok"].getBool()
    check failure["id"].getStr() == "r1"
    check failure["error"]["code"].getStr() == "window_not_found"
    let success = devSuccess("r2", %*{"handled": false}).responseJson()
    check success["ok"].getBool()
    check not success["result"]["handled"].getBool()

when defined(merenda.devControl):
  import merenda/nimkit/app/backend

  suite "Development capture delivery":
    test "ordinary render acknowledgements cannot replace captured pixels":
      let queue = newThreadHostEventQueue()
      queue.post(
        ThreadHostEvent(
          kind: theRendered,
          renderId: 1,
          capture: RenderCapture(id: 7, png: "owned pixels"),
        )
      )
      queue.post(ThreadHostEvent(kind: theRendered, renderId: 2))
      var event: ThreadHostEvent
      require queue.poll(event)
      check event.renderId == 1
      check event.capture.png == "owned pixels"
      require queue.poll(event)
      check event.renderId == 2
      check not queue.poll(event)
