import std/unittest
import nutella/objc

objcImpl:
  type NXRaiseInObjcMethodProtocol =
    concept self
        method boom(self: NXRaiseInObjcMethodProtocol)

  type NXRaiseInObjcMethodClass {.impl: NXRaiseInObjcMethodProtocol.} = object of NSObject

  method boom(self: NXRaiseInObjcMethodClass) =
    discard self
    raise newException(ValueError, "raised from objc method")

suite "Objective-C and Nim exception bridge":
  test "objcExceptionFromParts builds an Obj-C exception object with readable fields":
    let objcException = objcExceptionFromParts("ManualObjcName", "manual objc reason")
    let nimException = nimExceptionFromObjcRetained(objcException)

    check(nimException != nil)
    check(nimException.objcName == "ManualObjcName")
    check(nimException.objcReason == "manual objc reason")

  test "objcExceptionFromNim preserves Nim exception name and message":
    var sourceException: ref Exception
    try:
      raise newException(ValueError, "nim bridge reason")
    except CatchableError as nimException:
      sourceException = nimException

    let objcException = objcExceptionFromNim(sourceException)
    let converted = nimExceptionFromObjcRetained(objcException)

    check(converted != nil)
    check(converted.objcName == "ValueError")
    check(converted.objcReason == "nim bridge reason")

  test "nimExceptionFromObjc parses marker payloads from plain string objects":
    let markerPayload = nsString("nim.exc:MarkerName\nMarkerReason")
    let converted = nimExceptionFromObjc(markerPayload.value)

    check(converted != nil)
    check(converted.objcName == "MarkerName")
    check(converted.objcReason == "MarkerReason")

  test "Nim caller can catch Nim exception raised from objcImpl method":
    var o = NXRaiseInObjcMethodClass.new()
    var caught: ref ValueError

    try:
      o.boom()
    except ValueError as e:
      caught = e

    check(caught != nil)
    check(caught.msg == "raised from objc method")
