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

const
  YES* = true
  NO* = false

type
  ID* = pointer

  NSObject* {.pure, inheritable.} = object
    value*: ID

  ObjcClass* {.pure.} = object of NSObject

  NSString* = object of NSObject
  NSDictionary*[K, V] = object of NSObject

  ProtocolPrototype* {.pure, inheritable.} = object

  Method* = distinct pointer
  Ivar* = distinct pointer
  Category* = distinct pointer
  IMP* = proc(id: ID, selector: SEL): ID {.cdecl, varargs.}
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
    receiver*: ID
    superClass*: ObjcClass

  objc_property_attribute_t* = object
    name*: cstring
    value*: cstring

  PropertyAttribute* = object
    name*: string
    value*: string

  objc_exception_functions_t* = object
    version: cint
    throw_exc: proc(id: ID) {.cdecl.}
    try_enter: proc(p: pointer) {.cdecl.}
    try_exit: proc(p: pointer) {.cdecl.}
    extract: proc(p: pointer): ID {.cdecl.}
    match: proc(class: ObjcClass, id: ID): cint {.cdecl.}

  objc_AssociationPolicy* {.size: sizeof(cuint).} = enum
    OBJC_ASSOCIATION_ASSIGN = 0
    OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    OBJC_ASSOCIATION_RETAIN = 01401
    OBJC_ASSOCIATION_COPY = 01403

proc retainAux(o: ID): ID {.raises: [].}
proc retainRaw(o: ID) {.raises: [].}
proc releaseAux(o: ID) {.raises: [].}
proc retainCountAux(o: ID): NSUInteger {.raises: [].}

template retain*[T: NSObject](o: T): T =
  cast[T](retainAux(o.value))

proc `=destroy`(o: var NSObject) =
  if o.value != nil:
    releaseAux(o.value)
    o.value = nil

proc `=copy`(dest: var NSObject, src: NSObject) =
  if dest.value == src.value:
    return
  `=destroy`(dest)
  dest.value = src.value
  if dest.value != nil:
    retainRaw(dest.value)

proc `=sink`(dest: var NSObject, src: NSObject) =
  if dest.value == src.value:
    return
  `=destroy`(dest)
  dest.value = src.value

proc `=destroy`(o: var ObjcClass) =
  o.value = nil

proc `=copy`(dest: var ObjcClass, src: ObjcClass) =
  dest.value = src.value

proc `=sink`(dest: var ObjcClass, src: ObjcClass) =
  dest.value = src.value

proc release*(o: var NSObject) {.inline.} =
  `=destroy`(o)

proc release*(o: NSObject) {.inline.} =
  if o.value != nil:
    releaseAux(o.value)

template retainCount*(o: NSObject): NSUInteger =
  retainCountAux(o.value)

proc isNil*(a: NSObject): bool =
  result = a.value == nil

proc isNil*(a: ObjcClass): bool =
  result = a.value == nil

proc isNil*(a: Protocol): bool =
  cast[pointer](a) == nil

converter toID*(o: NSObject): ID {.inline.} =
  o.value

converter toNSObject*(id: ID): NSObject {.inline.} =
  NSObject(value: id)

converter toObjcClass*(id: ID): ObjcClass {.inline.} =
  ObjcClass(value: id)

template asType*[T: NSObject](o: ID): T =
  T(value: o)

template asType*[T: NSObject](o: NSObject): T =
  T(value: o.value)

proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}
proc sel_registerName*(str: cstring): SEL {.cdecl, importc.}
proc objc_msgSend*(self: ID, op: SEL): ID {.cdecl, importc, discardable, varargs.}

proc objc_msgSend_fpret*(self: ID, op: SEL): cdouble {.cdecl, importc, varargs.}
proc objc_msgSend_stret*(self: ID, op: SEL) {.cdecl, importc, varargs.}
proc objc_msgSendSuper*(super: var ObjcSuper, op: SEL): ID {.cdecl, importc, varargs.}
proc objc_msgSendSuper_stret*(super: var ObjcSuper, op: SEL) {.cdecl, importc, varargs.}

proc class_getName(cls: ID): cstring {.cdecl, importc.}
proc getName*(cls: ObjcClass): string =
  result = $class_getName(cls)

proc `$`*(cls: ObjcClass): string =
  getName(cls)

proc class_getSuperclass(cls: ID): ObjcClass {.cdecl, importc.}
template getSuperclass*(cls: ObjcClass): untyped =
  class_getSuperClass(cls)

proc class_isMetaClass(cls: ID): bool {.cdecl, importc.}
template isMetaClass*(cls: ObjcClass): untyped =
  class_isMetaClass(cls)

proc class_getInstanceSize(cls: ID): csize_t {.cdecl, importc.}
proc getInstanceSize*(cls: ObjcClass): int =
  class_getInstanceSize(cls).int

proc class_getInstanceVariable(cls: ID, name: cstring): Ivar {.cdecl, importc.}
template getIvar*(cls: ObjcClass, name: string): untyped =
  class_getInstanceVariable(cls, name.cstring)

proc class_getClassVariable(cls: ID, name: cstring): Ivar {.cdecl, importc.}
template getClassVariable*(cls: ObjcClass, name: string): untyped =
  class_getClassVariable(cls, name.cstring)

proc class_addIvar(
  cls: ID, name: cstring, size: csize_t, alignment: uint8, types: cstring
): bool {.cdecl, importc.}

proc addIvar*(
    cls: ObjcClass, name: string, size: int, alignment: int, types: string
): bool =
  class_addIvar(cls, name.cstring, size.csize_t, alignment.uint8, types.cstring) == YES

proc class_copyIvarList(cls: ID, outCount: var cuint): ptr Ivar {.cdecl, importc.}

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

proc class_getIvarLayout*(cls: ID): ptr uint8 {.cdecl, importc.}
proc class_getWeakIvarLayout*(cls: ID): ptr uint8 {.cdecl, importc.}
proc class_setIvarLayout*(cls: ID, layout: ptr uint8) {.cdecl, importc.}
proc class_setWeakIvarLayout*(cls: ID, layout: ptr uint8) {.cdecl, importc.}

proc class_getProperty(cls: ID, name: cstring): Property {.cdecl, importc.}
template getProperty*(cls: ObjcClass, name: string): untyped =
  class_getProperty(cls, name.cstring)

proc class_copyPropertyList*(
  cls: ID, outCount: var cuint
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
  cls: ID, name: SEL, imp: IMP, types: cstring
): bool {.cdecl, importc.}

template addMethod*(cls: ObjcClass, name: SEL, imp: IMP, types: string): bool =
  class_addMethod(cls, name, imp, types.cstring)

proc class_getInstanceMethod(cls: ID, name: SEL): Method {.cdecl, importc.}
template getInstanceMethod*(cls: ObjcClass, name: SEL): Method =
  class_getInstanceMethod(cls, name)

proc class_getClassMethod(cls: ID, name: SEL): Method {.cdecl, importc.}
template getClassMethod*(cls: ObjcClass, name: SEL): Method =
  class_getClassMethod(cls, name)

proc class_copyMethodList(cls: ID, outCount: var cuint): ptr Method {.cdecl, importc.}

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
  cls: ID, name: SEL, imp: IMP, types: cstring
): IMP {.cdecl, importc.}

template replaceMethod*(cls: ObjcClass, name: SEL, imp: IMP, types: string): untyped =
  class_replaceMethod(cls, name, imp, types.cstring)

proc class_getMethodImplementation(cls: ID, name: SEL): IMP {.cdecl, importc.}
template getMethodImplementation*(cls: ObjcClass, name: SEL): untyped =
  class_getMethodImplementation(cls, name)

proc class_getMethodImplementation_stret*(cls: ID, name: SEL): IMP {.cdecl, importc.}

proc class_respondsToSelector(cls: ID, sel: SEL): bool {.cdecl, importc.}
template respondsToSelector*(cls: ObjcClass, sel: SEL): untyped =
  class_respondsToSelector(cls, sel)

proc class_addProtocol(cls: ID, protocol: Protocol): bool {.cdecl, importc.}
template addProtocol*(cls: ObjcClass, protocol: Protocol): untyped =
  class_addProtocol(cls, protocol)

proc class_addProperty(
  cls: ID,
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
  cls: ID,
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

proc class_conformsToProtocol(cls: ID, protocol: Protocol): bool {.cdecl, importc.}

template conformsToProtocol*(cls: ObjcClass, protocol: Protocol): bool =
  class_conformsToProtocol(cls, protocol) == YES

proc class_copyProtocolList(
  cls: ID, outCount: var cuint
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

proc class_getVersion(cls: ID): cint {.cdecl, importc.}
template getVersion*(cls: ObjcClass): untyped =
  class_getVersion(cls).int

proc class_setVersion(cls: ID, version: cint) {.cdecl, importc.}
template setVersion*(cls: ObjcClass, version: int) =
  class_setVersion(cls, version.cint)

proc objc_getFutureClass(name: cstring): ObjcClass {.cdecl, importc.}
template getFutureClass*(name: string): untyped =
  objc_getFutureClass(name.cstring)

proc objc_allocateClassPair(
  superclass: ID, name: cstring, extraBytes: csize_t
): ID {.cdecl, importc.}

template allocateClassPair*(
    superclass: ObjcClass, name: string, extraBytes: int
): untyped =
  toObjcClass(objc_allocateClassPair(superclass, name.cstring, extrabytes.csize_t))

proc objc_disposeClassPair(cls: ID) {.cdecl, importc.}
template disposeClassPair*(cls: ObjcClass) =
  objc_disposeClassPair(cls)

proc objc_registerClassPair(cls: ID) {.cdecl, importc.}
template registerClassPair*(cls: ObjcClass) =
  objc_registerClassPair(cls)

proc objc_duplicateClass(
  original: ObjcClass, name: cstring, extraBytes: csize_t
): ObjcClass {.cdecl, importc.}

template duplicateClass*(original: ObjcClass, name: string, extraBytes: int): untyped =
  objc_duplicateClass(original, name.cstring, extraBytes.csize_t)

proc class_createInstance(cls: ID, extraBytes: csize_t): ID {.cdecl, importc.}
template createInstance*(cls: ObjcClass, extraBytes: csize_t): untyped =
  class_createInstance(cls, extraBytes.csize_t)

proc objc_constructInstance(cls: ID, bytes: pointer): ID {.cdecl, importc.}
template constructInstance*(cls: ObjcClass, bytes: pointer): untyped =
  objc_constructInstance(cls, bytes)

proc objc_destructInstance(obj: ID): pointer {.cdecl, importc.}
template destructInstance*(obj: ID): untyped =
  objc_destructInstance(obj)

proc object_copy(obj: ID, size: csize_t): ID {.cdecl, importc.}
template copy*(obj: ID, size: csize_t): untyped =
  object_copy(obj, size.csize_t)

proc object_dispose(obj: ID): ID {.cdecl, importc.}
template dispose*(obj: ID): untyped =
  object_dispose(obj)

proc object_setInstanceVariable(
  obj: ID, name: cstring, value: pointer
): Ivar {.cdecl, importc.}

template setInstanceVariable*(obj: ID, name: string, value: pointer): untyped =
  object_setInstanceVariable(obj, name.cstring, value)

proc object_getInstanceVariable(
  obj: ID, name: cstring, outValue: var pointer
): Ivar {.cdecl, importc.}

template getInstanceVariable*(obj: ID, name: string, outValue: var pointer): untyped =
  object_getInstanceVariable(obj, name.cstring, outValue)

proc object_getIndexedIvars(obj: ID): pointer {.cdecl, importc.}
template getIndexedIvars*(obj: ID): untyped =
  object_getIndexedIvars(obj)

proc object_getIvar(obj: ID, ivar: Ivar): ID {.cdecl, importc.}
template getIvar*(obj: ID, ivar: Ivar): untyped =
  object_getIvar(obj, ivar)

proc object_setIvar(obj: ID, ivar: Ivar, value: ID) {.cdecl, importc.}
template setIvar*(obj: ID, ivar: Ivar, value: ID) =
  object_setIvar(obj, ivar, value)

proc object_getClassName(obj: ID): cstring {.cdecl, importc.}
proc getRawClassName*(obj: ID): string =
  $object_getClassName(obj)

template getClassName*[T: NSObject](obj: T): string =
  $object_getClassName(obj.value)

proc objc_getClass(name: cstring): ObjcClass {.cdecl, importc.}
template getClass*(name: string): untyped =
  objc_getClass(name.cstring)

template getClass*[T: NSObject](t: typedesc[T]): untyped =
  objc_getClass(($T).cstring)

proc object_setClass(obj: ID, cls: ID): ObjcClass {.cdecl, importc.}
template setClass*(obj: ID, cls: ObjcClass): untyped =
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

proc object_getClass(obj: ID): ObjcClass {.cdecl, importc.}
template getClass*(obj: ID): untyped =
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

proc ivar_getOffset(v: Ivar): ptrdiff_t {.cdecl, importc.}
template getOffset*(v: Ivar): untyped =
  ivar_getOffset(v)

proc objc_setAssociatedObject(
  obj: ID, key: pointer, value: ID, policy: objc_AssociationPolicy
) {.cdecl, importc.}

template setAssociatedObject*(
    obj: ID, key: pointer, value: ID, policy: objc_AssociationPolicy
) =
  objc_setAssociatedObject(obj, key, value, policy)

proc objc_getAssociatedObject(obj: ID, key: pointer): ID {.cdecl, importc.}
template getAssociatedObject*(obj: ID, key: pointer): untyped =
  objc_getAssociatedObject(obj, key)

proc objc_removeAssociatedObjects(obj: ID) {.cdecl, importc.}
template removeAssociatedObjects*(obj: ID) =
  objc_removeAssociatedObjects(obj)

proc method_invoke*(receiver: ID, m: Method): ID {.cdecl, importc, varargs.}
proc method_invoke_stret*(receiver: ID, m: Method) {.cdecl, importc, varargs.}

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

proc class_getImageName(cls: ID): cstring {.cdecl, importc.}
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
template getProtocol*(name: string): untyped =
  objc_getProtocol(name.cstring)

template getProtocol*[T: ProtocolPrototype](t: typedesc[T]): untyped =
  objc_getProtocol(($T).cstring)

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

proc objc_enumerationMutation(obj: ID) {.cdecl, importc.}
template enumerationMutation*(obj: ID) =
  objc_enumerationMutation(obj)

type EnumerationHandler = proc(a2: ID) {.cdecl.}

proc objc_setEnumerationMutationHandler(handler: EnumerationHandler) {.cdecl, importc.}
template setEnumerationMutationHandler*(handler: EnumerationHandler) =
  objc_setEnumerationMutationHandler(handler)

proc imp_implementationWithBlock(blok: ID): IMP {.cdecl, importc.}
template implementationWithBlock*(blok: ID): untyped =
  imp_implementationWithBlock(blok)

proc imp_getBlock(anImp: IMP): ID {.cdecl, importc.}
template getBlock*(anImp: IMP): untyped =
  imp_getBlock(anImp)

proc imp_removeBlock(anImp: IMP): bool {.cdecl, importc.}
template removeBlock*(anImp: IMP): untyped =
  imp_removeBlock(anImp)

proc objc_loadWeak(location: var ID): ID {.cdecl, importc.}
template loadWeak*(location: var ID): untyped =
  objc_loadWeak(location)

proc objc_storeWeak(location: var ID, obj: ID): ID {.cdecl, importc.}
template storeWeak*(location: var ID, obj: ID): untyped =
  objc_storeWeak(location, obj)

{.push stackTrace: off.}
# These procs should better be inlined, but there's a Nim bug #5945

proc objcClass*(name: static[string]): ObjcClass =
  objc_getClass(name)

proc objcClass*[T](t: typedesc[T]): ObjcClass {.inline.} =
  objcClass($T)

proc getSelector*(name: static[string]): SEL =
  var s {.global.}: SEL
  if pointer(s).isNil:
    s = sel_registerName(name)
  return s

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
  result = buildCallSuper(bindSym"ID", obj, op, args, ObjCMsgSendFlavor.normal)

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
  senderParams.add(newIdentDefs(ident"self", bindSym"ID"))
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

proc retainAux(o: ID): ID {.raises: [].} =
  objc_msgSend(o, sel_registerName("retain"))

proc retainRaw(o: ID) {.raises: [].} =
  discard objc_msgSend(o, sel_registerName("retain"))

proc releaseAux(o: ID) {.raises: [].} =
  discard objc_msgSend(o, sel_registerName("release"))

proc retainCountAux(o: ID): NSUInteger {.raises: [].} =
  cast[NSUInteger](objc_msgSend(o, sel_registerName("retainCount")))

proc superclass*(o: NSObject): ObjcClass {.objc.}
proc alloc*[T: NSObject](n: typedesc[T]): T {.objc: "alloc".}
proc alloc*(cls: ObjcClass): ID {.inline.} =
  objc_msgSend(cls, sel_registerName("alloc"))

proc new*[T: NSObject](n: typedesc[T]): T {.objc: "new".}
proc new*(cls: ObjcClass): ID {.inline.} =
  objc_msgSend(cls, sel_registerName("new"))

proc autorelease*[T: NSObject](n: T): T {.objc: "autorelease", discardable.}
proc initRaw(v: ID): ID {.inline.} =
  objc_msgSend(v, sel_registerName("init"))

proc init*[T: NSObject](v: var T): T {.inline.} =
  result = asType[T](initRaw(v.value))
  v.value = nil

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

proc callSuperId*(obj: NSObject, op: SEL): ID {.inline.} =
  callSuperAs[ID](obj, op)

proc callSuperId*[A0](obj: NSObject, op: SEL, arg0: A0): ID {.inline.} =
  callSuperAs[ID, A0](obj, op, arg0)

template callSuperVoid*(obj: NSObject, op: SEL): untyped =
  discard callSuperAs[ID](obj, op)

template callSuperVoid*[A0](obj: NSObject, op: SEL, arg0: A0): untyped =
  discard callSuperAs[ID, A0](obj, op, arg0)

proc superDealloc*(obj: NSObject) {.inline.} =
  let deallocSel = sel_registerName("dealloc")
  callSuperVoid(obj, deallocSel)

proc alloc*[T](o: typedesc[T]): T {.objc: "alloc".}

proc isKindOfClassAux(o: NSObject, c: ID): bool {.objc: "isKindOfClass:".}
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
  elif t is ObjcClass:
    return "#"
  elif t is typedesc[NSObject]:
    return "#"
  elif t is NSObject:
    return "@"
  elif t is ID:
    return "@"
  elif t is SEL:
    return ":"
  elif t is void:
    return "v"

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
