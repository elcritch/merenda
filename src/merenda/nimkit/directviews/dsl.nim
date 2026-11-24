## Direct typed widget composition with structural slots and keyed siblings.
import std/[macros, strutils]
from sigils/selectors import DynamicAgent
import ../foundation/types
import ../view/views
import ../containers/stackviews
import ../controls/buttons
import ../text/textfields
import ../declarative/actions
import ./runtime
export runtime

proc actionExpression(call: NimNode): NimNode =
  let legacy = newCall(bindSym"viewAction")
  for i in 1 ..< call.len:
    legacy.add call[i]
  let handler = call[^1]
  if handler.kind notin {nnkDo, nnkLambda} or handler.params.len < 2:
    return legacy
  let first = handler.params[1]
  if first.kind != nnkIdentDefs or first[^2].kind == nnkEmpty or
      not (first[0].eqIdent("self") or first[0].eqIdent("this")):
    return legacy

  let
    self = first[0]
    senderType = first[^2]
    sender = ident(genSym(nskParam, "directViewSender").repr)
    widget = ident"this"
    body = handler.body
    adapted = handler.copyNimTree()
    params = newNimNode(nnkFormalParams).add(handler.params[0])
  if first.len > 3:
    let remaining = first.copyNimTree()
    remaining.del(0)
    params.add remaining
  for i in 2 ..< handler.params.len:
    params.add handler.params[i]
  params.add newIdentDefs(sender, bindSym"DynamicAgent")
  adapted.params = params
  adapted.body = quote:
    if `sender` of `senderType`:
      let `self` = `senderType`(`sender`)
      `body`

  let typed = legacy.copyNimTree()
  typed[^1] = adapted
  result = quote:
    when typeof(`widget`) is `senderType` and not compiles(`legacy`):
      `typed`
    else:
      `legacy`

macro viewBody*(session, body: untyped): untyped =
  var slot = 0
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
      elif item.kind == nnkAsgn and item[0].kind == nnkDotExpr and
          item[0][0].eqIdent("this") and item[0][1].eqIdent("stringValue"):
        result.add newCall(bindSym"patchText", parent, ident"this", item[1])
      elif item.kind in {nnkCall, nnkCommand} and item[0].eqIdent("arrangedSizing"):
        if item.len != 2:
          error("arrangedSizing requires one sizing policy", item)
        result.add newAssignment(newDotExpr(parent, ident"sizing"), item[1])
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
      elif item.kind in {nnkCall, nnkCommand} and
          (item[0].eqIdent("onAction") or item[0].eqIdent("onChange")):
        let action = actionExpression(item)
        let setter =
          if item[0].eqIdent("onAction"):
            bindSym"setAction"
          else:
            bindSym"setChange"
        result.add newCall(setter, parent, ident"this", action)
      else:
        result.add item.copyNimTree()

  let root = genSym(nskLet, "root")
  let content = statements(body, root, newEmptyNode())
  result = quote:
    block:
      composeBody(`session`, `root`):
        `content`
