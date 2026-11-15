import std/unittest
import sigils/core
import merenda/nimkit/foundation/sourcedispatch

suite "source dispatch cleanup":
  test "disconnects wait for the outermost dispatch of their own source":
    let a = Agent()
    let b = Agent()
    var events: seq[string]
    beginSourceDispatch(a)
    beginSourceDispatch(b)
    beginSourceDispatch(a)
    check deferSourceWork(
      a,
      proc() =
        events.add "a"
      ,
    )
    check deferSourceWork(
      b,
      proc() =
        events.add "b"
      ,
    )
    endSourceDispatch(a)
    check events.len == 0
    endSourceDispatch(b)
    check events == @["b"]
    endSourceDispatch(a)
    check events == @["b", "a"]
    check not deferSourceWork(
      a,
      proc() =
        events.add "unexpected"
      ,
    )
