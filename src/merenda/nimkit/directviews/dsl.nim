## Direct typed widget composition with structural slots and keyed siblings.
import std/[macros, strutils]
from sigils/selectors import DynamicAgent
from ../core/selectors import ActionSelector
import ../core/types
import ../view/views
import ../containers/stackviews
import ../controls/buttons
import ../text/textfields
import ./actions
import ./runtime
export runtime

proc takeActionParameter(params, callback: NimNode): tuple[name, typ: NimNode] =
  if params.len < 2:
    error(
      "DirectView handlers take a typed sender, receiver, and optional context",
      callback,
    )
  let parameter = params[1]
  if parameter.kind != nnkIdentDefs or parameter[^2].kind == nnkEmpty:
    error("Specify a type for the DirectView sender and receiver parameters", parameter)
  result = (parameter[0], parameter[^2])
  if parameter.len == 3:
    params.del(1)
  else:
    parameter.del(0)

proc directAction(widget, receiver, context, callback: NimNode): NimNode =
  if callback.kind notin {nnkDo, nnkLambda}:
    error("DirectView actions with explicit context require an inline proc", callback)
  let
    handler = callback.copyNimTree()
    params = handler.params
    (senderName, senderType) = takeActionParameter(params, callback)
    (receiverName, receiverType) = takeActionParameter(params, callback)
    sender = ident(genSym(nskParam, "directViewSender").repr)
    boundReceiver = ident(genSym(nskParam, "directViewReceiver").repr)
    body = handler.body
  params.insert(1, newIdentDefs(boundReceiver, receiver.getTypeInst()))
  params.add newIdentDefs(sender, bindSym"DynamicAgent")
  handler.body = quote:
    if `sender` of `senderType`:
      let
        `senderName` = `senderType`(`sender`)
        `receiverName`: `receiverType` = `boundReceiver`
      `body`

  let action = newCall(bindSym"viewAction", receiver)
  if context.kind != nnkEmpty:
    action.add context
  action.add handler
  result = quote:
    when typeof(`widget`) is `senderType`:
      `action`
    else:
      {.error: "The first DirectView handler parameter must have the widget's type".}

proc bindDirectAction[R: Responder](
    _: View, receiver: R, action: ActionSelector
): ViewAction =
  initViewAction(action, receiver)

proc invokeDirectHandler[W: View, R: Responder, S, O: DynamicAgent](
    receiver: R, handler: proc(sender: S, owner: O) {.nimcall.}, sender: DynamicAgent
) {.nimcall.} =
  if not handler.isNil and sender of W:
    handler(W(sender), receiver)

proc bindDirectAction[W: View, R: Responder, S, O: DynamicAgent](
    _: W, receiver: R, handler: proc(sender: S, owner: O) {.nimcall.}
): ViewAction =
  viewAction(receiver, handler, invokeDirectHandler[W, R, S, O])

macro directViewAction(widget, receiver: typed, handler: untyped): untyped =
  if handler.kind in {nnkDo, nnkLambda}:
    directAction(widget, receiver, newEmptyNode(), handler)
  else:
    newCall(bindSym"bindDirectAction", widget, receiver, handler)

macro directViewAction(widget, receiver, context: typed, handler: untyped): untyped =
  directAction(widget, receiver, context, handler)

template onAction*(button: Button, receiver: typed, handler: untyped) =
  ## Register a selector or sender-first handler during DirectView composition.
  let widget = button
  widget.setAction(directViewAction(widget, receiver, handler))

template onAction*(button: Button, receiver, context: typed, handler: untyped) =
  let widget = button
  widget.setAction(directViewAction(widget, receiver, context, handler))

template onChange*(field: TextField, receiver: typed, handler: untyped) =
  ## Register a selector or sender-first text change handler during composition.
  let widget = field
  widget.setChange(directViewAction(widget, receiver, handler))

template onChange*(field: TextField, receiver, context: typed, handler: untyped) =
  let widget = field
  widget.setChange(directViewAction(widget, receiver, context, handler))

macro viewBody*(session, body: untyped): untyped =
  var slot = 0
  let root = genSym(nskLet, "root")
  proc statements(body, parent, key: NimNode): NimNode
  proc statements(body, parent, key: NimNode): NimNode =
    result = newStmtList()
    for item in body:
      if item.kind in {nnkCall, nnkCommand} and item[0].eqIdent("component"):
        if item.len < 2:
          error("component requires a builder proc and its arguments", item)
        inc slot
        let id =
          if key.kind == nnkEmpty:
            newLit("slot:" & $slot)
          else:
            key
        let node = genSym(nskLet, "component")
        let kind = newLit("component:" & item[1].repr)
        let call = newCall(item[1], node)
        for i in 2 ..< item.len:
          call.add item[i]
        result.add quote do:
          block:
            let `node` = componentChild(`parent`, `id`, `kind`)
            try:
              `call`
            finally:
              endComponent(`node`)
      elif item.kind in {nnkCall, nnkCommand} and item.len >= 1 and
          item[0].kind in {nnkIdent, nnkSym} and
          (item[0].strVal[0].isUpperAscii or item[0].eqIdent("keyed")):
        let name = item[0].strVal
        if name.normalize == "keyed":
          if item.len != 3 or item[^1].kind != nnkStmtList:
            error("Keyed requires one identity and a block", item)
          let k = genSym(nskLet, "key")
          let nested = statements(item[^1], parent, k)
          let keyExpr = item[1]
          result.add quote do:
            block:
              let `k` = "key:" & $`keyExpr`
              `nested`
          continue
        inc slot
        let id =
          if key.kind == nnkEmpty:
            newLit("slot:" & $slot)
          else:
            key
        let node = genSym(nskLet, "node")
        let factory =
          case name.normalize
          of "vstack":
            newCall(bindSym"newStackView")
          of "hstack":
            newCall(bindSym"newStackView", bindSym"laHorizontal")
          of "label":
            newCall(bindSym"newLabel")
          of "button":
            newCall(bindSym"newButton")
          of "textfield":
            newCall(bindSym"newTextField")
          else:
            newCall(ident("new" & name))
        let hasBody = item[^1].kind == nnkStmtList
        let argsEnd =
          if hasBody:
            item.len - 1
          else:
            item.len
        let configuration = newStmtList()
        if name.normalize == "button":
          var hasNamed = false
          for i in 1 ..< argsEnd:
            if item[i].kind == nnkExprEqExpr:
              hasNamed = true
            elif hasNamed:
              error(
                "Button positional arguments must precede named properties", item[i]
              )
        let buttonTitle =
          name.normalize == "button" and argsEnd > 1 and item[1].kind != nnkExprEqExpr
        if buttonTitle:
          for i in 2 ..< argsEnd:
            if item[i].kind == nnkExprEqExpr and item[i][0].eqIdent("title"):
              error(
                "Button title cannot be supplied both positionally and by name", item[i]
              )
          # Reserve the constructor's title position for any remaining arguments.
          factory.add newLit("")
        for i in 1 ..< argsEnd:
          let arg = item[i]
          if buttonTitle and i == 1:
            let assignment =
              newAssignment(newDotExpr(ident"this", ident"title"), arg.copyNimTree())
            assignment.copyLineInfo(arg)
            configuration.add assignment
          elif arg.kind == nnkExprEqExpr:
            # Named properties use exactly the same setter/patch path as the body.
            let assignment = newAssignment(
              newDotExpr(ident"this", arg[0].copyNimTree()), arg[1].copyNimTree()
            )
            assignment.copyLineInfo(arg)
            configuration.add assignment
          else:
            factory.add arg.copyNimTree()
        if hasBody:
          for statement in item[^1]:
            configuration.add statement.copyNimTree()
        let widgetType = newLit(name.normalize)
        let context = genSym(nskLet, "context")
        let nested = statements(configuration, context, newEmptyNode())
        result.add quote do:
          block:
            let `node` = child(
              `parent`,
              `id`,
              `widgetType`,
              proc(): auto =
                `factory`,
            )
            let this {.inject.} = typeof(`factory`)(`node`.view)
            let bindingScope {.inject.} = `node`.bindings
            composeBody(`node`, `context`):
              `nested`
      elif item.kind in {nnkCall, nnkCommand} and item[0].kind == nnkDotExpr and
          item[0][0].eqIdent("bindingScope"):
        if item[0][1].eqIdent("bindTextField"):
          error(
            "Call this.bindTextField for this field or bindTextField on its owner", item
          )
        elif item[0][1].eqIdent("bindValue"):
          error("Call this.bindValue for this widget or bindValue on its owner", item)
        result.add item.copyNimTree()
      elif item.kind in {nnkForStmt, nnkBlockStmt}:
        let copy = item.copyNimTree()
        copy[^1] = statements(item[^1], parent, key)
        result.add copy
      elif item.kind in {nnkIfStmt, nnkWhenStmt, nnkCaseStmt}:
        let copy = item.copyNimTree()
        let start = if item.kind == nnkCaseStmt: 1 else: 0
        for i in start ..< copy.len:
          copy[i][^1] = statements(item[i][^1], parent, key)
        result.add copy
      else:
        result.add item.copyNimTree()

  let content = statements(body, root, newEmptyNode())
  result = quote:
    block:
      composeBody(`session`, `root`):
        `content`
