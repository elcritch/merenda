import std/unittest
import nutella/objc
import nutella/objc/assoc

type AssociatedStateObj = object
  value: int
type AssociatedStateRef = ref AssociatedStateObj

var associatedStateDestroyedCount = 0

proc `=destroy`(o: var AssociatedStateObj) =
  inc associatedStateDestroyedCount

suite "objc associated state Nim ref storage":

  test "associated Nim ref survives and clears cleanly":
    associatedStateDestroyedCount = 0
    var o = NSObject.new()
    var state = AssociatedStateRef(value: 42)
    setAssociatedRef(o, state)
    state = nil

    block:
      let loaded = o.getAssociatedRef(AssociatedStateRef)
      check(loaded != nil)
      check(loaded.value == 42)

    clearAssociatedRef[AssociatedStateRef](o)
    check(o.getAssociatedRef(AssociatedStateRef) == nil)
    check(associatedStateDestroyedCount == 1)

  test "associated Nim ref is released on owning object dealloc":
    associatedStateDestroyedCount = 0
    var o = NSObject.new()
    var state = AssociatedStateRef(value: 77)
    setAssociatedRef(o, state)
    state = nil

    release(o)
    check(o.isNil)
    check(associatedStateDestroyedCount == 1)
