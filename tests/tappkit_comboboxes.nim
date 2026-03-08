import std/[unittest, tables]

import figdraw/fignodes
import knutella/appkit
import knutella/objc
import siwin/window as siwin

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

    combo.closePopup()
    check(combo.popupWindow().isNil)

    combo.value = nil
    root.value = nil
    window.value = nil
    app.value = nil
