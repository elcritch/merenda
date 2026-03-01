# Modification of darwin/src/objc/runtime.nim
#
# Copyright (c) 2017 Yuriy Glukhov
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import std/[macros, strutils]

{.passL: "-lobjc".}
template impl*(x: untyped) {.pragma.}

const KNutellaNsToNxRemapEnabled* =
  defined(macosx) and not defined(nutellaDisableNsToNxRemap)
const KNutellaUseCustomNxObjectRoot* = defined(nutellaCustomNxObjectRoot)

const
  YES* = true
  NO* = false

type
  IDPtr* = pointer

  ID* {.pure, inheritable.} = object
    value*: IDPtr

  NSObject* = object of ID
  ObjcProtocolObject* {.pure, inheritable.} = object of ID

  ObjcClass* {.pure.} = object of NSObject

  NSString* = object of NSObject
  NSArray*[T] = object of NSObject
  NSDictionary*[K, V] = object of NSObject

  ProtocolPrototype* {.pure, inheritable.} = object

  Method* = distinct pointer
  Ivar* = distinct pointer
  Category* = distinct pointer
  IMP* = proc(id: IDPtr, selector: SEL): IDPtr {.cdecl, varargs.}
  Protocol* = distinct pointer
  SEL* = ptr object
  STR* = ptr char
  arith_t* = int
  uarith_t* = uint
  ptrdiff_t* = int
  BOOL* = bool

  NSInteger* = int
  NSUInteger* = uint

  objc_method_description = object
    name: SEL
    types: cstring

  MethodDescription* = object
    name*: SEL
    types*: string

  Property* = distinct pointer

  ObjcSuper* = object
    receiver*: IDPtr
    superClass*: ObjcClass

  objc_property_attribute_t* = object
    name*: cstring
    value*: cstring

  PropertyAttribute* = object
    name*: string
    value*: string

  objc_exception_functions_t* = object
    version: cint
    throw_exc: proc(id: IDPtr) {.cdecl.}
    try_enter: proc(p: pointer) {.cdecl.}
    try_exit: proc(p: pointer) {.cdecl.}
    extract: proc(p: pointer): IDPtr {.cdecl.}
    match: proc(class: ObjcClass, id: IDPtr): cint {.cdecl.}

  objc_AssociationPolicy* {.size: sizeof(cuint).} = enum
    OBJC_ASSOCIATION_ASSIGN = 0
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    OBJC_ASSOCIATION_RETAIN = 01401
    OBJC_ASSOCIATION_COPY = 01403

proc retainAux(o: IDPtr): IDPtr {.raises: [].}
proc retainRaw(o: IDPtr) {.raises: [].}
proc releaseAux(o: IDPtr) {.raises: [].}
proc retainCountAux(o: IDPtr): NSUInteger {.raises: [].}

proc `=destroy`*(o: var ID) =
  if o.value != nil:
    releaseAux(o.value)
    o.value = nil

proc `=copy`*(dest: var ID, src: ID) =
  if dest.value == src.value:
    return
  `=destroy`(dest)
  dest.value = src.value
  if dest.value != nil:
    retainRaw(dest.value)

proc `=sink`*(dest: var ID, src: ID) =
  if dest.value == src.value:
    return
  `=destroy`(dest)
  dest.value = src.value

proc `=destroy`*(o: var ObjcClass) =
  o.value = nil

proc `=copy`*(dest: var ObjcClass, src: ObjcClass) =
  dest.value = src.value

proc `=sink`*(dest: var ObjcClass, src: ObjcClass) =
  dest.value = src.value

proc GC_ref*[T: ID](o: T) =
  retainAux(o.value)

proc GC_unref*[T: ID](o: T) =
  releaseAux(o.value)

template retain*[T: ID](o: T): T =
  cast[T](retainAux(o.value))

proc release*(o: var ID) {.inline.} =
  `=destroy`(o)

proc release*(o: ID) {.inline.} =
  if o.value != nil:
    releaseAux(o.value)

template retainCount*(o: ID): NSUInteger =
  retainCountAux(o.value)

proc isNil*(a: ID): bool =
  result = a.value == nil

proc isNil*(a: Protocol): bool =
  cast[pointer](a) == nil

proc notNil*(a: ID): bool =
  result = a.value != nil

proc notNil*(a: Protocol): bool =
  cast[pointer](a) != nil

converter toID*(o: ID): IDPtr {.inline.} =
  o.value

converter toNSObject*(id: IDPtr): NSObject {.inline.} =
  NSObject(value: id)

converter toObjcClass*(id: IDPtr): ObjcClass {.inline.} =
  ObjcClass(value: id)

template asTypeRaw*[T: ID](o: IDPtr): T =
  T(value: o)

template asTypeRaw*[T: ID](o: ID): T =
  T(value: o.value)

template asType[T: ID](o: IDPtr): T =
  if o == nil:
    T(value: nil)
  else:
    T(value: retainAux(o))

template asType[T: ID](o: ID): T =
  if o.value == nil:
    T(value: nil)
  else:
    T(value: retainAux(o.value))

proc `as`*[T](o: IDPtr, v: typedesc[T]): T =
  asType[T](o)

proc `as`*[T](o: ID, v: typedesc[T]): T =
  asType[T](o)

proc `to`*[T](o: ID, v: typedesc[T]): T =
  asType[T](o)

proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}
proc sel_registerName*(str: cstring): SEL {.cdecl, importc.}
proc objc_msgSend*(self: IDPtr, op: SEL): IDPtr {.cdecl, importc, discardable, varargs.}

proc objc_msgSend_fpret*(self: IDPtr, op: SEL): cdouble {.cdecl, importc, varargs.}
proc objc_msgSend_stret*(self: IDPtr, op: SEL) {.cdecl, importc, varargs.}
proc objc_msgSendSuper*(
  super: var ObjcSuper, op: SEL
): IDPtr {.cdecl, importc, varargs.}

proc objc_msgSendSuper_stret*(super: var ObjcSuper, op: SEL) {.cdecl, importc, varargs.}

proc class_getName(cls: IDPtr): cstring {.cdecl, importc.}
proc getName*(cls: ObjcClass): string =
  if cls.isNil:
    return "<nil ObjcClass>"
  let name = class_getName(cls)
  if name.isNil:
    return "<unknown ObjcClass>"
  result = $name

proc `$`*(cls: ObjcClass): string =
  getName(cls)

proc class_getSuperclass(cls: IDPtr): ObjcClass {.cdecl, importc.}
template getSuperclass*(cls: ObjcClass): untyped =
  class_getSuperClass(cls)

proc class_isMetaClass(cls: IDPtr): bool {.cdecl, importc.}
template isMetaClass*(cls: ObjcClass): untyped =
  class_isMetaClass(cls)

proc class_getInstanceSize(cls: IDPtr): csize_t {.cdecl, importc.}
proc getInstanceSize*(cls: ObjcClass): int =
  class_getInstanceSize(cls).int

proc class_getInstanceVariable(cls: IDPtr, name: cstring): Ivar {.cdecl, importc.}
template getIvar*(cls: ObjcClass, name: string): untyped =
  class_getInstanceVariable(cls, name.cstring)

proc class_getClassVariable(cls: IDPtr, name: cstring): Ivar {.cdecl, importc.}
template getClassVariable*(cls: ObjcClass, name: string): untyped =
  class_getClassVariable(cls, name.cstring)

proc class_addIvar(
  cls: IDPtr, name: cstring, size: csize_t, alignment: uint8, types: cstring
): bool {.cdecl, importc.}

proc addIvar*(
    cls: ObjcClass, name: string, size: int, alignment: int, types: string
): bool =
  class_addIvar(cls, name.cstring, size.csize_t, alignment.uint8, types.cstring) == YES

proc class_copyIvarList(cls: IDPtr, outCount: var cuint): ptr Ivar {.cdecl, importc.}

proc ivarList*(cls: ObjcClass): seq[Ivar] =
  var
    count = 0.cuint
    ivars = class_copyIvarList(cls, count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[Ivar](count)
  copyMem(result[0].addr, ivars, sizeof(Ivar) * count.int)
  c_free(ivars)

proc class_getIvarLayout*(cls: IDPtr): ptr uint8 {.cdecl, importc.}
proc class_getWeakIvarLayout*(cls: IDPtr): ptr uint8 {.cdecl, importc.}
proc class_setIvarLayout*(cls: IDPtr, layout: ptr uint8) {.cdecl, importc.}
proc class_setWeakIvarLayout*(cls: IDPtr, layout: ptr uint8) {.cdecl, importc.}

proc class_getProperty(cls: IDPtr, name: cstring): Property {.cdecl, importc.}
template getProperty*(cls: ObjcClass, name: string): untyped =
  class_getProperty(cls, name.cstring)

proc class_copyPropertyList*(
  cls: IDPtr, outCount: var cuint
): ptr Property {.cdecl, importc.}

proc propertyList*(cls: ObjcClass): seq[Property] =
  var
    count = 0.cuint
    props = class_copyPropertyList(cls, count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[Property](count)
  copyMem(result[0].addr, props, sizeof(Property) * count.int)
  c_free(props)

proc class_addMethod(
  cls: IDPtr, name: SEL, imp: IMP, types: cstring
): bool {.cdecl, importc.}

template addMethod*(cls: ObjcClass, name: SEL, imp: IMP, types: string): bool =
  class_addMethod(cls, name, imp, types.cstring)

proc class_getInstanceMethod(cls: IDPtr, name: SEL): Method {.cdecl, importc.}
template getInstanceMethod*(cls: ObjcClass, name: SEL): Method =
  class_getInstanceMethod(cls, name)

proc class_getClassMethod(cls: IDPtr, name: SEL): Method {.cdecl, importc.}
template getClassMethod*(cls: ObjcClass, name: SEL): Method =
  class_getClassMethod(cls, name)

proc class_copyMethodList(
  cls: IDPtr, outCount: var cuint
): ptr Method {.cdecl, importc.}

proc methodList*(cls: ObjcClass): seq[Method] =
  var
    count = 0.cuint
    procs = class_copyMethodList(cls, count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[Method](count)
  copyMem(result[0].addr, procs, sizeof(Method) * count.int)
  c_free(procs)

proc class_replaceMethod(
  cls: IDPtr, name: SEL, imp: IMP, types: cstring
): IMP {.cdecl, importc.}

template replaceMethod*(cls: ObjcClass, name: SEL, imp: IMP, types: string): untyped =
  class_replaceMethod(cls, name, imp, types.cstring)

proc class_getMethodImplementation(cls: IDPtr, name: SEL): IMP {.cdecl, importc.}
template getMethodImplementation*(cls: ObjcClass, name: SEL): untyped =
  class_getMethodImplementation(cls, name)

proc class_getMethodImplementation_stret*(cls: IDPtr, name: SEL): IMP {.cdecl, importc.}

proc class_respondsToSelector(cls: IDPtr, sel: SEL): bool {.cdecl, importc.}
template respondsToSelector*(cls: ObjcClass, sel: SEL): untyped =
  class_respondsToSelector(cls, sel)

proc class_addProtocol(cls: IDPtr, protocol: Protocol): bool {.cdecl, importc.}
template addProtocol*(cls: ObjcClass, protocol: Protocol): untyped =
  class_addProtocol(cls, protocol)

proc class_addProperty(
  cls: IDPtr,
  name: cstring,
  attributes: ptr objc_property_attribute_t,
  attributeCount: cuint,
): bool {.cdecl, importc.}

proc addProperty*(
    cls: ObjcClass, name: string, attributes: openArray[objc_property_attribute_t]
): bool =
  class_addProperty(cls, name.cstring, attributes[0].unsafeAddr, attributes.len.cuint) ==
    YES

proc class_replaceProperty(
  cls: IDPtr,
  name: cstring,
  attributes: ptr objc_property_attribute_t,
  attributeCount: cuint,
) {.cdecl, importc.}

proc replaceProperty*(
    cls: ObjcClass, name: string, attributes: openArray[objc_property_attribute_t]
) =
  class_replaceProperty(
    cls, name.cstring, attributes[0].unsafeAddr, attributes.len.cuint
  )

proc class_conformsToProtocol(cls: IDPtr, protocol: Protocol): bool {.cdecl, importc.}

template conformsToProtocol*(cls: ObjcClass, protocol: Protocol): bool =
  class_conformsToProtocol(cls, protocol) == YES

proc class_copyProtocolList(
  cls: IDPtr, outCount: var cuint
): ptr Protocol {.cdecl, importc.}

proc protocolList*(cls: ObjcClass): seq[Protocol] =
  var
    count = 0.cuint
    prots = class_copyProtocolList(cls, count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[Protocol](count)
  copyMem(result[0].addr, prots, sizeof(Protocol) * count.int)
  c_free(prots)

proc class_getVersion(cls: IDPtr): cint {.cdecl, importc.}
template getVersion*(cls: ObjcClass): untyped =
  class_getVersion(cls).int

proc class_setVersion(cls: IDPtr, version: cint) {.cdecl, importc.}
template setVersion*(cls: ObjcClass, version: int) =
  class_setVersion(cls, version.cint)

proc objc_getFutureClass(name: cstring): ObjcClass {.cdecl, importc.}
template getFutureClass*(name: string): untyped =
  objc_getFutureClass(name.cstring)

proc objc_allocateClassPair(
  superclass: IDPtr, name: cstring, extraBytes: csize_t
): IDPtr {.cdecl, importc.}

template allocateClassPair*(
    superclass: ObjcClass, name: string, extraBytes: int
): untyped =
  toObjcClass(objc_allocateClassPair(superclass, name.cstring, extrabytes.csize_t))

proc objc_disposeClassPair(cls: IDPtr) {.cdecl, importc.}
template disposeClassPair*(cls: ObjcClass) =
  objc_disposeClassPair(cls)

proc objc_registerClassPair(cls: IDPtr) {.cdecl, importc.}
template registerClassPair*(cls: ObjcClass) =
  objc_registerClassPair(cls)

proc objc_duplicateClass(
  original: ObjcClass, name: cstring, extraBytes: csize_t
): ObjcClass {.cdecl, importc.}

template duplicateClass*(original: ObjcClass, name: string, extraBytes: int): untyped =
  objc_duplicateClass(original, name.cstring, extraBytes.csize_t)

proc class_createInstance(cls: IDPtr, extraBytes: csize_t): IDPtr {.cdecl, importc.}
template createInstance*(cls: ObjcClass, extraBytes: csize_t): untyped =
  class_createInstance(cls, extraBytes.csize_t)

proc objc_constructInstance(cls: IDPtr, bytes: pointer): IDPtr {.cdecl, importc.}
template constructInstance*(cls: ObjcClass, bytes: pointer): untyped =
  objc_constructInstance(cls, bytes)

proc objc_destructInstance(obj: IDPtr): pointer {.cdecl, importc.}
template destructInstance*(obj: IDPtr): untyped =
  objc_destructInstance(obj)

proc object_copy(obj: IDPtr, size: csize_t): IDPtr {.cdecl, importc.}
template copy*(obj: IDPtr, size: csize_t): untyped =
  object_copy(obj, size.csize_t)

proc object_dispose(obj: IDPtr): IDPtr {.cdecl, importc.}
template dispose*(obj: IDPtr): untyped =
  object_dispose(obj)

proc object_setInstanceVariable(
  obj: IDPtr, name: cstring, value: pointer
): Ivar {.cdecl, importc.}

template setInstanceVariable*(obj: IDPtr, name: string, value: pointer): untyped =
  object_setInstanceVariable(obj, name.cstring, value)

proc object_getInstanceVariable(
  obj: IDPtr, name: cstring, outValue: var pointer
): Ivar {.cdecl, importc.}

template getInstanceVariable*(
    obj: IDPtr, name: string, outValue: var pointer
): untyped =
  object_getInstanceVariable(obj, name.cstring, outValue)

proc object_getIndexedIvars(obj: IDPtr): pointer {.cdecl, importc.}
template getIndexedIvars*(obj: IDPtr): untyped =
  object_getIndexedIvars(obj)

proc object_getIvar(obj: IDPtr, ivar: Ivar): IDPtr {.cdecl, importc.}
template getIvar*(obj: IDPtr, ivar: Ivar): untyped =
  object_getIvar(obj, ivar)

proc object_setIvar(obj: IDPtr, ivar: Ivar, value: IDPtr) {.cdecl, importc.}
template setIvar*(obj: IDPtr, ivar: Ivar, value: IDPtr) =
  object_setIvar(obj, ivar, value)

proc object_getClassName(obj: IDPtr): cstring {.cdecl, importc.}
proc object_getClass(obj: IDPtr): ObjcClass {.cdecl, importc.}
proc ivar_getOffset(v: Ivar): ptrdiff_t {.cdecl, importc.}
proc getRawClassName*(obj: IDPtr): string =
  $object_getClassName(obj)

template getClassName*[T: ID](obj: T): string =
  $object_getClassName(obj.value)

proc nutellaNsToNxRuntimeName*(name: string): string {.inline.} =
  result = name
  when KNutellaNsToNxRemapEnabled:
    if name.len > 2 and name.startsWith("NS"):
      case name
      of "NSObject":
        when KNutellaUseCustomNxObjectRoot:
          result = "NXObject"
      of "NSProxy", "NSCopying", "NSMutableCopying", "NSCoding", "NSSecureCoding":
        discard
      else:
        result = "NX" & name[2 .. ^1]

proc objc_getClass(name: cstring): ObjcClass {.cdecl, importc.}
proc ensureNutellaRootClasses*()

var nxObjectRefCountOffset {.global.}: ptrdiff_t = -1

proc nxObjectRefCountPtr(obj: IDPtr): ptr NSUInteger {.inline, raises: [].} =
  if obj == nil or nxObjectRefCountOffset < 0:
    return nil
  cast[ptr NSUInteger](cast[uint](obj) + cast[uint](nxObjectRefCountOffset))

proc nxObjectReadRefCount(obj: IDPtr): NSUInteger {.inline, raises: [].} =
  let p = nxObjectRefCountPtr(obj)
  if p == nil:
    return 0.NSUInteger
  p[]

proc nxObjectWriteRefCount(obj: IDPtr, value: NSUInteger) {.inline, raises: [].} =
  let p = nxObjectRefCountPtr(obj)
  if p != nil:
    p[] = value

proc nxObjectAlloc(self: IDPtr, cmd: SEL): IDPtr {.cdecl, raises: [].} =
  result = class_createInstance(self, 0)
  if result != nil:
    nxObjectWriteRefCount(result, 1.NSUInteger)

proc nxObjectInit(self: IDPtr, cmd: SEL): IDPtr {.cdecl, raises: [].} =
  if nxObjectReadRefCount(self) == 0.NSUInteger:
    nxObjectWriteRefCount(self, 1.NSUInteger)
  result = self

proc nxObjectRetain(self: IDPtr, cmd: SEL): IDPtr {.cdecl, raises: [].} =
  let rc = nxObjectReadRefCount(self)
  nxObjectWriteRefCount(self, rc + 1.NSUInteger)
  result = self

proc nxObjectDealloc(self: IDPtr, cmd: SEL): IDPtr {.cdecl, raises: [].} =
  nxObjectWriteRefCount(self, 0.NSUInteger)
  discard object_dispose(self)
  result = nil

proc nxObjectRelease(self: IDPtr, cmd: SEL) {.cdecl, raises: [].} =
  let rc = nxObjectReadRefCount(self)
  if rc <= 1.NSUInteger:
    discard objc_msgSend(self, sel_registerName("dealloc"))
  else:
    nxObjectWriteRefCount(self, rc - 1.NSUInteger)

proc nxObjectRetainCount(self: IDPtr, cmd: SEL): NSUInteger {.cdecl, raises: [].} =
  result = nxObjectReadRefCount(self)

proc nxObjectAutorelease(self: IDPtr, cmd: SEL): IDPtr {.cdecl, raises: [].} =
  result = self

proc nxObjectIsEqual(self: IDPtr, cmd: SEL, other: IDPtr): bool {.cdecl, raises: [].} =
  self == other

proc nxObjectHash(self: IDPtr, cmd: SEL): NSUInteger {.cdecl, raises: [].} =
  cast[NSUInteger](cast[uint](self) shr 4)

proc nxObjectRespondsToSelector(
    self: IDPtr, cmd: SEL, selector: SEL
): bool {.cdecl, raises: [].} =
  class_respondsToSelector(object_getClass(self), selector)

proc nxObjectIsKindOfClass(
    self: IDPtr, cmd: SEL, cls: IDPtr
): bool {.cdecl, raises: [].} =
  if cls == nil:
    return false
  var current = object_getClass(self)
  while not current.isNil:
    if current.value == cls:
      return true
    current = class_getSuperclass(current.value)
  false

proc nxObjectNew(self: IDPtr, cmd: SEL): IDPtr {.cdecl, raises: [].} =
  var allocated = nxObjectAlloc(self, cmd)
  if allocated == nil:
    return nil
  result = objc_msgSend(allocated, sel_registerName("init"))

proc nxObjectInitialize(self: IDPtr, cmd: SEL) {.cdecl, raises: [].} =
  discard

proc ensureNutellaRootClasses*() =
  ## Bootstraps a standalone NXObject root class when custom root mode is enabled.
  when KNutellaUseCustomNxObjectRoot:
    let nxObjectName = "NXObject"
    var nxObject = objc_getClass(nxObjectName.cstring)
    if nxObject.isNil:
      nxObject = toObjcClass(objc_allocateClassPair(nil, nxObjectName.cstring, 0))
      if nxObject.isNil:
        return

      const nxRefAlign =
        when sizeof(NSUInteger) == 8:
          3
        elif sizeof(NSUInteger) == 4:
          2
        else:
          1

      discard
        addIvar(nxObject, "__nutellaNxRefCount", sizeof(NSUInteger), nxRefAlign, "Q")

      let nxMeta = object_getClass(nxObject.value)
      discard class_addMethod(
        nxMeta.value, sel_registerName("alloc"), cast[IMP](nxObjectAlloc), "@@:"
      )
      discard class_addMethod(
        nxMeta.value, sel_registerName("new"), cast[IMP](nxObjectNew), "@@:"
      )
      discard class_addMethod(
        nxMeta.value,
        sel_registerName("initialize"),
        cast[IMP](nxObjectInitialize),
        "v@:",
      )
      discard class_addMethod(
        nxObject.value, sel_registerName("init"), cast[IMP](nxObjectInit), "@@:"
      )
      discard class_addMethod(
        nxObject.value, sel_registerName("retain"), cast[IMP](nxObjectRetain), "@@:"
      )
      discard class_addMethod(
        nxObject.value, sel_registerName("release"), cast[IMP](nxObjectRelease), "v@:"
      )
      discard class_addMethod(
        nxObject.value,
        sel_registerName("retainCount"),
        cast[IMP](nxObjectRetainCount),
        "Q@:",
      )
      discard class_addMethod(
        nxObject.value,
        sel_registerName("autorelease"),
        cast[IMP](nxObjectAutorelease),
        "@@:",
      )
      discard class_addMethod(
        nxObject.value, sel_registerName("isEqual:"), cast[IMP](nxObjectIsEqual), "B@:@"
      )
      discard class_addMethod(
        nxObject.value, sel_registerName("hash"), cast[IMP](nxObjectHash), "Q@:"
      )
      discard class_addMethod(
        nxObject.value,
        sel_registerName("respondsToSelector:"),
        cast[IMP](nxObjectRespondsToSelector),
        "B@::",
      )
      discard class_addMethod(
        nxObject.value,
        sel_registerName("isKindOfClass:"),
        cast[IMP](nxObjectIsKindOfClass),
        "B@:#",
      )
      discard class_addMethod(
        nxObject.value, sel_registerName("dealloc"), cast[IMP](nxObjectDealloc), "v@:"
      )
      objc_registerClassPair(nxObject.value)

    if nxObjectRefCountOffset < 0:
      let refIvar = getIvar(nxObject, "__nutellaNxRefCount")
      if cast[pointer](refIvar) != nil:
        nxObjectRefCountOffset = ivar_getOffset(refIvar)

proc getClassByName*(name: string): ObjcClass =
  when KNutellaNsToNxRemapEnabled:
    let mapped = nutellaNsToNxRuntimeName(name)
    if mapped != name:
      ensureNutellaRootClasses()
      result = objc_getClass(mapped.cstring)
      if not result.isNil:
        return
  result = objc_getClass(name.cstring)

template getClass*(name: string): untyped =
  getClassByName(name)

template getClass*[T: NSObject](t: typedesc[T]): untyped =
  getClassByName($T)

proc object_setClass(obj: IDPtr, cls: IDPtr): ObjcClass {.cdecl, importc.}
template setClass*(obj: IDPtr, cls: ObjcClass): untyped =
  object_setClass(obj, cls)

proc objc_getClassList(
  buffer: ptr ObjcClass, bufferCount: cint
): cint {.cdecl, importc.}

proc getClassList*(): seq[ObjcClass] =
  let count = objc_getClassList(nil, 0.cint)
  if count == 0:
    result = @[]
    return result
  result = newSeq[ObjcClass](count)
  discard objc_getClassList(result[0].addr, result.len.cint)

proc objc_copyClassList(outCount: var cuint): ptr ObjcClass {.cdecl, importc.}

proc copyClassList*(): seq[ObjcClass] =
  var
    count = 0.cuint
    classes = objc_copyClassList(count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[ObjcClass](count)
  copyMem(result[0].addr, classes, sizeof(ObjcClass) * count.int)
  c_free(classes)

proc objc_lookUpClass(name: cstring): ObjcClass {.cdecl, importc.}
template lookUpClass*(name: cstring): untyped =
  objc_lookUpClass(name.cstring)

template getClass*(obj: IDPtr): untyped =
  object_getClass(obj)

proc objc_getRequiredClass(name: cstring): ObjcClass {.cdecl, importc.}
template getRequiredClass*(name: string): untyped =
  objc_getRequiredClass(name.cstring)

proc objc_getMetaClass(name: cstring): ObjcClass {.cdecl, importc.}
template getMetaClass*(name: string): untyped =
  objc_getMetaClass(name.cstring)

proc ivar_getName(v: Ivar): cstring {.cdecl, importc.}
template getName*(v: Ivar): untyped =
  $ivar_getName(v)

proc `$`*(v: Ivar): string =
  getName(v)

proc ivar_getTypeEncoding(v: Ivar): cstring {.cdecl, importc.}
template getTypeEncoding*(v: Ivar): untyped =
  $ivar_getTypeEncoding(v)

template getOffset*(v: Ivar): untyped =
  ivar_getOffset(v)

proc objc_setAssociatedObject(
  obj: IDPtr, key: pointer, value: IDPtr, policy: objc_AssociationPolicy
) {.cdecl, importc.}

template setAssociatedObject*(
    obj: IDPtr, key: pointer, value: IDPtr, policy: objc_AssociationPolicy
) =
  objc_setAssociatedObject(obj, key, value, policy)

proc objc_getAssociatedObject(obj: IDPtr, key: pointer): IDPtr {.cdecl, importc.}
template getAssociatedObject*(obj: IDPtr, key: pointer): untyped =
  objc_getAssociatedObject(obj, key)

proc objc_removeAssociatedObjects(obj: IDPtr) {.cdecl, importc.}
template removeAssociatedObjects*(obj: IDPtr) =
  objc_removeAssociatedObjects(obj)

proc method_invoke*(receiver: IDPtr, m: Method): IDPtr {.cdecl, importc, varargs.}
proc method_invoke_stret*(receiver: IDPtr, m: Method) {.cdecl, importc, varargs.}

proc sel_getName*(sel: SEL): cstring {.cdecl, importc.}
template getName*(sel: SEL): untyped =
  $sel_getName(sel)

proc `$`*(sel: SEL): string =
  getName(sel)

template registerName*(str: string): untyped =
  sel_registerName(str.cstring)

proc `$$`*(str: string): SEL =
  sel_registerName(str.cstring)

proc sel_getUid(str: cstring): SEL {.cdecl, importc.}
template getUid*(str: string): untyped =
  sel_getUid(str.cstring)

proc sel_isEqual(lhs: SEL, rhs: SEL): bool {.cdecl, importc.}
template isEqual*(lhs, rhs: SEL): untyped =
  sel_isEqual(lhs, rhs)

proc method_getName(m: Method): SEL {.cdecl, importc.}
template getName*(m: Method): untyped =
  $method_getName(m)

proc `$`*(m: Method): string =
  getName(m)

proc method_getImplementation(m: Method): IMP {.cdecl, importc.}
template getImplementation*(m: Method): untyped =
  method_getImplementation(m)

proc method_getTypeEncoding(m: Method): cstring {.cdecl, importc.}
template getTypeEncoding*(m: Method): untyped =
  $method_getTypeEncoding(m)

proc method_copyReturnType(m: Method): cstring {.cdecl, importc.}
proc copyReturnType*(m: Method): string =
  var ret = method_copyReturnType(m)
  result = $ret
  c_free(ret)

proc method_copyArgumentType(m: Method, index: cuint): cstring {.cdecl, importc.}
proc copyArgumentType*(m: Method, index: int): string =
  var ret = method_copyArgumentType(m, index.cuint)
  result = $ret
  c_free(ret)

proc method_getReturnType(m: Method, dst: cstring, dst_len: csize_t) {.cdecl, importc.}
proc getReturnType*(m: Method): string =
  var ret: array[100, char]
  method_getReturnType(m, cast[cstring](ret[0].addr), sizeof(ret).csize_t)
  result = $(cast[cstring](ret[0].addr))

proc method_getNumberOfArguments(m: Method): cuint {.cdecl, importc.}
template getNumberOfArguments*(m: Method): untyped =
  method_getNumberOfArguments(m).int

proc method_getArgumentType(
  m: Method, index: cuint, dst: cstring, dst_len: csize_t
) {.cdecl, importc.}

proc getArgumentType*(m: Method, index: int): string =
  var ret: array[100, char]
  method_getArgumentType(
    m, index.cuint, cast[cstring](ret[0].addr), sizeof(ret).csize_t
  )
  result = $(cast[cstring](ret[0].addr))

proc argumentTypes*(m: Method): seq[string] =
  let count = getNumberOfArguments(m)
  result = newSeq[string](count)
  if count == 0:
    result = @[]
    return result
  for i in 0 ..< count:
    result[i] = getArgumentType(m, i)

proc method_getDescription(m: Method): ptr objc_method_description {.cdecl, importc.}
proc getDescription*(m: Method): MethodDescription =
  var p = method_getDescription(m)
  result.name = p.name
  result.types = $p.types

proc method_setImplementation(m: Method, imp: IMP): IMP {.cdecl, importc.}
template setImplementation*(m: Method, imp: IMP): untyped =
  method_setImplementation(m, imp)

proc method_exchangeImplementations(m1: Method, m2: Method) {.cdecl, importc.}
template exchangeImplementations*(m1: Method, m2: Method) =
  method_exchangeImplementations(m1, m2)

proc objc_copyImageNames(outCount: var cuint): cstringArray {.cdecl, importc.}
proc imageNames*(): seq[string] =
  var
    count = 0.cuint
    images = objc_copyImageNames(count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[string](count.int)
  for i in 0 ..< result.len:
    result[i] = $images[i]

proc class_getImageName(cls: IDPtr): cstring {.cdecl, importc.}
template getImageName*(cls: ObjcClass): untyped =
  $class_getImageName(cls)

proc objc_copyClassNamesForImage(
  image: cstring, outCount: var cuint
): cstringArray {.cdecl, importc.}

proc classNamesForImage*(image: string): seq[string] =
  var
    count = 0.cuint
    classes = objc_copyClassNamesForImage(image.cstring, count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[string](count.int)
  for i in 0 ..< result.len:
    result[i] = $classes[i]

proc objc_getProtocol(name: cstring): Protocol {.cdecl, importc.}
proc getProtocolByName*(name: string): Protocol =
  result = objc_getProtocol(name.cstring)
  when KNutellaNsToNxRemapEnabled:
    if result.isNil:
      let mapped = nutellaNsToNxRuntimeName(name)
      if mapped != name:
        result = objc_getProtocol(mapped.cstring)

template getProtocol*(name: string): untyped =
  getProtocolByName(name)

template getProtocol*[T: ProtocolPrototype](t: typedesc[T]): untyped =
  block:
    const typeName = $T
    when typeName.endsWith("Prototype") and typeName.len > "Prototype".len:
      getProtocolByName(typeName[0 ..< typeName.len - "Prototype".len])
    else:
      getProtocolByName(typeName)

template getProtocol*[T: ObjcProtocolObject](t: typedesc[T]): untyped =
  getProtocolByName($T)

proc ofProto*[T: ObjcProtocolObject](o: ID): bool =
  if o.isNil:
    return false
  let proto = getProtocol(T)
  if proto.isNil:
    return false
  let cls = getClass(o.value)
  if cls.isNil:
    return false
  cls.conformsToProtocol(proto)

proc asProto*[T: ObjcProtocolObject](o: IDPtr): T =
  if o == nil:
    return T(value: nil)
  let proto = getProtocol(T)
  if proto.isNil:
    return T(value: nil)
  let cls = getClass(o)
  if cls.isNil or not cls.conformsToProtocol(proto):
    return T(value: nil)
  T(value: retainAux(o))

template asProto*[T: ObjcProtocolObject](o: ID): T =
  asProto[T](o.value)

proc objc_copyProtocolList(outCount: var cuint): ptr Protocol {.cdecl, importc.}
proc protocolList*(): seq[Protocol] =
  var
    count = 0.cuint
    prots = objc_copyProtocolList(count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[Protocol](count.int)
  copyMem(result[0].addr, prots, result.len * sizeof(Protocol))
  c_free(prots)

proc objc_allocateProtocol(name: cstring): Protocol {.cdecl, importc.}
template allocateProtocol*(name: string): untyped =
  objc_allocateProtocol(name.cstring)

proc objc_registerProtocol*(proto: Protocol) {.cdecl, importc.}
template registerProtocol*(proto: Protocol) =
  objc_registerProtocol(proto)

proc protocol_addMethodDescription(
  proto: Protocol, name: SEL, types: cstring, isRequiredMethod, isInstanceMethod: bool
) {.cdecl, importc.}

template addMethodDescription*(
    proto: Protocol, name: SEL, types: string, isRequiredMethod, isInstanceMethod: bool
) =
  protocol_addMethodDescription(
    proto, name, types.cstring, isRequiredMethod, isInstanceMethod
  )

proc protocol_addProtocol(proto, addition: Protocol) {.cdecl, importc.}
template addProtocol*(proto, addition: Protocol) =
  protocol_addProtocol(proto, addition)

proc protocol_addProperty(
  proto: Protocol,
  name: cstring,
  attributes: ptr objc_property_attribute_t,
  attributeCount: cuint,
  isRequiredProperty: bool,
  isInstanceProperty: bool,
) {.cdecl, importc.}

proc addProperty*(
    proto: Protocol,
    name: string,
    attributes: openArray[objc_property_attribute_t],
    isRequiredProperty, isInstanceProperty: bool,
) =
  protocol_addProperty(
    proto,
    name,
    attributes[0].unsafeAddr,
    attributes.len.cuint,
    isRequiredProperty,
    isInstanceProperty,
  )

proc protocol_getName(p: Protocol): cstring {.cdecl, importc.}
template getName*(p: Protocol): untyped =
  $protocol_getName(p)

proc `$`*(p: Protocol): string =
  getName(p)

proc protocol_isEqual(proto, other: Protocol): bool {.cdecl, importc.}
template isEqual*(proto, other: Protocol): untyped =
  protocol_isEqual(proto, other)

proc protocol_copyMethodDescriptionList(
  p: Protocol, isRequiredMethod, isInstanceMethod: bool, outCount: var cuint
): ptr objc_method_description {.cdecl, importc.}

proc methodDescriptionList*(
    p: Protocol, isRequiredMethod, isInstanceMethod: bool
): seq[MethodDescription] =
  type DescT = UncheckedArray[objc_method_description]
  var
    count = 0.cuint
    raw =
      protocol_copyMethodDescriptionList(p, isRequiredMethod, isInstanceMethod, count)
  if count == 0 or raw.isNil:
    result = @[]
    return result
  let descs = cast[ptr DescT](raw)
  result = newSeq[MethodDescription](count.int)
  for i in 0 ..< count.int:
    let types =
      if descs[i].types.isNil:
        ""
      else:
        $descs[i].types
    result[i] = MethodDescription(name: descs[i].name, types: types)
  c_free(raw)

proc protocol_getMethodDescription(
  p: Protocol, aSel: SEL, isRequiredMethod, isInstanceMethod: bool
): objc_method_description {.cdecl, importc.}

template getMethodDescription*(
    p: Protocol, aSel: SEL, isRequiredMethod, isInstanceMethod: bool
): untyped =
  protocol_getMethodDescription(p, aSel, isRequiredMethod, isInstanceMethod)

proc protocol_copyPropertyList(
  proto: Protocol, outCount: var cuint
): ptr Property {.cdecl, importc.}

proc propertyList*(proto: Protocol): seq[Property] =
  var
    count = 0.cuint
    props = protocol_copyPropertyList(proto, count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[Property](count.int)
  copyMem(result[0].addr, props, result.len * sizeof(Property))
  c_free(props)

proc protocol_getProperty(
  proto: Protocol, name: cstring, isRequiredProperty, isInstanceProperty: bool
): Property {.cdecl, importc.}

template getProperty*(
    proto: Protocol, name: string, isRequiredProperty, isInstanceProperty: bool
): untyped =
  protocol_getProperty(proto, name.cstring, isRequiredProperty, isInstanceProperty)

proc protocol_copyProtocolList*(
  proto: Protocol, outCount: var cuint
): ptr Protocol {.cdecl, importc.}

proc protocolList*(proto: Protocol): seq[Protocol] =
  var
    count = 0.cuint
    prots = protocol_copyProtocolList(proto, count)
  if count == 0:
    result = @[]
    return result
  result = newSeq[Protocol](count.int)
  copyMem(result[0].addr, prots, result.len * sizeof(Protocol))
  c_free(prots)

proc protocol_conformsToProtocol(proto, other: Protocol): bool {.cdecl, importc.}
template conformsToProtocol*(proto, other: Protocol): untyped =
  protocol_conformsToProtocol(proto, other)

proc property_getName(property: Property): cstring {.cdecl, importc.}
template getName*(property: Property): untyped =
  $property_getName(property)

proc `$`*(property: Property): string =
  getName(property)

proc property_getAttributes(property: Property): cstring {.cdecl, importc.}
template getAttributes*(property: Property): untyped =
  $property_getAttributes(property)

proc property_copyAttributeList(
  property: Property, outCount: var cuint
): ptr objc_property_attribute_t {.cdecl, importc.}

proc attributeList*(property: Property): seq[PropertyAttribute] =
  type AttrT = array[0 .. 0, objc_property_attribute_t]
  var
    count = 0.cuint
    raw = property_copyAttributeList(property, count)
    attrs = cast[AttrT](raw)
  if count == 0:
    result = @[]
    return result
  result = newSeq[PropertyAttribute](count.int)
  for i in 0 ..< count.int:
    result[i] = PropertyAttribute(name: $attrs[i].name, value: $attrs[i].value)
  c_free(raw)

proc property_copyAttributeValue(
  property: Property, attributeName: cstring
): cstring {.cdecl, importc.}

proc attributeValue*(property: Property, attributeName: string): string =
  var res = property_copyAttributeValue(property, attributeName.cstring)
  result = $res
  c_free(res)

proc objc_enumerationMutation(obj: IDPtr) {.cdecl, importc.}
template enumerationMutation*(obj: IDPtr) =
  objc_enumerationMutation(obj)

type EnumerationHandler = proc(a2: IDPtr) {.cdecl.}

proc objc_setEnumerationMutationHandler(handler: EnumerationHandler) {.cdecl, importc.}
template setEnumerationMutationHandler*(handler: EnumerationHandler) =
  objc_setEnumerationMutationHandler(handler)

proc imp_implementationWithBlock(blok: IDPtr): IMP {.cdecl, importc.}
template implementationWithBlock*(blok: IDPtr): untyped =
  imp_implementationWithBlock(blok)

proc imp_getBlock(anImp: IMP): IDPtr {.cdecl, importc.}
template getBlock*(anImp: IMP): untyped =
  imp_getBlock(anImp)

proc imp_removeBlock(anImp: IMP): bool {.cdecl, importc.}
template removeBlock*(anImp: IMP): untyped =
  imp_removeBlock(anImp)

proc objc_loadWeak(location: var IDPtr): IDPtr {.cdecl, importc.}
template loadWeak*(location: var IDPtr): untyped =
  objc_loadWeak(location)

proc objc_storeWeak(location: var IDPtr, obj: IDPtr): IDPtr {.cdecl, importc.}
template storeWeak*(location: var IDPtr, obj: IDPtr): untyped =
  objc_storeWeak(location, obj)

{.push stackTrace: off.}
# These procs should better be inlined, but there's a Nim bug #5945

proc objcClass*(name: static[string]): ObjcClass =
  getClassByName(name)

proc objcClass*[T](t: typedesc[T]): ObjcClass {.inline.} =
  objcClass($T)

proc getSelector*(name: static[string]): SEL =
  var s {.global.}: SEL
  if pointer(s).isNil:
    s = sel_registerName(name)
  return s

proc `@ selector`*(name: static[string]): SEL =
  getSelector(name)

proc respondsToSelector*(obj: NSObject, selector: static[string]): bool =
  class_respondsToSelector(object_getClass(obj), sel_registerName(selector))

{.pop.}

proc getArgsAndTypes(routine: NimNode): (NimNode, NimNode) =
  let args = newNimNode(nnkStmtList)
  let types = newNimNode(nnkStmtList)
  let params = routine.params
  for a in 1 ..< params.len:
    let p = params[a]
    for i in 0 .. p.len - 3:
      args.add(p[i])
      types.add(p[^2])
  result = (args, types)

proc unpackPragmaParams(p1, p2: NimNode): (string, NimNode) =
  if p2.kind == nnkNilLit:
    ("", p1)
  else:
    ($p1, p2)

proc guessSelectorNameFromProc(p: NimNode): string =
  var pName = p.name
  if pName.kind == nnkPostfix:
    pName = pName[^1]
  result = $pName

type ObjCMsgSendFlavor = enum
  normal
  fpret
  stret

template msgSendFlavorForRetType(retType: typedesc): ObjCMsgSendFlavor =
  when (retType is float | float32 | float64 | cfloat | cdouble) and hostCPU == "i386":
    ObjCMsgSendFlavor.fpret
  elif (retType is object | tuple) and sizeof(retType) > sizeof(pointer) * 2 and
      not defined(arm64): # TODO: sizeof check is a dangerous guess here! Please help.
    ObjCMsgSendFlavor.stret
  else:
    ObjCMsgSendFlavor.normal

proc buildCallSuper(
    retType, obj, op, args: NimNode, flavor: ObjCMsgSendFlavor
): NimNode =
  let superCall = genSym(nskVar, "superCall")
  let performSend = genSym(nskLet, "performSend")

  let senderParams = newNimNode(nnkFormalParams)
  if flavor == stret:
    senderParams.add(bindSym"void")
    senderParams.add(newIdentDefs(ident"retObj", newTree(nnkPtrTy, retType)))
  else:
    senderParams.add(retType)
  senderParams.add(newIdentDefs(ident"superObj", newTree(nnkVarTy, bindSym"ObjcSuper")))
  senderParams.add(newIdentDefs(ident"selector", bindSym"SEL"))
  for i, a in args:
    senderParams.add(newIdentDefs(ident("arg" & $i), a.getTypeInst))

  let procTy = newTree(nnkProcTy, senderParams)
  procTy.add(newTree(nnkPragma, ident"cdecl", ident"varargs", ident"gcsafe"))

  let sendProc = newTree(
    nnkCast,
    procTy,
    if flavor == stret:
      bindSym"objc_msgSendSuper_stret"
    else:
      bindSym"objc_msgSendSuper",
  )
  let castSendProc =
    newTree(nnkLetSection, newIdentDefs(performSend, newEmptyNode(), sendProc))

  let call =
    if flavor == stret:
      let ret = genSym(nskVar, "ret")
      var c = newCall(performSend, newCall(ident"addr", ret), superCall, op)
      for a in args:
        c.add(a)
      let setupSuper = quote:
        var `superCall` = ObjcSuper(
          receiver: `obj`, superClass: class_getSuperclass(object_getClass(`obj`))
        )
        var `ret`: `retType`
      return newStmtList(setupSuper, castSendProc, c, ret)
    else:
      newCall(performSend, superCall, op)

  for a in args:
    call.add(a)

  let setupSuper = quote:
    var `superCall` = ObjcSuper(
      receiver: `obj`, superClass: class_getSuperclass(object_getClass(`obj`))
    )

  result = newStmtList(setupSuper, castSendProc, call)

proc buildCallSuper(retType, obj, op, args: NimNode): NimNode =
  let normalCall = buildCallSuper(retType, obj, op, args, ObjCMsgSendFlavor.normal)
  let stretCall = buildCallSuper(retType, obj, op, args, ObjCMsgSendFlavor.stret)
  result = quote:
    when msgSendFlavorForRetType(`retType`) == ObjCMsgSendFlavor.stret:
      `stretCall`
    else:
      `normalCall`

proc identNameFromNode(n: NimNode): string =
  case n.kind
  of nnkIdent, nnkSym:
    $n
  of nnkPostfix:
    identNameFromNode(n[^1])
  of nnkAccQuoted:
    if n.len > 0:
      identNameFromNode(n[0])
    else:
      ""
  else:
    ""

proc parseSuperMessage(msg: NimNode, selectorName: var string, args: var seq[NimNode]) =
  case msg.kind
  of nnkPar:
    if msg.len == 1:
      parseSuperMessage(msg[0], selectorName, args)
    else:
      error("super(...) message must be a method name or method call", msg)
  of nnkIdent, nnkSym, nnkPostfix, nnkAccQuoted:
    selectorName = identNameFromNode(msg)
  of nnkCall, nnkCommand:
    selectorName = identNameFromNode(msg[0])
    if selectorName.len == 0:
      error("super(...) method call must start with a method name", msg)
    selectorName.add(":".repeat(msg.len - 1))
    for i in 1 ..< msg.len:
      args.add(copyNimTree(msg[i]))
  else:
    error("super(...) message must be a method name or method call", msg)

proc buildSuperMacroCall(obj, msg, retType: NimNode): NimNode =
  var selectorName = ""
  var args: seq[NimNode] = @[]
  parseSuperMessage(msg, selectorName, args)
  if selectorName.len == 0:
    error("super(...) could not resolve method name", msg)

  let selExpr = newCall(bindSym"getSelector", newLit(selectorName))
  if retType.kind == nnkEmpty:
    result = newCall(ident"callSuper", obj, selExpr)
  else:
    result = newCall(ident"callSuper", retType, obj, selExpr)
  for a in args:
    result.add(a)

macro callSuper*(obj: NSObject, op: SEL, args: varargs[typed]): untyped =
  result = buildCallSuper(bindSym"IDPtr", obj, op, args, ObjCMsgSendFlavor.normal)

macro callSuper*(
    retType: typedesc, obj: NSObject, op: SEL, args: varargs[typed]
): untyped =
  result = buildCallSuper(retType, obj, op, args)

macro super*(obj: NSObject, msg: untyped): untyped =
  result = buildSuperMacroCall(obj, msg, newEmptyNode())

macro super*(retType: typedesc, obj: NSObject, msg: untyped): untyped =
  result = buildSuperMacroCall(obj, msg, retType)

macro objcAux(
    flavor: static[ObjCMsgSendFlavor],
    firstArg: typed,
    name: static[string],
    body: untyped,
): untyped =
  var name = name

  let performSend = ident"performSend"

  let senderParams = newNimNode(nnkFormalParams)
  if flavor == stret:
    senderParams.add(ident"void")
    senderParams.add(newIdentDefs(ident"_", ident"pointer"))
  else:
    senderParams.add(copyNimTree(body.params[0]))
  senderParams.add(newIdentDefs(ident"self", bindSym"IDPtr"))
  senderParams.add(newIdentDefs(ident"selector", bindSym"SEL"))

  let procTy = newTree(nnkProcTy, senderParams)
  procTy.add(newTree(nnkPragma, ident"cdecl", ident"gcsafe"))

  let objcSendProc =
    case flavor
    of fpret:
      bindSym"objc_msgSend_fpret"
    of stret:
      bindSym"objc_msgSend_stret"
    else:
      bindSym"objc_msgSend"

  let sendProc = newTree(nnkCast, procTy, objcSendProc)

  let castSendProc =
    newTree(nnkLetSection, newIdentDefs(performSend, newEmptyNode(), sendProc))

  let call = newCall(performSend)

  let (args, argTypes) = body.getArgsAndTypes()

  if flavor == stret:
    call.add(newCall("addr", ident"result"))

  call.add(firstArg)

  if name.len == 0:
    name = guessSelectorNameFromProc(body)

  call.add(newCall(bindSym"getSelector", newLit(name))) # selector

  for i in 1 ..< args.len:
    senderParams.add(newIdentDefs(args[i], argTypes[i], newEmptyNode()))
    call.add(args[i])

  result = newStmtList(castSendProc, call)

macro objc*(name: untyped, body: untyped = nil): untyped =
  var (name, body) = unpackPragmaParams(name, body)
  var retType = body.params[0]
  if retType.kind == nnkEmpty:
    retType = ident"void"

  let (args, argTypes) = body.getArgsAndTypes()

  let firstArgTyp = argTypes[0]
  let isStatic =
    firstArgTyp.kind == nnkBracketExpr and firstArgTyp[0].kind == nnkIdent and
    $(firstArgTyp[0]) == "typedesc"
  let firstArg =
    if isStatic:
      newCall(ident"objcClass", args[0])
    else:
      args[0]

  result = copyNimTree(body)
  result.body = newCall(
    bindSym"objcAux",
    newCall(bindSym"msgSendFlavorForRetType", retType),
    firstArg,
    newLit(name),
    body,
  )
  result.addPragma(ident"inline")

#proc NSLog*(str: NSString) {.importc, varargs.}

proc retainAux(o: IDPtr): IDPtr {.raises: [].} =
  if o == nil:
    return nil
  objc_msgSend(o, sel_registerName("retain"))

proc retainRaw(o: IDPtr) {.raises: [].} =
  if o == nil:
    return
  discard objc_msgSend(o, sel_registerName("retain"))

proc releaseAux(o: IDPtr) {.raises: [].} =
  if o == nil:
    return
  discard objc_msgSend(o, sel_registerName("release"))

proc retainCountAux(o: IDPtr): NSUInteger {.raises: [].} =
  if o == nil:
    return 0
  cast[NSUInteger](objc_msgSend(o, sel_registerName("retainCount")))

proc superclass*(o: NSObject): ObjcClass {.objc.}
proc alloc*[T: NSObject](n: typedesc[T]): T {.objc: "alloc".}
proc alloc*(cls: ObjcClass): IDPtr {.inline.} =
  objc_msgSend(cls, sel_registerName("alloc"))

proc new*[T: NSObject](n: typedesc[T]): T {.objc: "new".}
proc new*(cls: ObjcClass): IDPtr {.inline.} =
  objc_msgSend(cls, sel_registerName("new"))

proc autorelease*[T: NSObject](n: T): T {.objc: "autorelease", discardable.}
proc initRaw(v: IDPtr): IDPtr {.inline.} =
  objc_msgSend(v, sel_registerName("init"))

proc init*[T: NSObject](v: var T): T {.inline.} =
  result = asTypeRaw[T](initRaw(move(v.value)))

proc init*[T: NSObject](n: typedesc[T]): T {.inline.} =
  var allocated = n.alloc()
  allocated.init()

proc superObject*(obj: NSObject): ObjcSuper {.inline.} =
  ObjcSuper(
    receiver: obj.value, superClass: class_getSuperclass(object_getClass(obj.value))
  )

proc callSuperAs*[T](obj: NSObject, op: SEL): T {.inline.} =
  var superObj = superObject(obj)
  cast[proc(superObj: var ObjcSuper, selParam: SEL): T {.cdecl, varargs.}](objc_msgSendSuper)(
    superObj, op
  )

proc callSuperAs*[T, A0](obj: NSObject, op: SEL, arg0: A0): T {.inline.} =
  var superObj = superObject(obj)
  cast[proc(superObj: var ObjcSuper, selParam: SEL, arg0: A0): T {.cdecl, varargs.}](objc_msgSendSuper)(
    superObj, op, arg0
  )

proc callSuperId*(obj: NSObject, op: SEL): IDPtr {.inline.} =
  callSuperAs[IDPtr](obj, op)

proc callSuperId*[A0](obj: NSObject, op: SEL, arg0: A0): IDPtr {.inline.} =
  callSuperAs[IDPtr, A0](obj, op, arg0)

template callSuperVoid*(obj: NSObject, op: SEL): untyped =
  discard callSuperAs[IDPtr](obj, op)

template callSuperVoid*[A0](obj: NSObject, op: SEL, arg0: A0): untyped =
  discard callSuperAs[IDPtr, A0](obj, op, arg0)

proc superDealloc*(obj: NSObject) {.inline.} =
  let deallocSel = sel_registerName("dealloc")
  callSuperVoid(obj, deallocSel)

proc alloc*[T](o: typedesc[T]): T {.objc: "alloc".}

proc isKindOfClassAux(o: NSObject, c: IDPtr): bool {.objc: "isKindOfClass:".}
proc isKindOfClass*(o: NSObject, c: ObjcClass): bool {.inline.} =
  if c.isNil:
    return false
  isKindOfClassAux(o, c.value)

proc isKindOfClass*(o: NSObject, c: typedesc): bool =
  o.isKindOfClass(c.objcClass())

template selector*(s: string): SEL =
  sel_registerName(s.cstring)

template addClass*(className, superName: string, cls: ObjcClass, body: untyped) =
  block:
    cls = allocateClassPair(getClass(superName), className, 0)

    template addProtocol(protocolName: string) {.used.} =
      discard addProtocol(cls, getProtocol(protocolName))

    template addMethod(methodName: string, fn: untyped) {.used.} =
      {.cast(raises: []).}:
        discard addMethod(cls, selector(methodName), cast[IMP](fn), "")

    body
    registerClassPair(cls)

proc encodeType*[T](t: typedesc[T]): string =
  # https://nshipster.com/type-encodings/
  when t is char:
    return "c"
  elif t is uint8:
    return "C"
  elif t is int:
    return "i"
  elif t is uint:
    return "I"
  elif t is cshort:
    return "s"
  elif t is cushort:
    return "S"
  elif t is int32:
    return "l"
  elif t is uint32:
    return "L"
  elif t is int64:
    return "q"
  elif t is uint64:
    return "Q"
  elif t is cfloat:
    return "f"
  elif t is cdouble:
    return "d"
  elif t is bool:
    return "B"
  elif t is cstring:
    return "*"
  elif t is typedesc:
    return "#"
  elif t is ObjcClass:
    return "#"
  elif t is typedesc[NSObject]:
    return "#"
  elif t is NSObject:
    return "@"
  elif t is IDPtr:
    return "@"
  elif t is SEL:
    return ":"
  elif t is void:
    return "v"
  elif t is object | tuple:
    return "{?=}"
  else:
    return "@"

macro getProcEncode*(y: typed): untyped =
  y.expectKind {nnkSym, nnkCast}
  var x =
    if y.kind == nnkSym:
      y.getImpl()
    else:
      y[1].getImpl()
  var j = newCall(bindSym"join")
  let encode = bindSym"encodeType"
  var ab = nnkBracket.newTree()
  x.expectKind nnkProcDef
  for p in x.params:
    if p.kind == nnkIdentDefs:
      ab.add newCall(encode, newCall(ident"type", p[1]))
    elif p.kind == nnkEmpty:
      ab.add newCall(encode, ident"void")
    elif p.kind == nnkSym:
      ab.add newCall(encode, newCall(ident"type", p))
  j.add ab
  result = nnkStaticExpr.newTree(j)

template addMethod*[T](cls: ObjcClass, name: SEL, imp: T): bool =
  class_addMethod(cls, name, cast[IMP](imp), getProcEncode(imp))

template replaceMethod*[T](cls: ObjcClass, name: SEL, imp: T): IMP =
  class_replaceMethod(cls, name, cast[IMP](imp), getProcEncode(imp))
