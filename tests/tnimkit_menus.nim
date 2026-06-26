import std/unittest

import sigils/selectors

import merenda/nimkit

type ContextSpyView = ref object of View
  rightDownCount: int
  handlesRightDown: bool
  actionCount: int

protocol ContextSpyActionProtocol:
  method contextSpyAction*(args: ActionArgs) {.optional.}

protocol ContextSpyEvents of ResponderEventProtocol:
  method rightMouseDown(spy: ContextSpyView, event: MouseEvent): bool =
    discard event
    inc spy.rightDownCount
    spy.handlesRightDown

protocol ContextSpyActions of ContextSpyActionProtocol:
  method contextSpyAction(spy: ContextSpyView, args: ActionArgs) =
    discard args
    inc spy.actionCount

proc newContextSpyView(frame: Rect): ContextSpyView =
  result = ContextSpyView()
  initViewFields(result, frame)
  discard result.withProtocol(ContextSpyEvents)
  discard result.withProtocol(ContextSpyActions)

suite "nimkit menus":
  test "view context menu opens on secondary click and dispatches item action":
    let
      window = newWindow("Context menu", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      target = newContextSpyView(initRect(20, 20, 80, 40))
      menu = newMenu("Actions")
      action = actionSelector("contextSpyAction")
      item = newMenuItem("Run", action)

    discard menu.addItem(item)
    target.setAcceptsFirstResponder(true)
    target.menu = menu
    root.addSubview(target)
    window.setContentView(root)

    check window.makeFirstResponder(target)
    check target.menu == menu
    check window.rightMouseDownAt(initPoint(30, 30), timestamp = 10.0)
    check menu.isOpen()
    check window.hasActiveTransientSession()
    check root.subviews.len == 3
    check root.subviews[1] of PopupMenuButton
    check root.subviews[2] of PopupListView

    let anchor = PopupMenuButton(root.subviews[1])
    check anchor.popupOpen()
    check anchor.hidden()
    check anchor.frame().origin == initPoint(30, 30)
    check window.firstResponder == anchor

    check window.mouseDownAt(initPoint(40, 42), timestamp = 10.1)
    check window.mouseUpAt(initPoint(40, 42), timestamp = 10.2)
    check target.actionCount == 1
    check not menu.isOpen()
    check not window.hasActiveTransientSession()
    check window.firstResponder == target
    check menu.nextResponder() == target
    check root.subviews.len == 1
    check root.subviews[0] == target

  test "view context menu waits for custom right mouse handling":
    let
      window = newWindow("Context fallback", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      target = newContextSpyView(initRect(20, 20, 80, 40))
      menu = newMenu("Actions")

    discard menu.addItem(newMenuItem("Run"))
    target.menu = menu
    root.addSubview(target)
    window.setContentView(root)

    target.handlesRightDown = true
    check window.rightMouseDownAt(initPoint(30, 30), timestamp = 20.0)
    check target.rightDownCount == 1
    check not menu.isOpen()
    check not window.hasActiveTransientSession()
    check root.subviews.len == 1

    target.handlesRightDown = false
    check window.rightMouseDownAt(initPoint(30, 30), timestamp = 21.0)
    check target.rightDownCount == 2
    check menu.isOpen()
    check window.hasActiveTransientSession()
    check window.firstResponder of PopupMenuButton

    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not menu.isOpen()
    check not window.hasActiveTransientSession()
    check window.firstResponder.isNil
    check menu.nextResponder() == target
    check root.subviews.len == 1
