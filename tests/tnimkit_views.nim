import std/unittest

import knutella/nimkit

type MouseSpyView = ref object of View

var
  spyMouseDownPoint: Point
  spyMouseUpPoint: Point
  spyMouseDownCount: int
  spyMouseUpCount: int

protocol MouseSpyEvents of ResponderEventProtocol:
  method mouseDown(spy: MouseSpyView, event: MouseEvent) =
    spyMouseDownPoint = event.location
    inc spyMouseDownCount

  method mouseUp(spy: MouseSpyView, event: MouseEvent) =
    spyMouseUpPoint = event.location
    inc spyMouseUpCount

proc newMouseSpyView(frame: Rect): MouseSpyView =
  result = MouseSpyView()
  initViewFields(result, frame)
  discard result.withProtocol(MouseSpyEvents)

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

  test "coordinate conversion covers hierarchy, siblings, and rectangles":
    let
      root = newView(0, 0, 300, 240)
      child = newView(20, 30, 100, 80)
      sibling = newView(150, 40, 70, 60)
      grandchild = newView(5, 7, 30, 20)

    root.addSubview(child)
    root.addSubview(sibling)
    child.addSubview(grandchild)

    check root.pointFromView(initPoint(3, 4), child) == initPoint(23, 34)
    check child.pointToView(initPoint(3, 4), root) == initPoint(23, 34)
    check child.pointFromView(initPoint(23, 34), root) == initPoint(3, 4)
    check sibling.pointFromView(initPoint(3, 4), child) == initPoint(-127, -6)
    check grandchild.pointToView(initPoint(1, 2), root) == initPoint(26, 39)

    check root.rectFromView(initRect(1, 2, 10, 11), child) == initRect(21, 32, 10, 11)
    check child.rectFromView(initRect(21, 32, 10, 11), root) == initRect(1, 2, 10, 11)

  test "coordinate conversion honors non-zero bounds origins":
    let
      root = newView(0, 0, 300, 240)
      child = newView(30, 40, 100, 80)

    root.setBounds(initRect(10, 20, 300, 240))
    child.setBounds(initRect(5, 6, 100, 80))
    root.addSubview(child)

    check child.pointFromView(initPoint(30, 40), root) == initPoint(5, 6)
    check root.pointFromView(initPoint(5, 6), child) == initPoint(30, 40)
    check child.pointToWindow(initPoint(5, 6)) == initPoint(20, 20)
    check child.pointFromWindow(initPoint(20, 20)) == initPoint(5, 6)

  test "coordinate conversion updates after reparenting":
    let
      firstRoot = newView(0, 0, 200, 160)
      secondRoot = newView(10, 15, 200, 160)
      child = newView(20, 30, 80, 40)

    firstRoot.addSubview(child)
    check child.pointToWindow(initPoint(0, 0)) == initPoint(20, 30)

    secondRoot.addSubview(child)
    check child.superview == secondRoot
    check child.pointToWindow(initPoint(0, 0)) == initPoint(30, 45)

  test "window coordinate helpers convert through content view frames and bounds":
    let content = newView(10, 15, 240, 180)
    content.setBounds(initRect(5, 7, 240, 180))

    check content.pointToWindow(initPoint(5, 7)) == initPoint(10, 15)
    check content.pointFromWindow(initPoint(10, 15)) == initPoint(5, 7)
    check content.rectToWindow(initRect(5, 7, 20, 30)) == initRect(10, 15, 20, 30)
    check content.rectFromWindow(initRect(10, 15, 20, 30)) == initRect(5, 7, 20, 30)

  test "hit testing and mouse dispatch use conversion helpers":
    let
      root = newView(0, 0, 200, 160)
      child = newMouseSpyView(initRect(30, 40, 80, 50))

    root.setBounds(initRect(10, 20, 200, 160))
    child.setBounds(initRect(5, 6, 80, 50))
    root.addSubview(child)

    spyMouseDownPoint = initPoint(0, 0)
    spyMouseUpPoint = initPoint(0, 0)
    spyMouseDownCount = 0
    spyMouseUpCount = 0

    check root.hitTest(initPoint(30, 40)) == child
    check root.clickAt(initPoint(30, 40))
    check spyMouseDownPoint == initPoint(5, 6)
    check spyMouseUpPoint == initPoint(5, 6)
    check spyMouseDownCount == 1
    check spyMouseUpCount == 1
