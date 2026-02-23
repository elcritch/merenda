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

  test "two objc methods keep Nim ref alive and un-marshaled through middle call during exception":
    type ChainPayloadObj = object
      label: string
      hops: int

    type ChainPayloadRef = ref ChainPayloadObj

    var chainPayloadDestroyedCount = 0
    var chainOuterPtr: pointer = nil
    var chainMiddlePtr: pointer = nil
    var chainInnerPtr: pointer = nil
    var chainMiddleAliveInFinally = false
    var chainMiddleLabelInFinally = ""

    proc `=destroy`(o: var ChainPayloadObj) =
      discard o
      inc chainPayloadDestroyedCount

    objcImpl:
      type NXExceptionChainProtocol =
        concept self
            method outerCall(self: NXExceptionChainProtocol, payload: ChainPayloadRef)
            method middleCall(self: NXExceptionChainProtocol, payload: ChainPayloadRef)
            method innerCall(self: NXExceptionChainProtocol, payload: ChainPayloadRef)

      type NXExceptionChainClass {.impl: NXExceptionChainProtocol.} = object of NSObject

      method outerCall(self: NXExceptionChainClass, payload: ChainPayloadRef) =
        chainOuterPtr = cast[pointer](payload)
        self.middleCall(payload)

      method middleCall(self: NXExceptionChainClass, payload: ChainPayloadRef) =
        let payloadOnStack = payload
        chainMiddlePtr = cast[pointer](payloadOnStack)
        try:
          self.innerCall(payloadOnStack)
        finally:
          echo "FINALLY!"
          chainMiddleAliveInFinally = not payloadOnStack.isNil
          if not payloadOnStack.isNil:
            chainMiddleLabelInFinally = payloadOnStack.label

      method innerCall(self: NXExceptionChainClass, payload: ChainPayloadRef) =
        discard self
        chainInnerPtr = cast[pointer](payload)
        raise newException(ValueError, "exception from innerCall")

    chainPayloadDestroyedCount = 0
    chainOuterPtr = nil
    chainMiddlePtr = nil
    chainInnerPtr = nil
    chainMiddleAliveInFinally = false
    chainMiddleLabelInFinally = ""

    var o = NXExceptionChainClass.new()
    var payload = ChainPayloadRef(label: "chain payload", hops: 1)
    let originalPtr = cast[pointer](payload)

    var caught: ref ValueError
    try:
      o.outerCall(payload)
    except ValueError as e:
      caught = e

    check(caught != nil)
    check(caught.msg == "exception from innerCall")
    check(chainOuterPtr == originalPtr)
    check(chainMiddlePtr == originalPtr)
    check(chainInnerPtr == originalPtr)
    check(chainMiddleAliveInFinally)
    check(chainMiddleLabelInFinally == "chain payload")
    check(chainPayloadDestroyedCount == 0)

    payload = nil
    check(chainPayloadDestroyedCount == 1)
