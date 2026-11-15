import std/unittest
import merenda/nimkit/foundation/sourcedispatch

suite "source dispatch cleanup":
  test "disconnects wait for the outermost dispatch of their own source":
    var first, second: int
    let a = cast[pointer](addr first)
    let b = cast[pointer](addr second)
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
