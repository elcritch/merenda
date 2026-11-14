## `viewBody` is syntax sugar over typed ViewSpec constructors and ordinary Nim control flow.
import std/[macros, strutils]
import ./descriptions
export descriptions

proc atSlot(spec: ViewSpec, slot: int): ViewSpec =
  result = spec
  result.slot = slot

proc onlySpec(children: seq[ViewSpec]): ViewSpec =
  if children.len != 1:
    raise newException(ValueError, "viewBody and keyed blocks require exactly one root")
  children[0]

macro viewBody*(body: untyped): untyped =
  ## Build a value description. Supports if/when/case, for, block, let/var and
  ## ordinary helper procs. Built-in nodes use capitalized type names;
  ## repeated siblings require explicit keys.
  var nextSlot = 0
  proc collect(body, output: NimNode): NimNode
  proc children(body: NimNode): NimNode =
    let output = genSym(nskVar, "children")
    let statements = collect(body, output)
    result = quote:
      block:
        var `output`: seq[ViewSpec]
        `statements`
        `output`

  proc expression(node: NimNode): NimNode =
    result = node.copyNimTree()
    if node.kind in {nnkCall, nnkCommand} and node[0].kind == nnkIdent:
      let spelling = node[0].strVal
      let name = node[0].strVal.normalize()
      if name in ["vstack", "hstack", "label", "button", "textfield"] and
          not spelling[0].isUpperAscii:
        error(
          "viewBody nodes require capitalized type names: VStack, HStack, Label, Button, TextField",
          node[0],
        )
      if name in ["vstack", "hstack", "keyed"]:
        if node[^1].kind != nnkStmtList:
          error(spelling & " requires a child block", node)
        let content = children(node[^1])
        result = newCall(
          if name == "vstack":
            bindSym"vstackSpec"
          elif name == "hstack":
            bindSym"hstackSpec"
          else:
            bindSym"keyedSpec"
        )
        for i in 1 ..< node.len - 1:
          result.add node[i].copyNimTree()
        if name == "keyed":
          result.add newCall(bindSym"onlySpec", content)
        else:
          result.add newTree(nnkExprEqExpr, ident"children", content)
      else:
        case name
        of "label":
          result[0] = bindSym"labelSpec"
        of "button":
          result[0] = bindSym"buttonSpec"
        of "textfield":
          result[0] = bindSym"textFieldSpec"
        else:
          discard
        if name in ["button", "textfield"] and node[^1].kind == nnkStmtList:
          result.del(result.len - 1)
          let eventName = if name == "button": "onAction" else: "onChange"
          if node[^1].len != 1:
            error("control blocks require one " & eventName & " binding", node[^1])
          let event = node[^1][0]
          if event.kind notin {nnkCall, nnkCommand} or not event[0].eqIdent(eventName):
            error("expected " & eventName & "(receiver) do (...) handler", event)
          let binding = newCall(bindSym"viewAction")
          for i in 1 ..< event.len:
            binding.add event[i].copyNimTree()
          result.add newTree(nnkExprEqExpr, ident(eventName), binding)
    inc nextSlot
    result = newCall(bindSym"atSlot", result, newLit(nextSlot))

  proc collect(body, output: NimNode): NimNode =
    result = newStmtList()
    for node in body:
      case node.kind
      of nnkLetSection, nnkVarSection, nnkConstSection, nnkAsgn, nnkDiscardStmt:
        result.add node.copyNimTree()
      of nnkForStmt, nnkBlockStmt:
        let copy = node.copyNimTree()
        copy[^1] = collect(node[^1], output)
        result.add copy
      of nnkIfStmt, nnkWhenStmt, nnkCaseStmt:
        let copy = node.copyNimTree()
        let start = if node.kind == nnkCaseStmt: 1 else: 0
        for i in start ..< copy.len:
          copy[i][^1] = collect(node[i][^1], output)
        result.add copy
      else:
        result.add newCall(bindSym"add", output, expression(node))

  result = newCall(bindSym"onlySpec", children(body))
