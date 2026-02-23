import std/unittest
import nutella/objc

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
