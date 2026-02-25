import std/strutils
import ./objcImpl

{.compile: "private/objc_exceptions_bridge.m".}

type ObjcExceptionError* = object of CatchableError
  objcClassName*: string
  objcName*: string
  objcReason*: string

const NimExceptionMarker = "nim.exc:"

proc nutella_objc_build_exception(
  name, reason, fallbackPayload: cstring
): IDPtr {.cdecl, importc.}

proc objcRetainRaw(id: IDPtr): IDPtr {.inline, raises: [].} =
  if id == nil:
    return nil
  let retainSend =
    cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs, raises: [].}](objc_msgSend)
  retainSend(id, sel_registerName("retain"))

proc objcReleaseRaw(id: IDPtr) {.inline, raises: [].} =
  if id == nil:
    return
  let releaseSend =
    cast[proc(self: IDPtr, op: SEL): void {.cdecl, varargs, raises: [].}](objc_msgSend)
  releaseSend(id, sel_registerName("release"))

proc objcRespondsToSelectorRaw(
    id: IDPtr, selectorName: string
): bool {.inline, raises: [].} =
  if id == nil:
    return false
  let respondsSend = cast[proc(self: IDPtr, op: SEL, selector: SEL): bool {.
    cdecl, varargs, raises: []
  .}](objc_msgSend)
  respondsSend(
    id, sel_registerName("respondsToSelector:"), sel_registerName(selectorName)
  )

proc objcSendIdRaw(id: IDPtr, selectorName: string): IDPtr {.inline, raises: [].} =
  if id == nil:
    return nil
  let sendId =
    cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs, raises: [].}](objc_msgSend)
  sendId(id, sel_registerName(selectorName))

proc objcUtf8StringRaw(id: IDPtr): string {.inline, raises: [].} =
  if id == nil:
    return ""
  if not objcRespondsToSelectorRaw(id, "UTF8String"):
    return ""
  let utf8Send =
    cast[proc(self: IDPtr, op: SEL): cstring {.cdecl, varargs, raises: [].}](objc_msgSend)
  let utf8 = utf8Send(id, sel_registerName("UTF8String"))
  if utf8.isNil:
    return ""
  $utf8

proc parseNimExceptionMarker(
    payload: string, name: var string, reason: var string
): bool =
  if not payload.startsWith(NimExceptionMarker):
    return false
  let rest = payload[NimExceptionMarker.len .. ^1]
  let splitAt = rest.find('\n')
  if splitAt < 0:
    name = rest
    reason = ""
    return true
  name = rest[0 ..< splitAt]
  if splitAt + 1 >= rest.len:
    reason = ""
  else:
    reason = rest[splitAt + 1 .. ^1]
  true

proc encodeNimExceptionMarker(name, reason: string): string {.inline, raises: [].} =
  NimExceptionMarker & name & "\n" & reason

proc objcExceptionText(exception: IDPtr): string {.raises: [].} =
  if exception == nil:
    return ""
  result = objcUtf8StringRaw(exception)
  if result.len > 0:
    return
  if objcRespondsToSelectorRaw(exception, "description"):
    let desc = objcSendIdRaw(exception, "description")
    result = objcUtf8StringRaw(desc)
  if result.len == 0:
    result = getRawClassName(exception)

proc objcExceptionName*(exception: IDPtr): string {.raises: [].} =
  if exception == nil:
    return ""
  if objcRespondsToSelectorRaw(exception, "name"):
    result = objcUtf8StringRaw(objcSendIdRaw(exception, "name"))
    if result.len > 0:
      return
  let payload = objcExceptionText(exception)
  var markerName = ""
  var markerReason = ""
  if parseNimExceptionMarker(payload, markerName, markerReason) and markerName.len > 0:
    return markerName
  result = getRawClassName(exception)

proc objcExceptionReason*(exception: IDPtr): string {.raises: [].} =
  if exception == nil:
    return ""
  if objcRespondsToSelectorRaw(exception, "reason"):
    result = objcUtf8StringRaw(objcSendIdRaw(exception, "reason"))
    if result.len > 0:
      return
  let payload = objcExceptionText(exception)
  var markerName = ""
  var markerReason = ""
  if parseNimExceptionMarker(payload, markerName, markerReason):
    return markerReason
  result = payload

proc newObjcExceptionError(exception: IDPtr): ref ObjcExceptionError {.raises: [].} =
  let className =
    if exception == nil:
      "<nil>"
    else:
      getRawClassName(exception)
  let name =
    if exception == nil:
      ""
    else:
      objcExceptionName(exception)
  let reason =
    if exception == nil:
      ""
    else:
      objcExceptionReason(exception)
  var msg = "Objective-C exception"
  if name.len > 0:
    msg.add(" [" & name & "]")
  if reason.len > 0:
    msg.add(": " & reason)
  result = newException(ObjcExceptionError, msg)
  result.objcClassName = className
  result.objcName = name
  result.objcReason = reason
  objcReleaseRaw(exception)

proc objcExceptionFromParts*(name, reason: string): IDPtr {.raises: [].} =
  let fallbackPayload = encodeNimExceptionMarker(name, reason)
  result =
    nutella_objc_build_exception(name.cstring, reason.cstring, fallbackPayload.cstring)

proc objcExceptionFromNim*(nimException: ref Exception): IDPtr {.raises: [].} =
  let name =
    if nimException.isNil or nimException.name.len == 0:
      "NimException"
    else:
      $nimException.name
  let reason = if nimException.isNil: "" else: nimException.msg
  objcExceptionFromParts(name, reason)

proc nimExceptionFromObjcRetained*(
    exception: IDPtr
): ref ObjcExceptionError {.raises: [].} =
  newObjcExceptionError(exception)

proc nimExceptionFromObjc*(exception: IDPtr): ref ObjcExceptionError {.raises: [].} =
  if exception == nil:
    return newObjcExceptionError(nil)
  nimExceptionFromObjcRetained(objcRetainRaw(exception))
