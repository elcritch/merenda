## Direct typed widget composition with structural slots and keyed siblings.
import std/[macros, strutils]
import ../foundation/types
import ../view/views
import ../containers/stackviews
import ../controls/buttons
import ../text/textfields
import ../declarative/actions
import ./runtime
export runtime

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
      elif item.kind in {nnkCall, nnkCommand} and item.len >= 2 and
          item[0].kind in {nnkIdent, nnkSym} and item[^1].kind == nnkStmtList and
          (item[0].strVal[0].isUpperAscii or item[0].eqIdent("keyed")):
        let name = item[0].strVal
        if name.normalize == "keyed":
          if item.len != 3:
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
        for i in 1 ..< item.len - 1:
          factory.add item[i].copyNimTree()
        let widgetType = newLit(name.normalize)
        let nested = statements(item[^1], node, newEmptyNode())
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
            discard beginUpdate(`node`)
            try:
              `nested`
            finally:
              endUpdate(`node`)
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
        let action = newCall(bindSym"viewAction")
        for i in 1 ..< item.len:
          action.add item[i]
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
      let `root` = beginUpdate(`session`)
      try:
        `content`
      finally:
        endUpdate(`session`)
