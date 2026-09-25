import std/unittest

import sigils/core

import merenda/nimkit

proc center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0, rect.origin.y + rect.size.height / 2.0
  )

suite "nimkit segmented controls":
  test "segments are a single-row radio matrix with toggle cells":
    let control = newSegmentedControl(
      ["All entries", "Normal only", "Ignored only"], frame = rect(0, 0, 280, 30)
    )

    check control.rows == 1
    check control.columns == 3
    check control.segmentCount == 3
    check control.selectionMode == msmRadio
    check control.selectedSegmentIndex == 0
    check control.cellAtIndex(0).buttonType == btToggle
    check control.cellAtIndex(0).state == bsOn
    check control.cellAtIndex(1).state == bsOff

  test "segments select one item and dispatch one matrix action":
    let
      window = newWindow("Segmented control", frame = rect(0, 0, 280, 100))
      root = newView(frame = rect(0, 0, 280, 100))
      control =
        newSegmentedControl(["All", "Normal", "Ignored"], frame = rect(10, 10, 260, 30))
      action = actionSelector("segmentChanged")

    var actionCount = 0
    proc onChanged(sender: DynamicAgent) =
      check sender == DynamicAgent(control)
      inc actionCount

    control.target = newActionTarget(action, onChanged)
    control.action = action
    root.addSubview(control)
    window.setContentView(root)

    let point = control.pointToWindow(control.cellFrameAtIndex(2).center())
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check control.selectedSegmentIndex == 2
    check control.cellAtIndex(0).state == bsOff
    check control.cellAtIndex(2).state == bsOn
    check actionCount == 1

    control.selectedSegmentIndex = 1
    check control.selectedSegmentIndex == 1
    check actionCount == 1

    check window.makeFirstResponder(control)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check control.selectedSegmentIndex == 0
    check actionCount == 2
