import std/[macros, strutils]

import ./core
import ./ivar
import ./assoc

export core
export ivar

type ObjcImplMethodKind = enum
  oimkInstance
  oimkClass

template kw*(name: static[string]) {.pragma.}
template structural*() {.pragma.}

type ObjcProtocolMethodSpec = object
  selector: string
  encoding: string
  methodKind: ObjcImplMethodKind
  isRequired: bool

type ObjcProtocolPropertySpec = object
  name: string
  typeEncoding: string
  methodKind: ObjcImplMethodKind
  isRequired: bool
  isReadOnly: bool

type ObjcImplMethodInfo = object
  spec: ObjcProtocolMethodSpec
  wrapperProc: NimNode
  implProc: NimNode
  sourceDef: NimNode

type ObjcImplIvarFieldSpec = object
  name: string
  typ: NimNode
  getterName: string
  setterName: string

proc identName(n: NimNode): string =
  case n.kind
  of nnkIdent, nnkSym:
    $n
  of nnkPostfix:
    identName(n[^1])
  of nnkPragmaExpr:
    identName(n[0])
  of nnkAccQuoted:
    if n.len > 0:
      identName(n[0])
    else:
      ""
  of nnkDotExpr:
    identName(n[^1])
  else:
    ""

proc isExportedName(n: NimNode): bool =
  case n.kind
  of nnkPostfix:
    n.len == 2 and $n[0] == "*"
  of nnkPragmaExpr:
    isExportedName(n[0])
  of nnkAccQuoted:
    if n.len > 0:
      isExportedName(n[0])
    else:
      false
  else:
    false

proc isExportedTypeName(n: NimNode): bool =
  isExportedName(n)

proc unwrapTypeNode(typ: NimNode): NimNode =
  case typ.kind
  of nnkPragmaExpr:
    unwrapTypeNode(typ[0])
  of nnkPostfix:
    if typ.len > 1:
      unwrapTypeNode(typ[^1])
    else:
      typ
  of nnkPar:
    if typ.len == 1:
      unwrapTypeNode(typ[0])
    else:
      typ
  else:
    typ

proc isTypedescTypeNode(typ: NimNode): bool =
  let node = unwrapTypeNode(typ)
  node.kind == nnkBracketExpr and node.len == 2 and identName(node[0]) == "typedesc"

proc typedescElementTypeName(typ: NimNode): string =
  let node = unwrapTypeNode(typ)
  if node.kind == nnkBracketExpr and node.len == 2 and identName(node[0]) == "typedesc":
    return identName(node[1])
  ""

proc objcTypeCodeFromTypeName(name, protocolName, className: string): string =
  if name == "char":
    return "c"
  elif name == "uint8":
    return "C"
  elif name == "int" or name == "cint" or name == "int32":
    return "i"
  elif name == "uint" or name == "cuint" or name == "uint32":
    return "I"
  elif name == "cshort":
    return "s"
  elif name == "cushort":
    return "S"
  elif name == "int64":
    return "q"
  elif name == "uint64":
    return "Q"
  elif name == "float" or name == "float32" or name == "cfloat":
    return "f"
  elif name == "float64" or name == "cdouble":
    return "d"
  elif name == "bool":
    return "B"
  elif name == "cstring" or name == "string":
    return "*"
  elif name == "ObjcClass":
    return "#"
  elif name == "NSObject" or name == "IDPtr" or name == protocolName or name == className:
    return "@"
  elif name == "SEL":
    return ":"
  elif name == "void":
    return "v"
  elif name == "NSPoint":
    return "{NSPoint=ff}"
  elif name == "NSSize":
    return "{NSSize=ff}"
  elif name == "NSRect":
    return "{NSRect={NSPoint=ff}{NSSize=ff}}"
  elif name == "CGPoint":
    return "{CGPoint=dd}"
  elif name == "CGSize":
    return "{CGSize=dd}"
  elif name == "CGRect":
    return "{CGRect={CGPoint=dd}{CGSize=dd}}"
  elif name == "NSRange":
    return "{_NSRange=QQ}"
  ""

proc objcTypeCodeFromNodeInner(
    typ: NimNode,
    protocolName, className: string,
    seen: var seq[string],
    preferredStructName = "",
): string =
  let node = unwrapTypeNode(typ)
  case node.kind
  of nnkEmpty:
    "v"
  of nnkRefTy:
    "@"
  of nnkVarTy, nnkDistinctTy:
    objcTypeCodeFromNodeInner(
      node[0], protocolName, className, seen, preferredStructName
    )
  of nnkBracketExpr:
    if node.len == 2 and identName(node[0]) == "typedesc": "#" else: "@"
  of nnkPtrTy:
    "^" & objcTypeCodeFromNodeInner(node[0], protocolName, className, seen)
  of nnkObjectTy:
    var payload = ""
    if node.len >= 3 and node[2].kind == nnkRecList:
      for rec in node[2]:
        if rec.kind != nnkIdentDefs:
          continue
        let fieldType = rec[^2]
        let fieldCount = max(rec.len - 2, 0)
        for _ in 0 ..< fieldCount:
          payload.add(
            objcTypeCodeFromNodeInner(fieldType, protocolName, className, seen)
          )
    let structName = if preferredStructName.len > 0: preferredStructName else: "?"
    "{" & structName & "=" & payload & "}"
  of nnkTupleTy:
    var payload = ""
    for part in node:
      if part.kind == nnkIdentDefs:
        let fieldType = part[^2]
        let fieldCount = max(part.len - 2, 0)
        for _ in 0 ..< fieldCount:
          payload.add(
            objcTypeCodeFromNodeInner(fieldType, protocolName, className, seen)
          )
      elif part.kind != nnkEmpty:
        payload.add(objcTypeCodeFromNodeInner(part, protocolName, className, seen))
    let structName = if preferredStructName.len > 0: preferredStructName else: "?"
    "{" & structName & "=" & payload & "}"
  of nnkIdent:
    let name = identName(node)
    let prim = objcTypeCodeFromTypeName(name, protocolName, className)
    if prim.len > 0:
      return prim
    "@"
  of nnkSym:
    let name = identName(node)
    let prim = objcTypeCodeFromTypeName(name, protocolName, className)
    if prim.len > 0:
      return prim
    if name.len == 0 or name in seen:
      return "@"
    seen.add(name)
    let impl = node.getImpl()
    if impl.kind == nnkTypeDef and impl.len >= 3:
      let body = impl[2]
      case body.kind
      of nnkObjectTy, nnkTupleTy:
        return objcTypeCodeFromNodeInner(body, protocolName, className, seen, name)
      of nnkDistinctTy:
        return objcTypeCodeFromNodeInner(body[0], protocolName, className, seen, name)
      of nnkRefTy:
        return "@"
      else:
        discard
    "@"
  else:
    let name = identName(node)
    let prim = objcTypeCodeFromTypeName(name, protocolName, className)
    if prim.len > 0: prim else: "@"

proc normalizeObjcNodeType(typ: NimNode, protocolName, className: string): NimNode =
  case typ.kind
  of nnkEmpty:
    result = newEmptyNode()
  of nnkVarTy, nnkRefTy, nnkDistinctTy, nnkPtrTy:
    result = newTree(typ.kind, normalizeObjcNodeType(typ[0], protocolName, className))
  of nnkBracketExpr:
    result = newNimNode(nnkBracketExpr)
    for c in typ:
      result.add(normalizeObjcNodeType(c, protocolName, className))
  else:
    let name = identName(typ)
    if name == protocolName:
      result = bindSym"NSObject"
    else:
      result = copyNimTree(typ)

proc objcTypeCodeFromNode(typ: NimNode, protocolName, className: string): string =
  var seen: seq[string] = @[]
  objcTypeCodeFromNodeInner(typ, protocolName, className, seen)

proc firstParamIndex(params: NimNode): int

proc paramNameNode(n: NimNode): NimNode =
  case n.kind
  of nnkPragmaExpr:
    paramNameNode(n[0])
  else:
    n

proc kwSelectorSegmentFromParamName(n: NimNode): string =
  if n.kind != nnkPragmaExpr:
    return ""
  let pragmas = n[1]
  if pragmas.kind != nnkPragma:
    return ""
  for p in pragmas:
    if p.kind == nnkCall and identName(p[0]) == "kw":
      if p.len != 2 or p[1].kind notin {nnkStrLit .. nnkTripleStrLit}:
        error("objcImpl `.kw(...)` pragma requires one string literal", p)
      return p[1].strVal
  ""

proc methodSpecFromDef(
    def: NimNode, protocolName, className: string
): ObjcProtocolMethodSpec =
  if def.kind notin {nnkMethodDef, nnkProcDef}:
    error("objcImpl concept can only contain method/proc declarations", def)

  let methodName = identName(def.name)
  if methodName.len == 0:
    error("objcImpl could not read method name from concept", def)

  let params = def.params
  let firstIdx = firstParamIndex(params)
  if firstIdx < 0:
    error(
      "objcImpl method/proc declarations must include `self` as first argument", def
    )
  let firstParamTypedesc = typedescElementTypeName(params[firstIdx][^2])
  var totalParams = 0
  var explicitArgCount = 0
  var encoding = objcTypeCodeFromNode(params[0], protocolName, className) & "@:"
  var selectorName = methodName

  for i in 1 ..< params.len:
    let p = params[i]
    if p.kind != nnkIdentDefs:
      continue
    let typeNode = p[^2]
    let namedCount = p.len - 2
    for j in 0 ..< namedCount:
      inc totalParams
      if totalParams == 1:
        continue # first arg is the explicit self in Nim surface syntax
      inc explicitArgCount
      let kwSegment = kwSelectorSegmentFromParamName(p[j])
      if kwSegment.len > 0:
        selectorName.add(kwSegment)
      selectorName.add(':')
      encoding.add(objcTypeCodeFromNode(typeNode, protocolName, className))

  result.selector = selectorName
  result.encoding = encoding
  result.methodKind = if firstParamTypedesc.len > 0: oimkClass else: oimkInstance
  result.isRequired = true

  let pragmas = def.pragma
  if pragmas.kind == nnkPragma:
    var hasOptional = false
    var hasRequired = false
    for p in pragmas:
      let pragmaName =
        case p.kind
        of nnkExprColonExpr:
          identName(p[0])
        else:
          identName(p)
      if pragmaName == "optional":
        hasOptional = true
      elif pragmaName == "required":
        hasRequired = true
    if hasOptional and hasRequired:
      error("objcImpl protocol method cannot be both `.optional` and `.required`", def)
    if hasOptional:
      result.isRequired = false

proc propertySpecFromDef(
    def: NimNode, protocolName, className: string
): ObjcProtocolPropertySpec =
  if def.kind notin {nnkMethodDef, nnkProcDef}:
    error(
      "objcImpl concept property declarations must be method/proc declarations", def
    )

  let methodName = identName(def.name)
  if methodName.len == 0:
    error("objcImpl could not read property declaration name", def)

  let params = def.params
  let selfIdx = firstParamIndex(params)
  if selfIdx < 0:
    error("objcImpl property declarations must include `self` as first argument", def)

  var totalParams = 0
  for i in 1 ..< params.len:
    let p = params[i]
    if p.kind != nnkIdentDefs:
      continue
    let namedCount = p.len - 2
    for _ in 0 ..< namedCount:
      inc totalParams
  if totalParams != 1:
    error(
      "objcImpl `.property` declarations must be getter-style declarations with only `self` parameter",
      def,
    )

  let retType = params[0]
  if retType.kind == nnkEmpty:
    error("objcImpl `.property` declarations must have a non-void return type", def)

  let retEnc = objcTypeCodeFromNode(retType, protocolName, className)
  if retEnc == "v":
    error("objcImpl `.property` declarations must have a non-void return type", def)

  result.name = methodName
  result.typeEncoding = retEnc
  result.methodKind =
    if typedescElementTypeName(params[selfIdx][^2]).len > 0: oimkClass else: oimkInstance
  result.isRequired = true
  result.isReadOnly = false

  let pragmas = def.pragma
  if pragmas.kind == nnkPragma:
    var hasOptional = false
    var hasRequired = false
    for p in pragmas:
      case p.kind
      of nnkExprColonExpr:
        let pragmaName = identName(p[0])
        if pragmaName == "property":
          let n =
            case p[1].kind
            of nnkStrLit .. nnkTripleStrLit:
              p[1].strVal
            else:
              identName(p[1])
          if n.len == 0:
            error("objcImpl `.property` pragma requires a valid property name", p)
          result.name = n
        elif pragmaName == "optional":
          hasOptional = true
        elif pragmaName == "required":
          hasRequired = true
      else:
        let pragmaName = identName(p)
        if pragmaName == "optional":
          hasOptional = true
        elif pragmaName == "required":
          hasRequired = true
        elif pragmaName == "readonly":
          result.isReadOnly = true
    if hasOptional and hasRequired:
      error(
        "objcImpl protocol property cannot be both `.optional` and `.required`", def
      )
    if hasOptional:
      result.isRequired = false

proc hasPropertyPragma(def: NimNode): bool =
  let pragmas = def.pragma
  if pragmas.kind != nnkPragma:
    return false
  for p in pragmas:
    case p.kind
    of nnkExprColonExpr:
      if identName(p[0]) == "property":
        return true
    else:
      if identName(p) == "property":
        return true
  false

proc firstParamIndex(params: NimNode): int =
  for i in 1 ..< params.len:
    if params[i].kind == nnkIdentDefs:
      return i
  -1

proc firstParamTypeName(def: NimNode): string =
  let params = def.params
  let idx = firstParamIndex(params)
  if idx < 0:
    return ""
  let typ = params[idx][^2]
  if isTypedescTypeNode(typ):
    return ""
  identName(typ)

proc firstParamTypedescName(def: NimNode): string =
  let params = def.params
  let idx = firstParamIndex(params)
  if idx < 0:
    return ""
  typedescElementTypeName(params[idx][^2])

proc methodKindLabel(kind: ObjcImplMethodKind): string =
  if kind == oimkClass: "class" else: "instance"

proc hasErrorPragma(def: NimNode): bool =
  let pragmas = def.pragma
  if pragmas.kind != nnkPragma:
    return false
  for p in pragmas:
    case p.kind
    of nnkExprColonExpr:
      if identName(p[0]) == "error":
        return true
    else:
      if identName(p) == "error":
        return true
  false

template objcAbiType(T: typedesc): untyped =
  when T is string:
    cstring
  elif T is ID:
    IDPtr
  else:
    T

const ObjcCStringScratchSlots = 128

var objcCStringScratch {.threadvar.}: seq[string]
var objcCStringScratchIdx {.threadvar.}: int

proc objcStableCString*(value: string): cstring =
  ## Keeps C-string pointers alive across objc_msgSend varargs boundaries.
  if objcCStringScratch.len == 0:
    objcCStringScratch.setLen(ObjcCStringScratchSlots)
    objcCStringScratchIdx = 0
  let idx = objcCStringScratchIdx
  objcCStringScratch[idx] = value
  objcCStringScratchIdx = (idx + 1) mod ObjcCStringScratchSlots
  cstring(objcCStringScratch[idx])

template objcToAbiArg(T: typedesc, v: untyped): untyped =
  when T is string:
    objcStableCString(v)
  elif T is ID:
    toID(v)
  else:
    v

template objcFromAbiValue(T: typedesc, v: untyped): untyped =
  when T is string:
    if v.isNil:
      ""
    else:
      $v
  elif T is ID:
    asTypeRaw[T](v)
  else:
    v

template objcFromAbiReturnValue(T: typedesc, v: untyped): untyped =
  block:
    let objcRawReturnValue = v
    when T is string:
      if objcRawReturnValue.isNil:
        ""
      else:
        $objcRawReturnValue
    elif T is ID:
      objcRawReturnValue as T
    else:
      objcRawReturnValue

proc objcAbiTypeNode(typ: NimNode): NimNode =
  newCall(bindSym"objcAbiType", copyNimTree(typ))

proc objcToAbiArgNode(typ, arg: NimNode): NimNode =
  newCall(bindSym"objcToAbiArg", copyNimTree(typ), copyNimTree(arg))

proc objcFromAbiValueNode(typ, value: NimNode): NimNode =
  newCall(bindSym"objcFromAbiValue", copyNimTree(typ), copyNimTree(value))

proc buildObjcWrapperProc(
    def: NimNode, protocolName, className: string
): tuple[implProc: NimNode, wrapperProc: NimNode] =
  let methodName = identName(def.name)
  if methodName.len == 0:
    error("objcImpl could not read implementation method name", def)

  let params = def.params
  let selfIdx = firstParamIndex(params)
  if selfIdx < 0:
    error("objcImpl method implementation must include `self` as first argument", def)
  let selfParam = params[selfIdx]
  if selfParam.len != 3:
    error(
      "objcImpl first parameter group must contain exactly one name for `self`", def
    )
  let selfName = identName(paramNameNode(selfParam[0]))
  if selfName.len == 0:
    error("objcImpl could not read implementation self parameter name", def)
  let isClassMethod = firstParamTypedescName(def) == className

  let implName = genSym(nskProc, methodName & "_impl")
  var implProc = newNimNode(nnkProcDef)
  for c in def:
    implProc.add(copyNimTree(c))
  implProc[0] = implName

  var wrapperParams: seq[NimNode] = @[]
  let retType = normalizeObjcNodeType(params[0], protocolName, className)
  if retType.kind == nnkEmpty:
    wrapperParams.add(newEmptyNode())
  else:
    wrapperParams.add(objcAbiTypeNode(retType))

  let selfIdent = ident(selfName)
  let selfRaw = genSym(nskParam, selfName & "Raw")
  wrapperParams.add(newIdentDefs(selfRaw, bindSym"IDPtr", newEmptyNode()))
  let cmdSel = genSym(nskParam, "cmdSel")
  wrapperParams.add(newIdentDefs(cmdSel, bindSym"SEL", newEmptyNode()))

  var wrapperBody = newStmtList()
  var callArgs: seq[NimNode] = @[]
  if isClassMethod:
    let classType = ident(className)
    wrapperBody.add quote do:
      discard `selfRaw`
    callArgs.add(copyNimTree(classType))
  else:
    let selfType = ident(className)
    wrapperBody.add quote do:
      var `selfIdent` = asTypeRaw[`selfType`](`selfRaw`)
    wrapperBody.add quote do:
      discard `selfIdent`
    wrapperBody.add quote do:
      defer:
        wasMoved(`selfIdent`)
    callArgs.add(copyNimTree(selfIdent))

  var sawSelf = false
  for i in 1 ..< params.len:
    let p = params[i]
    if p.kind != nnkIdentDefs:
      continue
    if not sawSelf:
      sawSelf = true
      continue
    let typeNode = p[^2]
    let normType = normalizeObjcNodeType(typeNode, protocolName, className)
    let abiType = objcAbiTypeNode(normType)
    for j in 0 ..< p.len - 2:
      let argIdent = identName(paramNameNode(p[j]))
      if argIdent.len == 0:
        error("objcImpl could not read parameter name", p[j])
      let argName = ident(argIdent)
      let rawArg = genSym(nskParam, argIdent & "Raw")
      let fromValueExprForVar = objcFromAbiValueNode(normType, rawArg)
      let fromValueExprForLet = objcFromAbiValueNode(normType, rawArg)
      wrapperParams.add(newIdentDefs(rawArg, abiType, newEmptyNode()))
      wrapperBody.add quote do:
        when `normType` is ID:
          var `argName` = `fromValueExprForVar`
          discard `argName`
          defer:
            wasMoved(`argName`)
        else:
          let `argName` = `fromValueExprForLet`
      callArgs.add(copyNimTree(argName))

  wrapperBody.add quote do:
    discard `cmdSel`

  let implCall = newCall(implName)
  for a in callArgs:
    implCall.add(a)

  if retType.kind == nnkEmpty:
    wrapperBody.add(implCall)
  else:
    wrapperBody.add quote do:
      when `retType` is ID:
        var objcImplReturnValue = `implCall`
        let objcAbiReturnValue = objcToAbiArg(`retType`, objcImplReturnValue)
        result = objcAbiReturnValue
        wasMoved(objcImplReturnValue)
      else:
        result = objcToAbiArg(`retType`, `implCall`)

  let wrapperProc = newProc(
    name = genSym(nskProc, methodName & "_objcWrapper"),
    params = wrapperParams,
    body = wrapperBody,
    pragmas = nnkPragma.newTree(ident"cdecl"),
  )
  result = (implProc: implProc, wrapperProc: wrapperProc)

proc normalizeObjcHelperType(typ: NimNode, protocolName, className: string): NimNode =
  case typ.kind
  of nnkEmpty:
    result = newEmptyNode()
  of nnkVarTy, nnkRefTy, nnkDistinctTy, nnkPtrTy:
    result = newTree(typ.kind, normalizeObjcHelperType(typ[0], protocolName, className))
  of nnkBracketExpr:
    result = newNimNode(nnkBracketExpr)
    for c in typ:
      result.add(normalizeObjcHelperType(c, protocolName, className))
  else:
    let name = identName(typ)
    if name == protocolName:
      if className.len > 0:
        result = ident(className)
      else:
        result = copyNimTree(typ)
    else:
      result = copyNimTree(typ)

proc buildObjcCallHelperProc(
    def: NimNode, spec: ObjcProtocolMethodSpec, protocolName, className: string
): NimNode =
  let srcParams = def.params
  let helperBaseName = identName(def.name)
  if helperBaseName.len == 0:
    error("objcImpl helper generation requires a valid method name", def)
  let helperNameNode =
    if def.len > 0:
      def[0]
    else:
      def.name
  let helperName =
    if isExportedName(helperNameNode):
      postfix(ident(helperBaseName), "*")
    else:
      ident(helperBaseName)
  let selfIdx = firstParamIndex(srcParams)
  if selfIdx < 0:
    error("objcImpl helper generation requires a first `self` parameter", def)

  var helperParams: seq[NimNode] = @[]
  var retType = normalizeObjcHelperType(srcParams[0], protocolName, className)
  helperParams.add(copyNimTree(retType))
  for i in 1 ..< srcParams.len:
    let p = srcParams[i]
    if p.kind != nnkIdentDefs:
      helperParams.add(copyNimTree(p))
      continue
    var hp = copyNimTree(p)
    hp[^2] = normalizeObjcHelperType(p[^2], protocolName, className)
    helperParams.add(hp)

  let selfParam = srcParams[selfIdx]
  if selfParam.len != 3:
    error(
      "objcImpl helper generation expects first parameter group to contain one name",
      def,
    )
  let selfName = copyNimTree(paramNameNode(selfParam[0]))

  let callSel = newCall(bindSym"getSelector", newLit(spec.selector))

  let senderParams = newNimNode(nnkFormalParams)
  let retAbiType =
    if retType.kind == nnkEmpty:
      ident"void"
    else:
      objcAbiTypeNode(retType)
  senderParams.add(retAbiType)
  senderParams.add(newIdentDefs(ident"selfId", bindSym"IDPtr"))
  senderParams.add(newIdentDefs(ident"selector", bindSym"SEL"))

  let callTarget =
    if spec.methodKind == oimkClass:
      newCall(bindSym"objcClass", copyNimTree(selfName))
    else:
      copyNimTree(selfName)
  var callArgs: seq[NimNode] = @[callTarget, callSel]
  var seenSelf = false
  for i in 1 ..< srcParams.len:
    let p = srcParams[i]
    if p.kind != nnkIdentDefs:
      continue
    if not seenSelf:
      seenSelf = true
      continue
    let pType = normalizeObjcHelperType(p[^2], protocolName, className)
    let abiType = objcAbiTypeNode(pType)
    for j in 0 ..< p.len - 2:
      let argIdent = identName(paramNameNode(p[j]))
      if argIdent.len == 0:
        error("objcImpl helper generation could not read parameter name", p[j])
      let argName = ident(argIdent)
      senderParams.add(newIdentDefs(ident("arg" & $i & "_" & $j), abiType))
      callArgs.add(objcToAbiArgNode(pType, argName))

  let procTy = newTree(nnkProcTy, senderParams)
  procTy.add(newTree(nnkPragma, ident"cdecl", ident"varargs", ident"gcsafe"))
  let sendProcSym = genSym(nskLet, "performSend")
  let sendProc = newTree(nnkCast, procTy, bindSym"objc_msgSend")
  let castSendProc =
    newTree(nnkLetSection, newIdentDefs(sendProcSym, newEmptyNode(), sendProc))
  let callExpr = newCall(sendProcSym)
  for a in callArgs:
    callExpr.add(a)

  var body = newStmtList()
  body.add(castSendProc)
  if retType.kind == nnkEmpty:
    body.add(callExpr)
  else:
    body.add quote do:
      result = objcFromAbiReturnValue(`retType`, `callExpr`)

  result = newProc(
    name = helperName,
    params = helperParams,
    body = body,
    pragmas = nnkPragma.newTree(ident"inline"),
  )

proc collectImplProtocols(n: NimNode, protocols: var seq[string]) =
  case n.kind
  of nnkStmtList, nnkTupleConstr, nnkPar:
    for c in n:
      collectImplProtocols(c, protocols)
  else:
    let pName = identName(n)
    if pName.len == 0:
      error("objcImpl `impl` protocol name is invalid", n)
    protocols.add(pName)

proc collectIvarTypes(n: NimNode, ivarTypes: var seq[NimNode]) =
  case n.kind
  of nnkStmtList, nnkTupleConstr, nnkPar:
    for c in n:
      collectIvarTypes(c, ivarTypes)
  of nnkEmpty:
    discard
  else:
    ivarTypes.add(copyNimTree(n))

proc collectImplPragmaProtocols(typeNameNode: NimNode, protocols: var seq[string]) =
  case typeNameNode.kind
  of nnkPragmaExpr:
    let pragmas = typeNameNode[1]
    if pragmas.kind == nnkPragma:
      for p in pragmas:
        if p.kind == nnkExprColonExpr and identName(p[0]) == "impl":
          collectImplProtocols(p[1], protocols)
        elif identName(p) == "impl":
          error("objcImpl `.impl` pragma requires at least one protocol", p)
    collectImplPragmaProtocols(typeNameNode[0], protocols)
  of nnkPostfix:
    collectImplPragmaProtocols(typeNameNode[^1], protocols)
  of nnkAccQuoted:
    if typeNameNode.len > 0:
      collectImplPragmaProtocols(typeNameNode[0], protocols)
  else:
    discard

proc collectIvarPragmaTypes(typeNameNode: NimNode, ivarTypes: var seq[NimNode]) =
  case typeNameNode.kind
  of nnkPragmaExpr:
    let pragmas = typeNameNode[1]
    if pragmas.kind == nnkPragma:
      for p in pragmas:
        if p.kind == nnkExprColonExpr and identName(p[0]) == "ivar":
          collectIvarTypes(p[1], ivarTypes)
        elif identName(p) == "ivar":
          error("objcImpl `.ivar` pragma requires at least one type", p)
    collectIvarPragmaTypes(typeNameNode[0], ivarTypes)
  of nnkPostfix:
    collectIvarPragmaTypes(typeNameNode[^1], ivarTypes)
  of nnkAccQuoted:
    if typeNameNode.len > 0:
      collectIvarPragmaTypes(typeNameNode[0], ivarTypes)
  else:
    discard

proc hasStructuralPragma(typeNameNode: NimNode): bool =
  case typeNameNode.kind
  of nnkPragmaExpr:
    let pragmas = typeNameNode[1]
    if pragmas.kind == nnkPragma:
      for p in pragmas:
        if identName(p) == "structural":
          return true
    hasStructuralPragma(typeNameNode[0])
  of nnkPostfix:
    hasStructuralPragma(typeNameNode[^1])
  of nnkAccQuoted:
    if typeNameNode.len > 0:
      hasStructuralPragma(typeNameNode[0])
    else:
      false
  else:
    false

proc collectFieldAccessorPragmas(
    fieldNode: NimNode, getterName, setterName: var string
) =
  if fieldNode.kind != nnkPragmaExpr:
    return
  let pragmas = fieldNode[1]
  if pragmas.kind != nnkPragma:
    return

  for p in pragmas:
    if p.kind == nnkExprColonExpr:
      let pragmaName = identName(p[0])
      if pragmaName == "get":
        let gName = identName(p[1])
        if gName.len == 0:
          error("objcImpl `.get` field pragma requires a getter name", p)
        if getterName.len > 0:
          error("objcImpl duplicate `.get` field pragma", p)
        getterName = gName
      elif pragmaName == "set":
        let sName = identName(p[1])
        if sName.len == 0:
          error("objcImpl `.set` field pragma requires a setter name", p)
        if setterName.len > 0:
          error("objcImpl duplicate `.set` field pragma", p)
        setterName = sName
    else:
      let pragmaName = identName(p)
      if pragmaName == "get":
        error("objcImpl `.get` field pragma requires a getter name", p)
      elif pragmaName == "set":
        error("objcImpl `.set` field pragma requires a setter name", p)

proc collectObjectIvarFields(
    objectTy: NimNode, fields: var seq[ObjcImplIvarFieldSpec]
) =
  if objectTy.kind != nnkObjectTy:
    return
  if objectTy.len < 3:
    return

  let recList = objectTy[2]
  if recList.kind == nnkEmpty:
    return
  if recList.kind != nnkRecList:
    error("objcImpl class ivar fields must be simple `name: RefType` entries", objectTy)

  for rec in recList:
    if rec.kind != nnkIdentDefs:
      error("objcImpl class ivar fields must be simple `name: RefType` entries", rec)
    let fieldType = copyNimTree(rec[^2])
    for i in 0 ..< rec.len - 2:
      let fName = identName(rec[i])
      if fName.len == 0:
        error("objcImpl class ivar field name is invalid", rec[i])
      var getterName = ""
      var setterName = ""
      collectFieldAccessorPragmas(rec[i], getterName, setterName)
      fields.add ObjcImplIvarFieldSpec(
        name: fName,
        typ: copyNimTree(fieldType),
        getterName: getterName,
        setterName: setterName,
      )

proc buildConditionalTypeDecl(
    typeLine: string, typeName: string, onlyIfMissing: bool
): NimNode =
  if not onlyIfMissing:
    return parseStmt("type\n  " & typeLine)
  parseStmt(
    "when not compiles(block:\n" & "  var objcImplTypeCheck: " & typeName & "\n" &
      "  discard objcImplTypeCheck):\n" & "  type\n    " & typeLine
  )

proc objcImplRuntimeName(name: string): string =
  nutellaNsToNxRuntimeName(name)

proc buildRespondsLikeProc(
    protocolName: string,
    protocolExported: bool,
    protocolSpecs: seq[ObjcProtocolMethodSpec],
): NimNode =
  let respondsLikeName =
    if protocolExported:
      postfix(ident("respondsLike"), "*")
    else:
      ident("respondsLike")
  let protocolType = ident(protocolName)
  let objName = ident("o")

  let nilRetExpr = newTree(
    nnkObjConstr,
    copyNimTree(protocolType),
    newTree(nnkExprColonExpr, ident("value"), newNilLit()),
  )

  var ifStmt = newNimNode(nnkIfStmt)
  ifStmt.add(
    newTree(
      nnkElifBranch,
      newCall(newDotExpr(copyNimTree(objName), ident("isNil"))),
      newStmtList(newNimNode(nnkReturnStmt).add(copyNimTree(nilRetExpr))),
    )
  )

  for spec in protocolSpecs:
    if not spec.isRequired or spec.methodKind != oimkInstance:
      continue
    let selectorLit = newLit(spec.selector)
    let hasSelectorExpr = newCall(
      bindSym"respondsToSelector",
      newCall(bindSym"getClass", newDotExpr(copyNimTree(objName), ident("value"))),
      newCall(bindSym"selector", selectorLit),
    )
    ifStmt.add(
      newTree(
        nnkElifBranch,
        newCall(bindSym"not", hasSelectorExpr),
        newStmtList(newNimNode(nnkReturnStmt).add(copyNimTree(nilRetExpr))),
      )
    )

  let body = newStmtList()
  body.add(ifStmt)
  body.add(
    newNimNode(nnkReturnStmt).add(
      newCall(bindSym"to", copyNimTree(objName), copyNimTree(protocolType))
    )
  )

  result = newProc(
    name = respondsLikeName,
    params =
      @[
        copyNimTree(protocolType),
        newIdentDefs(copyNimTree(objName), bindSym"ID", newEmptyNode()),
        newIdentDefs(
          ident("expected"),
          nnkBracketExpr.newTree(ident("typedesc"), copyNimTree(protocolType)),
          newEmptyNode(),
        ),
      ],
    body = body,
    pragmas = nnkPragma.newTree(ident"inline"),
  )

macro objcImpl*(x: untyped): untyped =
  let input =
    if x.kind == nnkStmtList:
      x
    else:
      newStmtList(x)

  var protocolName = ""
  var className = ""
  var protocolExported = false
  var protocolStructural = false
  var classExported = false
  var classSuperName = ""
  var classImplProtocols: seq[string] = @[]
  var classIvarTypes: seq[NimNode] = @[]
  var classIvarFields: seq[ObjcImplIvarFieldSpec] = @[]
  var conceptBody = newEmptyNode()
  var implementedProtocols: seq[string] = @[]
  var inferredExtensionClassName = ""

  for stmt in input:
    case stmt.kind
    of nnkTypeSection:
      for def in stmt:
        if def.kind != nnkTypeDef:
          continue
        let name = identName(def[0])
        if name.len == 0:
          continue
        let body = def[2]
        case body.kind
        of nnkTypeClassTy:
          protocolName = name
          protocolExported = isExportedTypeName(def[0])
          protocolStructural = hasStructuralPragma(def[0])
          conceptBody = body[^1]
        of nnkObjectTy:
          className = name
          classExported = isExportedTypeName(def[0])
          if body.len >= 2 and body[1].kind == nnkOfInherit and body[1].len > 0:
            classSuperName = identName(body[1][0])
          classImplProtocols = @[]
          classIvarTypes = @[]
          classIvarFields = @[]
          collectImplPragmaProtocols(def[0], classImplProtocols)
          collectIvarPragmaTypes(def[0], classIvarTypes)
          collectObjectIvarFields(body, classIvarFields)
        else:
          discard
    of nnkCommand, nnkCall:
      if identName(stmt[0]) == "implements":
        error(
          "objcImpl no longer supports `implements`; use `type <Class> {.impl: <Protocol>... .} = object of <Superclass>`",
          stmt,
        )
    else:
      discard

  let hasProtocol = protocolName.len > 0
  let hasClassDecl = className.len > 0

  if not hasProtocol and not hasClassDecl:
    var extensionClassTargets: seq[string] = @[]
    for stmt in input:
      if stmt.kind notin {nnkMethodDef, nnkProcDef} or hasErrorPragma(stmt):
        continue
      let classTarget = block:
        let receiver = firstParamTypeName(stmt)
        if receiver.len > 0:
          receiver
        else:
          firstParamTypedescName(stmt)
      if classTarget.len == 0:
        continue
      if classTarget notin extensionClassTargets:
        extensionClassTargets.add(classTarget)

    if extensionClassTargets.len == 1:
      inferredExtensionClassName = extensionClassTargets[0]
      className = inferredExtensionClassName
    elif extensionClassTargets.len > 1:
      error(
        "objcImpl class extension block must target exactly one class; found `" &
          extensionClassTargets.join("`, `") & "`",
        x,
      )

  let hasClass = className.len > 0
  let isClassExtensionBlock = inferredExtensionClassName.len > 0
  if not hasProtocol and not hasClass:
    error(
      "objcImpl requires at least one declaration: protocol concept and/or class object",
      x,
    )

  if hasClassDecl and classSuperName.len == 0:
    error("objcImpl class declaration must include a superclass", x)

  implementedProtocols = classImplProtocols
  if hasProtocol and hasClassDecl:
    if classImplProtocols.len == 0:
      error(
        "objcImpl requires class protocol conformance via pragma: `type <Class> {.impl: <Protocol>... .} = object of <Superclass>`",
        x,
      )

    if classSuperName == protocolName:
      error(
        "objcImpl class cannot inherit from protocol `" & protocolName &
          "`; use `object of NSObject` (or another class) plus `{.impl: " & protocolName &
          ".}`",
        x,
      )
    var protocolImplemented = false
    for p in implementedProtocols:
      if p == protocolName:
        protocolImplemented = true
        break
    if not protocolImplemented:
      error(
        "objcImpl protocol `" & protocolName &
          "` must appear in class pragma `{.impl: ... .}`",
        x,
      )

  # De-duplicate protocol list while preserving order.
  var dedupProtocols: seq[string] = @[]
  for p in implementedProtocols:
    if p notin dedupProtocols:
      dedupProtocols.add(p)
  implementedProtocols = dedupProtocols

  # De-duplicate ivar types while preserving order.
  var dedupIvarTypes: seq[NimNode] = @[]
  var dedupIvarTypeKeys: seq[string] = @[]
  for t in classIvarTypes:
    let key = t.repr
    if key notin dedupIvarTypeKeys:
      dedupIvarTypeKeys.add(key)
      dedupIvarTypes.add(t)
  classIvarTypes = dedupIvarTypes

  var dedupFieldNames: seq[string] = @[]
  var dedupIvarFields: seq[ObjcImplIvarFieldSpec] = @[]
  for f in classIvarFields:
    if f.name in dedupFieldNames:
      error("objcImpl duplicate ivar field `" & f.name & "`", x)
    dedupFieldNames.add(f.name)
    dedupIvarFields.add(f)
  classIvarFields = dedupIvarFields

  var autoFieldImplDefs: seq[NimNode] = @[]
  if hasClass:
    let classTypeIdent = ident(className)
    for field in classIvarFields:
      let fieldTypeNode = copyNimTree(field.typ)
      let selfIdent = ident("self")
      let valueIdent = ident("value")

      if field.getterName.len > 0 and field.getterName != field.name:
        let getterProcName = ident(field.name)
        let getterMethodName =
          if classExported:
            postfix(ident(field.getterName), "*")
          else:
            ident(field.getterName)
        let getterBody = quote:
          result = `getterProcName`(`selfIdent`)
        autoFieldImplDefs.add(
          newProc(
            name = getterMethodName,
            params =
              @[
                copyNimTree(fieldTypeNode),
                newIdentDefs(selfIdent, copyNimTree(classTypeIdent), newEmptyNode()),
              ],
            body = getterBody,
            pragmas = nnkPragma.newTree(ident"inline"),
          )
        )

      if field.setterName.len > 0 and field.setterName != field.name & "=":
        let setterProcName = ident(field.name & "=")
        let setterMethodName =
          if classExported:
            postfix(ident(field.setterName), "*")
          else:
            ident(field.setterName)
        let setterBody = quote:
          `setterProcName`(`selfIdent`, `valueIdent`)
        autoFieldImplDefs.add(
          newProc(
            name = setterMethodName,
            params =
              @[
                newEmptyNode(),
                newIdentDefs(selfIdent, copyNimTree(classTypeIdent), newEmptyNode()),
                newIdentDefs(valueIdent, copyNimTree(fieldTypeNode), newEmptyNode()),
              ],
            body = setterBody,
            pragmas = nnkPragma.newTree(ident"inline"),
          )
        )

  if hasProtocol and conceptBody.kind != nnkStmtList:
    error("objcImpl protocol concept body is missing method declarations", x)

  var protocolSpecs: seq[ObjcProtocolMethodSpec] = @[]
  var protocolPropertySpecs: seq[ObjcProtocolPropertySpec] = @[]
  var protocolHelperDefs = newStmtList()
  var protocolStructuralDefs = newStmtList()
  if hasProtocol:
    for conceptStmt in conceptBody:
      let spec = methodSpecFromDef(conceptStmt, protocolName, className)
      protocolSpecs.add(spec)
      protocolHelperDefs.add(
        buildObjcCallHelperProc(conceptStmt, spec, protocolName, "")
      )
      if hasPropertyPragma(conceptStmt):
        protocolPropertySpecs.add(
          propertySpecFromDef(conceptStmt, protocolName, className)
        )
    if protocolStructural:
      protocolStructuralDefs.add(
        buildRespondsLikeProc(protocolName, protocolExported, protocolSpecs)
      )

  var generatedTypes = newStmtList()
  if hasProtocol:
    let protocolTypeLine =
      protocolName & (if protocolExported: "*" else: "") &
      " = object of ObjcProtocolObject"
    let protocolPrototypeTypeLine =
      protocolName & "Prototype" & (if protocolExported: "*" else: "") &
      " = object of ProtocolPrototype"
    generatedTypes.add(buildConditionalTypeDecl(protocolTypeLine, protocolName, true))
    generatedTypes.add(
      buildConditionalTypeDecl(
        protocolPrototypeTypeLine, protocolName & "Prototype", true
      )
    )
  if hasClassDecl:
    let classTypeLine =
      className & (if classExported: "*" else: "") & " = object of " & classSuperName
    generatedTypes.add(buildConditionalTypeDecl(classTypeLine, className, true))

  var passthrough = newStmtList()
  var implDefs: seq[NimNode] = @[]
  for stmt in input:
    case stmt.kind
    of nnkTypeSection:
      var filtered = newNimNode(nnkTypeSection)
      for def in stmt:
        if def.kind != nnkTypeDef:
          filtered.add(copyNimTree(def))
          continue
        let name = identName(def[0])
        let body = def[2]
        if (hasProtocol and name == protocolName and body.kind == nnkTypeClassTy) or
            (hasClassDecl and name == className and body.kind == nnkObjectTy):
          continue
        filtered.add(copyNimTree(def))
      if filtered.len > 0:
        passthrough.add(filtered)
    of nnkCommand, nnkCall:
      passthrough.add(copyNimTree(stmt))
    of nnkMethodDef, nnkProcDef:
      if hasClass and not hasErrorPragma(stmt) and (
        firstParamTypeName(stmt) == className or
        firstParamTypedescName(stmt) == className
      ):
        implDefs.add(stmt)
      else:
        passthrough.add(copyNimTree(stmt))
    else:
      passthrough.add(copyNimTree(stmt))

  for fieldDef in autoFieldImplDefs:
    implDefs.add(fieldDef)

  var implMethods: seq[ObjcImplMethodInfo] = @[]
  for def in implDefs:
    let built = buildObjcWrapperProc(def, protocolName, className)
    implMethods.add ObjcImplMethodInfo(
      spec: methodSpecFromDef(def, protocolName, className),
      wrapperProc: built.wrapperProc,
      implProc: built.implProc,
      sourceDef: def,
    )

  for i in 0 ..< implMethods.len:
    for j in i + 1 ..< implMethods.len:
      if implMethods[i].spec.selector == implMethods[j].spec.selector and
          implMethods[i].spec.methodKind == implMethods[j].spec.methodKind:
        error(
          "objcImpl found duplicate " & methodKindLabel(implMethods[i].spec.methodKind) &
            " implementation for selector `" & implMethods[i].spec.selector & "`",
          implMethods[j].sourceDef,
        )

  if hasProtocol and hasClassDecl:
    for pSpec in protocolSpecs:
      if not pSpec.isRequired:
        continue
      var found = false
      for impl in implMethods:
        if impl.spec.selector != pSpec.selector or
            impl.spec.methodKind != pSpec.methodKind:
          continue
        found = true
        if impl.spec.encoding != pSpec.encoding:
          error(
            "objcImpl signature mismatch for `" & pSpec.selector & "`: protocol `" &
              pSpec.encoding & "`, implementation `" & impl.spec.encoding & "`",
            x,
          )
        break
      if not found:
        error(
          "objcImpl missing implementation for required " &
            methodKindLabel(pSpec.methodKind) & " protocol method `" & pSpec.selector &
            "`",
          x,
        )

  let protoVar =
    if hasProtocol:
      genSym(nskVar, "objcImplProto")
    else:
      newEmptyNode()
  let clsVar =
    if hasClass:
      genSym(nskVar, "objcImplClass")
    else:
      newEmptyNode()
  let protoNameLit =
    if hasProtocol:
      newLit(objcImplRuntimeName(protocolName))
    else:
      newEmptyNode()
  let classNameLit =
    if hasClass:
      newLit(objcImplRuntimeName(className))
    else:
      newEmptyNode()
  let superClassNameLit =
    if hasClass:
      newLit(objcImplRuntimeName(classSuperName))
    else:
      newEmptyNode()
  let metaClsVar =
    if hasClass:
      genSym(nskLet, "objcImplMetaClass")
    else:
      newEmptyNode()
  var addMethodDescs = newStmtList()
  var addPropertyDescs = newStmtList()
  if hasProtocol:
    for spec in protocolSpecs:
      let selectorName = newLit(spec.selector)
      let typeEncoding = newLit(spec.encoding)
      let isRequiredMethod = newLit(spec.isRequired)
      let isInstanceMethod = newLit(spec.methodKind == oimkInstance)
      addMethodDescs.add quote do:
        addMethodDescription(
          `protoVar`,
          selector(`selectorName`),
          `typeEncoding`,
          `isRequiredMethod`,
          `isInstanceMethod`,
        )
    for spec in protocolPropertySpecs:
      let propertyName = newLit(spec.name)
      let propertyTypeEncoding = newLit(spec.typeEncoding)
      let isRequiredProperty = newLit(spec.isRequired)
      let isInstanceProperty = newLit(spec.methodKind == oimkInstance)
      let isReadOnlyProperty = newLit(spec.isReadOnly)
      addPropertyDescs.add quote do:
        block:
          var attrs =
            @[
              objc_property_attribute_t(
                name: "T".cstring, value: `propertyTypeEncoding`.cstring
              )
            ]
          if `isReadOnlyProperty`:
            attrs.add(objc_property_attribute_t(name: "R".cstring, value: "".cstring))
          addProperty(
            `protoVar`, `propertyName`, attrs, `isRequiredProperty`,
            `isInstanceProperty`,
          )

  var wrapperDefs = newStmtList()
  var fieldAccessorDefs = newStmtList()
  var callHelperDefs = newStmtList()
  var addClassMethods = newStmtList()
  var addMetaMethods = newStmtList()
  var ensureClassIvars = newStmtList()
  var addExtraProtocols = newStmtList()

  for ivarType in classIvarTypes:
    let ivarTypeNode = copyNimTree(ivarType)
    ensureClassIvars.add quote do:
      doAssert addRefIvar(`clsVar`, ivarRefName[`ivarTypeNode`]())

  for field in classIvarFields:
    let fieldNameLit = newLit(field.name)
    let fieldTypeNode = copyNimTree(field.typ)
    ensureClassIvars.add quote do:
      doAssert addFieldIvar[`fieldTypeNode`](`clsVar`, `fieldNameLit`)

    let selfIdent = ident("self")
    let valueIdent = ident("value")

    let getterName =
      if classExported:
        postfix(ident(field.name), "*")
      else:
        ident(field.name)
    let getterBody = quote:
      result = getIvarFieldVar[`fieldTypeNode`](`selfIdent`, `fieldNameLit`)
    fieldAccessorDefs.add newProc(
      name = getterName,
      params =
        @[
          nnkVarTy.newTree(copyNimTree(fieldTypeNode)),
          newIdentDefs(selfIdent, ident(className), newEmptyNode()),
        ],
      body = getterBody,
      pragmas = nnkPragma.newTree(ident"inline"),
    )

    let setterName =
      if classExported:
        postfix(ident(field.name & "="), "*")
      else:
        ident(field.name & "=")
    let setterBody = quote:
      setIvarField[`fieldTypeNode`](`selfIdent`, `fieldNameLit`, `valueIdent`)
    fieldAccessorDefs.add newProc(
      name = setterName,
      params =
        @[
          newEmptyNode(),
          newIdentDefs(selfIdent, ident(className), newEmptyNode()),
          newIdentDefs(valueIdent, copyNimTree(fieldTypeNode), newEmptyNode()),
        ],
      body = setterBody,
      pragmas = nnkPragma.newTree(ident"inline"),
    )

  for p in implementedProtocols:
    if p == protocolName:
      continue
    let pLit = newLit(objcImplRuntimeName(p))
    addExtraProtocols.add quote do:
      block:
        let p = getProtocol(`pLit`)
        if not p.isNil:
          discard addProtocol(`clsVar`, p)

  for impl in implMethods:
    wrapperDefs.add(impl.implProc)
    wrapperDefs.add(impl.wrapperProc)
    callHelperDefs.add(
      buildObjcCallHelperProc(impl.sourceDef, impl.spec, protocolName, className)
    )
    let selectorName = newLit(impl.spec.selector)
    let typeEncoding = newLit(impl.spec.encoding)
    let wrapperSym = impl.wrapperProc.name
    if impl.spec.methodKind == oimkClass:
      addMetaMethods.add quote do:
        discard addMethod(
          `metaClsVar`,
          selector(`selectorName`),
          cast[IMP](`wrapperSym`),
          `typeEncoding`,
        )
    else:
      addClassMethods.add quote do:
        discard addMethod(
          `clsVar`, selector(`selectorName`), cast[IMP](`wrapperSym`), `typeEncoding`
        )

  result = newStmtList()
  result.add(generatedTypes)
  result.add(fieldAccessorDefs)
  result.add(passthrough)
  result.add(protocolHelperDefs)
  result.add(protocolStructuralDefs)
  result.add(callHelperDefs)
  result.add(wrapperDefs)
  var runtimeSetup = newStmtList()
  if hasClass:
    runtimeSetup.add quote do:
      ensureNutellaRootClasses()

  if hasProtocol and not protocolStructural:
    runtimeSetup.add quote do:
      var `protoVar` = getProtocol(`protoNameLit`)
      if `protoVar`.isNil:
        `protoVar` = allocateProtocol(`protoNameLit`)
        if not `protoVar`.isNil:
          `addMethodDescs`
          `addPropertyDescs`
          registerProtocol(`protoVar`)
          `protoVar` = getProtocol(`protoNameLit`)

  if hasClass:
    var attachPrimaryProto = newStmtList()
    if hasProtocol and not protocolStructural:
      attachPrimaryProto.add quote do:
        if not `protoVar`.isNil:
          discard addProtocol(`clsVar`, `protoVar`)

    if isClassExtensionBlock:
      let extensionMissingClassMsg = newLit(
        "objcImpl class extension requires existing runtime class `" &
          objcImplRuntimeName(className) & "`"
      )
      runtimeSetup.add quote do:
        var `clsVar` = getClass(`classNameLit`)
        doAssert(not `clsVar`.isNil, `extensionMissingClassMsg`)
        let `metaClsVar` = getClass(`clsVar`.value)
        `addClassMethods`
        if not `metaClsVar`.isNil:
          `addMetaMethods`
    else:
      runtimeSetup.add quote do:
        var `clsVar` = getClass(`classNameLit`)
        if `clsVar`.isNil:
          `clsVar` = allocateClassPair(getClass(`superClassNameLit`), `classNameLit`, 0)
          if not `clsVar`.isNil:
            let `metaClsVar` = getClass(`clsVar`.value)
            `ensureClassIvars`
            `attachPrimaryProto`
            `addExtraProtocols`
            `addClassMethods`
            if not `metaClsVar`.isNil:
              `addMetaMethods`
            registerClassPair(`clsVar`)
        else:
          let `metaClsVar` = getClass(`clsVar`.value)
          `ensureClassIvars`
          `attachPrimaryProto`
          `addExtraProtocols`
          `addClassMethods`
          if not `metaClsVar`.isNil:
            `addMetaMethods`

  if runtimeSetup.len > 0:
    result.add quote do:
      block:
        `runtimeSetup`
