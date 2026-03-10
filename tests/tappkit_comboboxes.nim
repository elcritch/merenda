import std/[unittest, tables, unicode]

import figdraw/fignodes
import knutella/appkit
import knutella/objc
import siwin/window as siwin

proc textNodeVerticalMargins(
    renders: Renders
): tuple[found: bool, topMargin: float32, bottomMargin: float32] =
  for _, list in renders.layers.pairs:
    for node in list.nodes:
      if node.kind != nkText or node.textLayout.runes.len <= 0:
        continue
      var foundRect = false
      var minY = 0.0'f32
      var maxY = 0.0'f32
      for rect in node.textLayout.selectionRects:
        if rect.h <= 0.0:
          continue
        if not foundRect:
          minY = rect.y
          maxY = rect.y + rect.h
          foundRect = true
          continue
        minY = min(minY, rect.y)
        maxY = max(maxY, rect.y + rect.h)
      if not foundRect:
        continue
      return (true, minY, max(node.screenBox.h - maxY, 0.0))
  (false, 0.0, 0.0)

proc renderContainsText(renders: Renders, expected: string): bool =
  for _, list in renders.layers.pairs:
    for node in list.nodes:
      if node.kind != nkText or node.textLayout.runes.len <= 0:
        continue
      var text = ""
      for rune in node.textLayout.runes:
        text.add(rune)
      if text == expected:
        return true
  false

proc popupItemScreenPoint(window: NSWindow, combo: NSComboBox, index: int): NSPoint =
  discard window
  var popupFrame = combo.popupWindowFrame()
  popupFrame.size.height =
    comboBoxPopupItemHeight(combo) * comboBoxVisiblePopupItems(combo).float32 + 2.0
  let itemHeight = comboBoxPopupItemHeight(combo)
  nsPoint(
    popupFrame.origin.x + popupFrame.size.width * 0.5,
    popupFrame.origin.y + popupFrame.size.height - 1.0 - index.float32 * itemHeight -
      itemHeight * 0.5,
  )

proc popupWindowItemScreenPoint(popup: NSComboBoxWindow, index: int): NSPoint =
  if popup.isNil or popup.contentView().isNil:
    return nsPoint(0.0, 0.0)
  let popupSubviews = popup.contentView().subviews()
  if popupSubviews.len == 0:
    return nsPoint(0.0, 0.0)
  let popupScrollView = popupSubviews[0].NSScrollView
  if popupScrollView.isNil:
    return nsPoint(0.0, 0.0)
  let popupView = popupScrollView.documentView().NSComboBoxView
  if popupView.isNil:
    return nsPoint(0.0, 0.0)
  let itemRect = popupView.rectForItemAtIndex(index)
  let itemPoint = nsPoint(
    itemRect.origin.x + itemRect.size.width * 0.5,
    itemRect.origin.y + itemRect.size.height * 0.5,
  )
  let popupPoint = popupView.convertPointToView(itemPoint, NSView(value: nil))
  popup.convertBaseToScreen(popupPoint)

proc clickComboBoxArrow(app: NSApplication, window: NSWindow, combo: NSComboBox) =
  if app.isNil or window.isNil or combo.isNil:
    return
  let frame = combo.frame()
  let point = nsPoint(
    frame.origin.x + frame.size.width - 5.0, frame.origin.y + frame.size.height * 0.5
  )
  let down = mouseButtonEventFromSiwin(
    window.windowNumber(),
    point,
    siwin.MouseButtonEvent(
      button: siwin.MouseButton.left, pressed: true, generated: false
    ),
  )
  let up = mouseButtonEventFromSiwin(
    window.windowNumber(),
    point,
    siwin.MouseButtonEvent(
      button: siwin.MouseButton.left, pressed: false, generated: false
    ),
  )
  app.postEvent(down, false)
  app.postEvent(up, false)

proc clickPopupItem(app: NSApplication, popup: NSWindow, screenPoint: NSPoint) =
  if app.isNil or popup.isNil:
    return
  let point = popup.convertScreenToBase(screenPoint)
  let down = mouseButtonEventFromSiwin(
    popup.windowNumber(),
    point,
    siwin.MouseButtonEvent(
      button: siwin.MouseButton.left, pressed: true, generated: false
    ),
  )
  let up = mouseButtonEventFromSiwin(
    popup.windowNumber(),
    point,
    siwin.MouseButtonEvent(
      button: siwin.MouseButton.left, pressed: false, generated: false
    ),
  )
  app.postEvent(down, false)
  app.postEvent(up, false)

objcImpl:
  type TestComboBox = object of NSComboBox
    xCapturedPopup {.get: capturedPopup.}: NSComboBoxWindow
    xClosePopupCallCount {.get: closePopupCallCount.}: int

  method init*(self: var TestComboBox): TestComboBox =
    result =
      asTypeRaw[TestComboBox](callSuperIdFrom(TestComboBox, self, getSelector("init")))
    if result.isNil:
      return
    initIvarFields(result)
    result.xCapturedPopup = NSComboBoxWindow(value: nil)
    result.xClosePopupCallCount = 0

  method closePopupWindow*(self: TestComboBox) =
    if self.xCapturedPopup.isNil:
      self.xCapturedPopup = self.popupWindow()
    inc self.xClosePopupCallCount
    callSuperVoid(self, getSelector("closePopupWindow"))

  method dealloc(self: TestComboBox) {.used.} =
    self.xCapturedPopup = NSComboBoxWindow(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(TestComboBox, self, getSelector("dealloc"))

suite "appkit combobox":
  test "selection APIs keep displayed item in sync with selected item":
    var combo = NSComboBox.new()
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")

    combo.selectItemAtIndex(1)
    check(combo.indexOfSelectedItem() == 1)
    check(combo.stringValue() == @ns"item2")

    combo.selectItemAtIndex(-1)
    check(combo.indexOfSelectedItem() == 1)
    check(combo.stringValue() == @ns"item2")

    combo.selectItemAtIndex(99)
    check(combo.indexOfSelectedItem() == 1)
    check(combo.stringValue() == @ns"item2")

    combo.selectItemWithObjectValue(@ns"item3")
    check(combo.indexOfSelectedItem() == 2)
    check(combo.stringValue() == @ns"item3")

    combo.selectItemWithObjectValue(@ns"missing")
    check(combo.indexOfSelectedItem() == 2)
    check(combo.stringValue() == @ns"item3")

    combo.setObjectValue(@ns"item1".NSObject)
    check(combo.indexOfSelectedItem() == 0)
    check(combo.stringValue() == @ns"item1")

    combo.value = nil

  test "selected item renders in combo control text":
    var window = newWindow(0.0, 0.0, 260.0, 140.0, "combo render probe")
    var root = newView(0.0, 0.0, 260.0, 140.0)
    var combo = NSComboBox.new()
    combo.setFrame(nsRect(10.0, 10.0, 121.0, 26.0))
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")
    combo.selectItemAtIndex(1)
    root.addSubview(combo.NSView)
    window.setContentView(root)

    let renders = debugBuildWindowRenders(window)
    check(not renders.isNil)
    check(renderContainsText(renders, "item2"))
    check(combo.stringValue() == @ns"item2")

    combo.value = nil
    root.value = nil
    window.value = nil

  test "mouse click opens a borderless popup window":
    var app = NSApplication.new()
    var window = newWindow(0, 0, 240, 120, "Combo Popup")
    var root = newView(0, 0, 240, 120)

    var comboAlloc = TestComboBox.alloc()
    var combo = comboAlloc.init()
    comboAlloc.value = nil
    combo.setFrame(nsRect(10.0, 10.0, 121.0, 26.0))
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")
    root.addSubview(combo.NSView)
    window.setContentView(root)
    app.addWindow(window)

    let clickPoint = nsPoint(126.0, 20.0)
    let down = mouseButtonEventFromSiwin(
      window.windowNumber(),
      clickPoint,
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: true, generated: false
      ),
    )
    let drag = mouseMoveEventFromSiwin(
      window.windowNumber(),
      nsPoint(clickPoint.x, clickPoint.y + 8.0),
      siwin.MouseMoveEvent(kind: siwin.MouseMoveKind.moveWhileDragging),
      {},
      {siwin.MouseButton.left},
    )
    let up = mouseButtonEventFromSiwin(
      window.windowNumber(),
      nsPoint(clickPoint.x, clickPoint.y + 8.0),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: false, generated: false
      ),
    )

    app.postEvent(drag, false)
    app.postEvent(up, false)
    app.sendEvent(down)

    let popup = combo.capturedPopup()
    let ownerFrame = window.frame()
    check(combo.closePopupCallCount() == 1)
    check(not popup.isNil)
    check(popup.styleMask() == NSBorderlessWindowMask)
    check(popup.isReleasedWhenClosed())
    check(popup.windowClosed())
    check(not popup.contentView().isNil)
    check(popup.frame().size.width > 0.0)
    check(popup.frame().size.height > 0.0)
    check(popup.frame().origin.x >= ownerFrame.origin.x)
    check(popup.frame().origin.x <= ownerFrame.origin.x + ownerFrame.size.width)
    check(NSTitledWindow in window.styleMask())
    check(combo.popupWindow().isNil)
    check(not combo.popupOpen())

    combo.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "native run loop click tracking does not crash popup flush":
    var app = NSApplication.new()
    var window = newWindow(0, 0, 240, 120, "Combo Popup Native")
    var root = newView(0, 0, 240, 120)

    var comboAlloc = TestComboBox.alloc()
    var combo = comboAlloc.init()
    comboAlloc.value = nil
    combo.setFrame(nsRect(10.0, 10.0, 121.0, 26.0))
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")
    root.addSubview(combo.NSView)
    window.setContentView(root)
    app.addWindow(window)
    window.makeKeyAndOrderFront(app.NSObject)

    let clickPoint = nsPoint(126.0, 20.0)
    let down = mouseButtonEventFromSiwin(
      window.windowNumber(),
      clickPoint,
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: true, generated: false
      ),
    )
    let drag = mouseMoveEventFromSiwin(
      window.windowNumber(),
      nsPoint(clickPoint.x, clickPoint.y + 8.0),
      siwin.MouseMoveEvent(kind: siwin.MouseMoveKind.moveWhileDragging),
      {},
      {siwin.MouseButton.left},
    )
    let up = mouseButtonEventFromSiwin(
      window.windowNumber(),
      nsPoint(clickPoint.x, clickPoint.y + 8.0),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: false, generated: false
      ),
    )

    app.postEvent(down, false)
    app.postEvent(drag, false)
    app.postEvent(up, false)
    discard app.runForFrames(20)

    let popup = combo.capturedPopup()
    check(combo.closePopupCallCount() == 1)
    check(not popup.isNil)
    check(popup.styleMask() == NSBorderlessWindowMask)
    check(combo.popupWindow().isNil)
    check(not combo.popupOpen())
    check(NSTitledWindow in window.styleMask())

    combo.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "mouse selection through popup chooses item and closes safely":
    var app = NSApplication.new()
    var window = newWindow(0, 0, 240, 120, "Combo Popup Select")
    var root = newView(0, 0, 240, 120)

    var comboAlloc = TestComboBox.alloc()
    var combo = comboAlloc.init()
    comboAlloc.value = nil
    combo.setFrame(nsRect(10.0, 10.0, 121.0, 26.0))
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")
    root.addSubview(combo.NSView)
    window.setContentView(root)
    app.addWindow(window)
    window.makeKeyAndOrderFront(app.NSObject)

    let arrowPoint = nsPoint(126.0, 20.0)
    let popupTarget = window.convertScreenToBase(popupItemScreenPoint(window, combo, 1))
    let down = mouseButtonEventFromSiwin(
      window.windowNumber(),
      arrowPoint,
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: true, generated: false
      ),
    )
    let drag = mouseMoveEventFromSiwin(
      window.windowNumber(),
      popupTarget,
      siwin.MouseMoveEvent(kind: siwin.MouseMoveKind.moveWhileDragging),
      {},
      {siwin.MouseButton.left},
    )
    let up = mouseButtonEventFromSiwin(
      window.windowNumber(),
      popupTarget,
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: false, generated: false
      ),
    )

    app.postEvent(down, false)
    app.postEvent(drag, false)
    app.postEvent(up, false)
    discard app.runForFrames(20)

    check(combo.indexOfSelectedItem() == 1)
    check(combo.stringValue() == @ns"item2")
    check(combo.closePopupCallCount() == 1)
    check(combo.popupWindow().isNil)
    check(not combo.popupOpen())

    combo.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "plain mouse click opens persistent popup without blocking":
    var app = NSApplication.new()
    var window = newWindow(0, 0, 240, 120, "Combo Popup Persistent")
    var root = newView(0, 0, 240, 120)

    var comboAlloc = TestComboBox.alloc()
    var combo = comboAlloc.init()
    comboAlloc.value = nil
    combo.setFrame(nsRect(10.0, 10.0, 121.0, 26.0))
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")
    root.addSubview(combo.NSView)
    window.setContentView(root)
    app.addWindow(window)
    window.makeKeyAndOrderFront(app.NSObject)

    clickComboBoxArrow(app, window, combo)
    discard app.runForFrames(5)

    check(combo.popupOpen())
    check(not combo.popupWindow().isNil)
    check(combo.closePopupCallCount() == 0)

    combo.closePopup()
    check(combo.popupWindow().isNil)
    check(not combo.popupOpen())

    combo.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "persistent popup click selects item, closes, and shows chosen item":
    var app = NSApplication.new()
    var window = newWindow(0, 0, 240, 120, "Combo Popup Persistent Select")
    var root = newView(0, 0, 240, 120)

    var comboAlloc = TestComboBox.alloc()
    var combo = comboAlloc.init()
    comboAlloc.value = nil
    combo.setFrame(nsRect(10.0, 10.0, 121.0, 26.0))
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")
    root.addSubview(combo.NSView)
    window.setContentView(root)
    app.addWindow(window)
    window.makeKeyAndOrderFront(app.NSObject)

    clickComboBoxArrow(app, window, combo)
    discard app.runForFrames(5)

    let popup = combo.popupWindow()
    check(not popup.isNil)
    clickPopupItem(app, popup.NSWindow, popupWindowItemScreenPoint(popup, 2))
    discard app.runForFrames(5)

    check(combo.indexOfSelectedItem() == 2)
    check(combo.stringValue() == @ns"item3")
    let windowRenders = debugBuildWindowRenders(window)
    check(not windowRenders.isNil)
    check(renderContainsText(windowRenders, "item3"))
    check(combo.closePopupCallCount() == 1)
    check(combo.popupWindow().isNil)
    check(not combo.popupOpen())

    combo.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "popup render tree uses transform and inverted text nodes":
    var app = NSApplication.new()
    var window = newWindow(0, 0, 240, 120, "Combo Popup Render")
    var root = newView(0, 0, 240, 120)

    var comboAlloc = TestComboBox.alloc()
    var combo = comboAlloc.init()
    comboAlloc.value = nil
    combo.setFrame(nsRect(10.0, 10.0, 121.0, 26.0))
    combo.addItemWithObjectValue(@ns"item1")
    combo.addItemWithObjectValue(@ns"item2")
    combo.addItemWithObjectValue(@ns"item3")
    root.addSubview(combo.NSView)
    window.setContentView(root)
    app.addWindow(window)

    combo.openPopup()

    let popup = combo.popupWindow()
    check(not popup.isNil)
    check(not popup.contentView().isNil)

    let popupSubviews = popup.contentView().subviews()
    check(popupSubviews.len > 0)
    let popupScrollView =
      if popupSubviews.len > 0:
        NSScrollView(popupSubviews[0])
      else:
        NSScrollView(value: nil)
    let popupDocView =
      if popupScrollView.isNil:
        NSView(value: nil)
      else:
        popupScrollView.documentView()
    check(not popupDocView.isNil)
    check(not popupDocView.isFlipped())

    let renders = debugBuildWindowRenders(popup.NSWindow)
    check(not renders.isNil)

    var foundTransform = false
    var foundText = false
    for _, list in pairs(renders.layers):
      for node in list.nodes:
        if node.kind == nkTransform:
          foundTransform = true
        elif node.kind == nkText and node.textLayout.runes.len > 0:
          foundText = true
          check(NfInvertY in node.flags)

    check(foundTransform)
    check(foundText)
    let margins = textNodeVerticalMargins(renders)
    check(margins.found)
    check(abs(margins.topMargin - margins.bottomMargin) <= 2.0)

    combo.closePopup()
    check(combo.popupWindow().isNil)

    combo.value = nil
    root.value = nil
    window.value = nil
    app.value = nil
