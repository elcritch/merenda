import std/unittest

import knutella/nimkit

suite "nimkit views":
  test "subviews participate in hit testing from front to back":
    let root = newView(0, 0, 200, 160)
    let back = newView(20, 20, 80, 50)
    let front = newView(30, 25, 80, 50)
    root.addSubview(back)
    root.addSubview(front)

    check root.hitTest(initPoint(35, 30)) == front
    check root.hitTest(initPoint(22, 22)) == back
    check root.hitTest(initPoint(199, 159)) == root
    check root.hitTest(initPoint(220, 159)).isNil

  test "hidden views do not hit test":
    let root = newView(0, 0, 200, 160)
    let child = newView(20, 20, 80, 50)
    root.addSubview(child)
    child.setHidden(true)

    check root.hitTest(initPoint(25, 25)) == root

  test "child invalidation propagates to parent":
    let root = newView(0, 0, 200, 160)
    let child = newView(20, 20, 80, 50)
    root.addSubview(child)
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)

    child.setBackgroundColor(initColor(1, 0, 0))

    check child.needsDisplay
    check root.needsDisplay
