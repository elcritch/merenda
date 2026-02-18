import std/[macros, strutils]
import objc/core

export core

type ObjcProtocolMethodSpec = object
  selector: string
  encoding: string

type ObjcImplMethodInfo = object
  spec: ObjcProtocolMethodSpec
  wrapperProc: NimNode
  sourceDef: NimNode

type ObjcImplIvarFieldSpec = object
  name: string
  typ: NimNode

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
    if name == protocolName or name == className:
      result = bindSym"NSObject"
    else:
      result = copyNimTree(typ)

proc objcTypeCodeFromNode(typ: NimNode, protocolName, className: string): string =
  case typ.kind
  of nnkEmpty:
    "v"
  of nnkVarTy, nnkRefTy, nnkDistinctTy:
    objcTypeCodeFromNode(typ[0], protocolName, className)
  of nnkBracketExpr:
    if typ.len == 2 and identName(typ[0]) == "typedesc": "#" else: "@"
  of nnkPtrTy:
    "^" & objcTypeCodeFromNode(typ[0], protocolName, className)
  else:
    let name = identName(typ)
    if name == "char":
      "c"
    elif name == "uint8":
      "C"
    elif name == "int" or name == "cint" or name == "int32":
      "i"
    elif name == "uint" or name == "cuint" or name == "uint32":
      "I"
    elif name == "cshort":
      "s"
    elif name == "cushort":
      "S"
    elif name == "int64":
      "q"
    elif name == "uint64":
      "Q"
    elif name == "cfloat":
      "f"
    elif name == "cdouble":
      "d"
    elif name == "bool":
      "B"
    elif name == "cstring" or name == "string":
      "*"
    elif name == "ObjcClass":
      "#"
    elif name == "NSObject" or name == "ID" or name == protocolName or name == className:
      "@"
    elif name == "SEL":
      ":"
    elif name == "void":
      "v"
    else:
      "@"

proc methodSpecFromDef(
    def: NimNode, protocolName, className: string
): ObjcProtocolMethodSpec =
  if def.kind notin {nnkMethodDef, nnkProcDef}:
    error("objcImpl concept can only contain method/proc declarations", def)

  let methodName = identName(def.name)
  if methodName.len == 0:
    error("objcImpl could not read method name from concept", def)

  let params = def.params
  var totalParams = 0
  var explicitArgCount = 0
  var encoding = objcTypeCodeFromNode(params[0], protocolName, className) & "@:"

  for i in 1 ..< params.len:
    let p = params[i]
    if p.kind != nnkIdentDefs:
      continue
    let typeNode = p[^2]
    let namedCount = p.len - 2
    for _ in 0 ..< namedCount:
      inc totalParams
      if totalParams == 1:
        continue # first arg is the explicit self in Nim surface syntax
      inc explicitArgCount
      encoding.add(objcTypeCodeFromNode(typeNode, protocolName, className))

  result.selector = methodName & ":".repeat(explicitArgCount)
  result.encoding = encoding

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
  identName(params[idx][^2])

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

proc leafTypeName(typ: NimNode): string =
  case typ.kind
  of nnkVarTy, nnkRefTy, nnkDistinctTy, nnkPtrTy:
    leafTypeName(typ[0])
  else:
    identName(typ)

template objcAbiType(T: typedesc): untyped =
  when T is string:
    cstring
  elif T is NSObject:
    ID
  else:
    T

template objcToAbiArg(T: typedesc, v: untyped): untyped =
  when T is string:
    cstring(v)
  elif T is NSObject:
    toID(v)
  else:
    v

template objcFromAbiValue(T: typedesc, v: untyped): untyped =
  when T is string:
    if v.isNil:
      ""
    else:
      $v
  elif T is NSObject:
    asType[T](v)
  else:
    v

proc buildObjcWrapperProc(def: NimNode, protocolName, className: string): NimNode =
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
  let selfName = identName(selfParam[0])
  if selfName.len == 0:
    error("objcImpl could not read implementation self parameter name", def)

  var wrapperParams: seq[NimNode] = @[]
  wrapperParams.add(normalizeObjcNodeType(params[0], protocolName, className))

  let selfIdent = ident(selfName)
  let selfRaw = genSym(nskParam, selfName & "Raw")
  wrapperParams.add(newIdentDefs(selfRaw, bindSym"ID", newEmptyNode()))
  let cmdSel = genSym(nskParam, "cmdSel")
  wrapperParams.add(newIdentDefs(cmdSel, bindSym"SEL", newEmptyNode()))

  var wrapperBody = newStmtList()
  let selfType = ident(className)
  wrapperBody.add quote do:
    var `selfIdent` = asType[`selfType`](`selfRaw`)
  wrapperBody.add quote do:
    discard `selfIdent`
  wrapperBody.add quote do:
    defer:
      wasMoved(`selfIdent`)

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
    let abiType = newCall(bindSym"objcAbiType", normType)
    for j in 0 ..< p.len - 2:
      let argName = copyNimTree(p[j])
      let rawArg = genSym(nskParam, identName(argName) & "Raw")
      wrapperParams.add(newIdentDefs(rawArg, abiType, newEmptyNode()))
      wrapperBody.add quote do:
        when `normType` is NSObject:
          var `argName` = objcFromAbiValue(`normType`, `rawArg`)
          discard `argName`
          defer:
            wasMoved(`argName`)
        else:
          let `argName` = objcFromAbiValue(`normType`, `rawArg`)

  wrapperBody.add quote do:
    discard `cmdSel`

  if def.body.kind == nnkStmtList:
    for stmt in def.body:
      wrapperBody.add(copyNimTree(stmt))
  else:
    wrapperBody.add(copyNimTree(def.body))

  result = newProc(
    name = genSym(nskProc, methodName & "_objcImpl"),
    params = wrapperParams,
    body = wrapperBody,
    pragmas = nnkPragma.newTree(ident"cdecl"),
  )

proc normalizeObjcHelperType(typ: NimNode, protocolName: string): NimNode =
  case typ.kind
  of nnkEmpty:
    result = newEmptyNode()
  of nnkVarTy, nnkRefTy, nnkDistinctTy, nnkPtrTy:
    result = newTree(typ.kind, normalizeObjcHelperType(typ[0], protocolName))
  of nnkBracketExpr:
    result = newNimNode(nnkBracketExpr)
    for c in typ:
      result.add(normalizeObjcHelperType(c, protocolName))
  else:
    let name = identName(typ)
    if name == protocolName:
      result = bindSym"NSObject"
    else:
      result = copyNimTree(typ)

proc buildObjcCallHelperProc(
    def: NimNode, spec: ObjcProtocolMethodSpec, protocolName, className: string
): NimNode =
  let srcParams = def.params
  let helperName = copyNimTree(def.name)
  let selfIdx = firstParamIndex(srcParams)
  if selfIdx < 0:
    error("objcImpl helper generation requires a first `self` parameter", def)

  var helperParams: seq[NimNode] = @[]
  var retType = normalizeObjcHelperType(srcParams[0], protocolName)
  helperParams.add(copyNimTree(retType))
  for i in 1 ..< srcParams.len:
    let p = srcParams[i]
    if p.kind != nnkIdentDefs:
      helperParams.add(copyNimTree(p))
      continue
    var hp = copyNimTree(p)
    hp[^2] = normalizeObjcHelperType(p[^2], protocolName)
    helperParams.add(hp)

  let selfParam = srcParams[selfIdx]
  if selfParam.len != 3:
    error(
      "objcImpl helper generation expects first parameter group to contain one name",
      def,
    )
  let selfName = copyNimTree(selfParam[0])

  let callSel = newCall(bindSym"getSelector", newLit(spec.selector))

  let senderParams = newNimNode(nnkFormalParams)
  let retAbiType =
    if retType.kind == nnkEmpty:
      ident"void"
    else:
      newCall(bindSym"objcAbiType", copyNimTree(retType))
  senderParams.add(retAbiType)
  senderParams.add(newIdentDefs(ident"selfId", bindSym"ID"))
  senderParams.add(newIdentDefs(ident"selector", bindSym"SEL"))

  var callArgs: seq[NimNode] = @[copyNimTree(selfName), callSel]
  var seenSelf = false
  for i in 1 ..< srcParams.len:
    let p = srcParams[i]
    if p.kind != nnkIdentDefs:
      continue
    if not seenSelf:
      seenSelf = true
      continue
    let pType = normalizeObjcHelperType(p[^2], protocolName)
    let abiType = newCall(bindSym"objcAbiType", copyNimTree(pType))
    for j in 0 ..< p.len - 2:
      let argName = copyNimTree(p[j])
      senderParams.add(newIdentDefs(ident("arg" & $i & "_" & $j), abiType))
      callArgs.add(newCall(bindSym"objcToAbiArg", copyNimTree(pType), argName))

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
      result = objcFromAbiValue(`retType`, `callExpr`)

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
      fields.add ObjcImplIvarFieldSpec(name: fName, typ: copyNimTree(fieldType))

macro objcImpl*(x: untyped): untyped =
  let input =
    if x.kind == nnkStmtList:
      x
    else:
      newStmtList(x)

  var protocolName = ""
  var className = ""
  var classSuperName = ""
  var classImplProtocols: seq[string] = @[]
  var classIvarTypes: seq[NimNode] = @[]
  var classIvarFields: seq[ObjcImplIvarFieldSpec] = @[]
  var conceptBody = newEmptyNode()
  var implementedProtocols: seq[string] = @[]

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
          conceptBody = body[^1]
        of nnkObjectTy:
          className = name
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
  let hasClass = className.len > 0
  if not hasProtocol and not hasClass:
    error(
      "objcImpl requires at least one declaration: protocol concept and/or class object",
      x,
    )

  if hasClass and classSuperName.len == 0:
    error("objcImpl class declaration must include a superclass", x)

  implementedProtocols = classImplProtocols
  if hasProtocol and hasClass:
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

  if hasProtocol and conceptBody.kind != nnkStmtList:
    error("objcImpl protocol concept body is missing method declarations", x)

  var protocolSpecs: seq[ObjcProtocolMethodSpec] = @[]
  if hasProtocol:
    for conceptStmt in conceptBody:
      protocolSpecs.add(methodSpecFromDef(conceptStmt, protocolName, className))

  var generatedTypes = newStmtList()
  var generatedTypeLines: seq[string] = @[]
  if hasProtocol:
    generatedTypeLines.add("  " & protocolName & " = object of ProtocolPrototype")
  if hasClass:
    generatedTypeLines.add("  " & className & " = object of " & classSuperName)
  if generatedTypeLines.len > 0:
    generatedTypes = parseStmt("type\n" & generatedTypeLines.join("\n"))

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
            (hasClass and name == className and body.kind == nnkObjectTy):
          continue
        filtered.add(copyNimTree(def))
      if filtered.len > 0:
        passthrough.add(filtered)
    of nnkCommand, nnkCall:
      passthrough.add(copyNimTree(stmt))
    of nnkMethodDef, nnkProcDef:
      if hasClass and firstParamTypeName(stmt) == className and not hasErrorPragma(stmt):
        implDefs.add(stmt)
      else:
        passthrough.add(copyNimTree(stmt))
    else:
      passthrough.add(copyNimTree(stmt))

  var implMethods: seq[ObjcImplMethodInfo] = @[]
  for def in implDefs:
    implMethods.add ObjcImplMethodInfo(
      spec: methodSpecFromDef(def, protocolName, className),
      wrapperProc: buildObjcWrapperProc(def, protocolName, className),
      sourceDef: def,
    )

  for i in 0 ..< implMethods.len:
    for j in i + 1 ..< implMethods.len:
      if implMethods[i].spec.selector == implMethods[j].spec.selector:
        error(
          "objcImpl found duplicate implementation for selector `" &
            implMethods[i].spec.selector & "`",
          implMethods[j].sourceDef,
        )

  if hasProtocol and hasClass:
    for pSpec in protocolSpecs:
      var found = false
      for impl in implMethods:
        if impl.spec.selector != pSpec.selector:
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
          "objcImpl missing implementation for required protocol method `" &
            pSpec.selector & "`",
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
      newLit(protocolName)
    else:
      newEmptyNode()
  let classNameLit =
    if hasClass:
      newLit(className)
    else:
      newEmptyNode()
  let superClassNameLit =
    if hasClass:
      newLit(classSuperName)
    else:
      newEmptyNode()
  var addMethodDescs = newStmtList()
  if hasProtocol:
    for spec in protocolSpecs:
      let selectorName = newLit(spec.selector)
      let typeEncoding = newLit(spec.encoding)
      addMethodDescs.add quote do:
        addMethodDescription(
          `protoVar`, selector(`selectorName`), `typeEncoding`, true, true
        )

  var wrapperDefs = newStmtList()
  var fieldAccessorDefs = newStmtList()
  var callHelperDefs = newStmtList()
  var addClassMethods = newStmtList()
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
      doAssert addRefIvar(`clsVar`, `fieldNameLit`)

    let getterName = ident(field.name)
    let setterName = ident(field.name & "=")
    let selfIdent = ident("self")
    let valueIdent = ident("value")
    let getterBody = quote:
      result = getIvarRef[`fieldTypeNode`](`selfIdent`, `fieldNameLit`)
    let setterBody = quote:
      setIvarRef[`fieldTypeNode`](`selfIdent`, `fieldNameLit`, `valueIdent`)

    fieldAccessorDefs.add newProc(
      name = getterName,
      params =
        @[
          copyNimTree(fieldTypeNode),
          newIdentDefs(selfIdent, ident(className), newEmptyNode()),
        ],
      body = getterBody,
      pragmas = nnkPragma.newTree(ident"inline"),
    )

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
    let pLit = newLit(p)
    addExtraProtocols.add quote do:
      block:
        let p = getProtocol(`pLit`)
        if not p.isNil:
          discard addProtocol(`clsVar`, p)

  for impl in implMethods:
    wrapperDefs.add(impl.wrapperProc)
    callHelperDefs.add(
      buildObjcCallHelperProc(impl.sourceDef, impl.spec, protocolName, className)
    )
    let selectorName = newLit(impl.spec.selector)
    let typeEncoding = newLit(impl.spec.encoding)
    let wrapperSym = impl.wrapperProc.name
    addClassMethods.add quote do:
      discard addMethod(
        `clsVar`, selector(`selectorName`), cast[IMP](`wrapperSym`), `typeEncoding`
      )

  result = newStmtList()
  result.add(generatedTypes)
  result.add(fieldAccessorDefs)
  result.add(passthrough)
  result.add(callHelperDefs)
  result.add(wrapperDefs)
  var runtimeSetup = newStmtList()
  if hasProtocol:
    runtimeSetup.add quote do:
      var `protoVar` = getProtocol(`protoNameLit`)
      if `protoVar`.isNil:
        `protoVar` = allocateProtocol(`protoNameLit`)
        if not `protoVar`.isNil:
          `addMethodDescs`
          registerProtocol(`protoVar`)
          `protoVar` = getProtocol(`protoNameLit`)

  if hasClass:
    var attachPrimaryProto = newStmtList()
    if hasProtocol:
      attachPrimaryProto.add quote do:
        if not `protoVar`.isNil:
          discard addProtocol(`clsVar`, `protoVar`)

    runtimeSetup.add quote do:
      var `clsVar` = getClass(`classNameLit`)
      if `clsVar`.isNil:
        `clsVar` = allocateClassPair(getClass(`superClassNameLit`), `classNameLit`, 0)
        if not `clsVar`.isNil:
          `ensureClassIvars`
          `attachPrimaryProto`
          `addExtraProtocols`
          `addClassMethods`
          registerClassPair(`clsVar`)
      else:
        `ensureClassIvars`
        `attachPrimaryProto`
        `addExtraProtocols`
        `addClassMethods`

  if runtimeSetup.len > 0:
    result.add quote do:
      block:
        `runtimeSetup`
