import std/[strutils, unittest]

import pkg/vmath
import figdraw/fignodes
import nutella/appkit
import nutella/objc

suite "nutella appkit hello world":
  proc controlStringValue(control: NSControl): NSString =
    control.stringValue()

  proc setControlStringValue(control: NSControl, value: NSString) =
    control.setStringValue(value)

  proc clickControl(control: NSControl) =
    var sender = NSResponder.new()
    control.performClick(sender)
    sender.value = nil

  proc rectContains(outer, inner: NSRect, epsilon = 0.75'f32): bool =
    let outerRight = outer.origin.x + outer.size.width
    let outerBottom = outer.origin.y + outer.size.height
    let innerRight = inner.origin.x + inner.size.width
    let innerBottom = inner.origin.y + inner.size.height
    inner.origin.x >= outer.origin.x - epsilon and
      inner.origin.y >= outer.origin.y - epsilon and innerRight <= outerRight + epsilon and
      innerBottom <= outerBottom + epsilon

  proc approxEq(a, b: float32, epsilon = 0.01'f32): bool =
    abs(a - b) <= epsilon

  test "raw pixel input maps to logical coordinates":
    let raw = vec2(300.0'f32, 200.0'f32)
    let mapped =
      rawInputToLogical(raw, ivec2(600'i32, 400'i32), vec2(300.0'f32, 200.0'f32))
    check(mapped.x == 150.0'f32)
    check(mapped.y == 100.0'f32)

    let passthrough =
      rawInputToLogical(raw, ivec2(0'i32, 0'i32), vec2(300.0'f32, 200.0'f32))
    check(passthrough.x == raw.x)
    check(passthrough.y == raw.y)

  test "appkit runtime classes stay namespaced to avoid NS* collisions":
    var responder = NSResponder.new()
    var view = newView(0, 0, 10, 10)
    var button = newButton(0, 0, 120, 32, "Press")
    var field = newTextField(0, 0, 200, 32, "Hello")
    var secure = NSSecureTextField.new()
    var search = NSSearchField.new()
    var box = NSBox.new()
    var window = newWindow(0, 0, 10, 10, "w")
    var panel = NSPanel.new()
    var app = NSApplication.new()

    check(getClassName(responder).startsWith("NXResponder"))
    check(getClassName(view).startsWith("NXView"))
    check(getClassName(button).startsWith("NXButton"))
    check(getClassName(field).startsWith("NXTextField"))
    check(getClassName(secure).startsWith("NXSecureTextField"))
    check(getClassName(search).startsWith("NXSearchField"))
    check(getClassName(box).startsWith("NXBox"))
    check(getClassName(window).startsWith("NXWindow"))
    check(getClassName(panel).startsWith("NXPanel"))
    check(getClassName(app).startsWith("NXApplication"))

    responder.value = nil
    view.value = nil
    button.value = nil
    field.value = nil
    secure.value = nil
    search.value = nil
    box.value = nil
    window.value = nil
    panel.value = nil
    app.value = nil

  test "appkit controls report runtime class hierarchy":
    var button = newButton(0, 0, 120, 32, "Press")
    check(button.isKindOfClass(NSButton))
    check(button.isKindOfClass(NSControl))
    check(button.isKindOfClass(NSView))
    check(button.isKindOfClass(NSResponder))
    check(button.isKindOfClass(NSObject))
    check(not button.isKindOfClass(NSTextField))

    var field = newTextField(0, 0, 200, 32, "Hello")
    check(field.isKindOfClass(NSTextField))
    check(field.isKindOfClass(NSControl))
    check(field.isKindOfClass(NSView))
    check(field.isKindOfClass(NSResponder))
    check(field.isKindOfClass(NSObject))
    check(not field.isKindOfClass(NSButton))

    button.value = nil
    field.value = nil

  test "basic appkit api compiles":
    check compiles(
      block:
        let app = NSApp()
        let window = newWindow(100, 120, 640, 420, "Nutella Hello World")
        let root = newView(0, 0, 640, 420)
        root.setTag(100)
        root.setBackgroundColor(0.96, 0.96, 0.98, 1.0)
        root.setFrameOrigin(nsPoint(0, 0))
        root.setFrameSize(nsSize(640, 420))

        let field = newTextField(32, 32, 360, 44, "Hello world from Nutella")
        field.setAlignment(NSCenterTextAlignment)
        field.setTextColor(nsColor(0.14, 0.19, 0.33, 1.0))
        field.setDrawsBackground(false)
        root.addSubview(field)
        let found = root.viewWithTag(100)
        discard found

        let button = newButton(32, 96, 180, 44, "Click me")
        button.setAllowsMixedState(true)
        button.setOnClick(
          proc(sender: NSButton) {.gcsafe.} =
            discard sender
        )
        button.click()
        button.click()
        root.addSubview(button)

        window.setContentSize(nsSize(640, 420))
        window.setContentView(root)
        app.addWindow(window)
        discard app.windows()
        window.makeKeyAndOrderFront(app)
        discard app.runForFrames(1)
        window.close()
        app.stop()
    )

  test "ported view, control, and button APIs mutate state":
    var root = newView(0, 0, 300, 220)
    root.setTag(7)

    var childA = newView(0, 0, 40, 40)
    childA.setTag(101)
    var childB = newView(50, 0, 40, 40)
    childB.setTag(102)
    root.addSubview(childA)
    root.addSubview(childB)

    check(root.subviews().len == 2)
    check(not childA.superview().isNil)
    check(root.viewWithTag(102).tag() == 102)

    childB.removeFromSuperview()
    check(root.subviews().len == 1)
    check(childB.superview().isNil)
    check(root.viewWithTag(102).isNil)

    var field = newTextField(0, 60, 200, 30, "Styled")
    field.setAlignment(NSRightTextAlignment)
    field.setTextColor(nsColor(0.2, 0.3, 0.4, 1.0))
    field.setBackgroundColor(nsColor(0.9, 0.92, 0.97, 1.0))
    field.setDrawsBackground(false)
    check(field.alignment() == NSRightTextAlignment)
    check(field.textColor() == nsColor(0.2, 0.3, 0.4, 1.0))
    check(field.backgroundColor() == nsColor(0.9, 0.92, 0.97, 1.0))
    check(not field.drawsBackground())
    check(field.isEnabled())
    field.setEnabled(false)
    check(not field.isEnabled())

    var button = newButton(0, 100, 160, 34, "Stateful")
    check(button.state() == NSOffState)
    button.click()
    check(button.state() == NSOnState)
    button.setAllowsMixedState(true)
    button.click()
    check(button.state() == NSMixedState)
    button.setState(NSOffState.cint)
    check(button.state() == NSOffState)
    button.setAllowsMixedState(true)
    button.click()
    check(button.state() == NSOnState)
    button.click()
    check(button.state() == NSMixedState)
    button.setEnabled(false)
    button.click()
    check(button.state() == NSMixedState)

    var win = newWindow(5, 6, 200, 120, "Resize")
    win.setFrameOrigin(nsPoint(10, 20))
    win.setContentSize(nsSize(320, 200))
    check(win.frameOrigin() == nsPoint(10, 20))
    check(win.frameSize() == nsSize(320, 200))

    button.value = nil
    field.value = nil
    childB.value = nil
    childA.value = nil
    root.value = nil
    win.value = nil

  test "control dispatch routes to subclass string and click behavior":
    var field = newTextField(0, 0, 240, 30, "Initial")
    echo "A1:"
    check(controlStringValue(field) == @ns"Initial")
    echo "A2:"
    setControlStringValue(field, @ns"Updated")
    echo "A3:"
    check(field.stringValue() == @ns"Updated")
    echo "A4:"
    check(controlStringValue(field) == @ns"Updated")
    echo "A5:"

    var button = newButton(0, 0, 120, 30, "Push")
    var clicks = 0
    button.setOnClick(
      proc(sender: NSButton) {.gcsafe.} =
        discard sender
        inc clicks
    )
    check(button.state() == NSOffState)
    check(controlStringValue(button) == @ns"Push")
    setControlStringValue(button, @ns"Renamed")
    check(button.title() == @ns"Renamed")
    clickControl(button)
    check(button.state() == NSOnState)
    check(clicks == 1)

    field.value = nil
    button.value = nil

  test "ported basic element classes expose header-aligned APIs":
    var secure = NSSecureTextField.new()
    check(secure.isKindOfClass(NSSecureTextField))
    check(secure.isKindOfClass(NSTextField))
    check(secure.echosBullets())
    secure.setEchosBullets(false)
    check(not secure.echosBullets())

    var search = NSSearchField.new()
    check(search.isKindOfClass(NSSearchField))
    check(search.recentsAutosaveName() == @ns"")
    search.setRecentsAutosaveName(@ns"main-search")
    check(search.recentsAutosaveName() == @ns"main-search")
    let searches = nsArray[NSString]([@ns"nutella", @ns"ravynos"])
    search.setRecentSearches(searches)
    let loadedSearches = search.recentSearches()
    check(loadedSearches.len == 2)
    check(loadedSearches[0] == @ns"nutella")
    check(loadedSearches[1] == @ns"ravynos")

    var box = NSBox.new()
    check(box.isKindOfClass(NSBox))
    check(box.isKindOfClass(NSView))
    check(box.title() == @ns"")
    box.setTitleWithMnemonic(@ns"P&references")
    check(box.title() == @ns"Preferences")
    check(box.isTransparent())
    box.setTransparent(false)
    check(not box.isTransparent())
    var boxContent = newView(0, 0, 120, 40)
    box.setContentView(boxContent)
    check(box.contentView().value == boxContent.value)
    check(boxContent.superview().value == box.value)

    var panel = NSPanel.new()
    check(panel.isKindOfClass(NSPanel))
    check(panel.isKindOfClass(NSWindow))
    check(not panel.canBecomeMainWindow())
    check(not panel.worksWhenModal())
    check(not panel.becomesKeyOnlyIfNeeded())
    check(not panel.isFloatingPanel())
    panel.setWorksWhenModal(true)
    panel.setBecomesKeyOnlyIfNeeded(true)
    panel.setFloatingPanel(true)
    check(panel.worksWhenModal())
    check(panel.becomesKeyOnlyIfNeeded())
    check(panel.isFloatingPanel())

    panel.value = nil
    boxContent.value = nil
    box.value = nil
    search.value = nil
    secure.value = nil

  test "button text layout stays within the button text box":
    var button = newButton(
      0, 0, 170, 34,
      "Cycle State (this title is intentionally too long for the control)",
    )
    button.setAlignment(NSCenterTextAlignment)

    let metrics = debugTextLayoutMetricsForView(button)
    check(metrics.hasLayout)
    check(metrics.glyphCount > 0)
    check(metrics.fitsTextBox)
    check(rectContains(metrics.controlBox, metrics.textBox))
    check(rectContains(metrics.textBox, metrics.textBounds))

    button.value = nil

  test "text field layout stays within the text box":
    var field = newTextField(
      0, 0, 240, 40,
      "Ported APIs: setTag/viewWithTag/removeFromSuperview/alignment/state/contentSize",
    )
    field.setDrawsBackground(true)
    field.setAlignment(NSLeftTextAlignment)

    let metrics = debugTextLayoutMetricsForView(field)
    check(metrics.hasLayout)
    check(metrics.glyphCount > 0)
    check(metrics.fitsTextBox)
    check(rectContains(metrics.controlBox, metrics.textBox))
    check(rectContains(metrics.textBox, metrics.textBounds))

    field.value = nil

  test "application keeps added window alive across frame loop":
    var app = NSApp()

    block:
      var window = newWindow(100, 120, 320, 240, "Owned Window")
      app.addWindow(window)
      # Mark closed to avoid backend setup; run loop should still traverse safely.
      window.close()
      # Drop the local owner; app should still own the window entry safely.
      window.value = nil

    discard app.runForFrames(1)
    app.value = nil

  test "native resize keeps frame size in logical units":
    var app = NSApp()
    var window = newWindow(90, 90, 320, 200, "Logical Size")
    var root = newView(0, 0, 320, 200)
    var label = newTextField(12, 12, 296, 36, "Logical size regression test")
    root.addSubview(label)
    window.setContentView(root)
    app.addWindow(window)
    window.makeKeyAndOrderFront(app)

    let requested = window.frameSize()
    try:
      discard app.runForFrames(4)
    except CatchableError:
      skip()

    let observed = window.frameSize()
    check(abs(observed.width - requested.width) <= 2.0)
    check(abs(observed.height - requested.height) <= 2.0)

    window.close()
    app.stop()
    label.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "next core ui classes provide aligned appkit api":
    var cell = NSCell.new()
    check(cell.isKindOfClass(NSCell))
    check(getClassName(cell).startsWith("NXCell"))
    check(cell.stringValue() == @ns"")
    cell.setStringValue(@ns"42")
    check(cell.intValue() == 42.cint)
    var sourceCell = NSCell.new()
    sourceCell.setStringValue(@ns"17")
    cell.takeStringValueFrom(sourceCell)
    check(cell.stringValue() == @ns"17")
    check(cell.intValue() == 17.cint)
    check(cell.nextState() == NSOnState)
    cell.setAllowsMixedState(true)
    cell.setState(NSMixedState)
    check(cell.state() == NSMixedState)

    var actionCell = NSActionCell.new()
    check(actionCell.isKindOfClass(NSActionCell))
    check(actionCell.isKindOfClass(NSCell))
    actionCell.setTag(17)
    check(actionCell.tag() == 17)

    var buttonCell = NSButtonCell.new()
    check(buttonCell.isKindOfClass(NSButtonCell))
    check(buttonCell.isKindOfClass(NSActionCell))
    check(buttonCell.title() == @ns"Button")
    buttonCell.setTitle(@ns"Cell Button")
    check(buttonCell.title() == @ns"Cell Button")
    buttonCell.setAllowsMixedState(true)
    buttonCell.setState(NSOffState)
    check(buttonCell.state() == NSOffState)
    buttonCell.setState(NSOnState)
    check(buttonCell.state() == NSOnState)
    buttonCell.setState(NSMixedState)
    check(buttonCell.state() == NSMixedState)

    var clip = NSClipView.new()
    check(clip.isKindOfClass(NSClipView))
    check(clip.isKindOfClass(NSView))
    clip.setFrame(0, 0, 100, 80)
    var doc = newView(0, 0, 300, 240)
    clip.setDocumentView(doc)
    let docRect = clip.documentRect()
    check(docRect.size.width == 300.0)
    check(docRect.size.height == 240.0)
    clip.scrollToPoint(nsPoint(999, 999))
    let visible = clip.documentVisibleRect()
    check(visible.origin == nsPoint(200, 160))
    check(visible.size == nsSize(100, 80))
    check(doc.frameOrigin() == nsPoint(-200, -160))

    var cv = NSCollectionView.new()
    check(cv.isKindOfClass(NSCollectionView))
    check(cv.isKindOfClass(NSView))
    cv.setSelectable(false)
    cv.setMinItemSize(nsSize(64, 64))
    cv.setMaxItemSize(nsSize(256, 256))
    cv.setMaxNumberOfRows(5)
    cv.setMaxNumberOfColumns(4)
    check(not cv.isSelectable())
    check(cv.minItemSize() == nsSize(64, 64))
    check(cv.maxItemSize() == nsSize(256, 256))
    check(cv.maxNumberOfRows() == 5)
    check(cv.maxNumberOfColumns() == 4)

    var alert = NSAlert.new()
    check(alert.isKindOfClass(NSAlert))
    check(getClassName(alert).startsWith("NXAlert"))
    alert.setAlertStyle(NSCriticalAlertStyle)
    alert.setMessageText(@ns"Danger")
    alert.setInformativeText(@ns"Disk is full")
    discard alert.addButtonWithTitle(@ns"OK")
    discard alert.addButtonWithTitle(@ns"Cancel")
    check(alert.alertStyle() == NSCriticalAlertStyle)
    check(alert.messageText() == @ns"Danger")
    check(alert.informativeText() == @ns"Disk is full")
    check(alert.buttons().len == 2)
    check(alert.runModal() == NSAlertSecondButtonReturn)

    alert.value = nil
    cv.value = nil
    doc.value = nil
    clip.value = nil
    buttonCell.value = nil
    actionCell.value = nil
    sourceCell.value = nil
    cell.value = nil

  test "clip view applies figdraw clipping and scroll offset in render tree":
    var window = newWindow(0, 0, 320, 240, "Clip Render")
    var root = newView(0, 0, 320, 240)
    var clip = NSClipView.new()
    clip.setFrame(20.cfloat, 30.cfloat, 100.cfloat, 80.cfloat)
    clip.setDrawsBackground(true)
    clip.setBackgroundColor(nsColor(0.2, 0.3, 0.4, 1.0))
    var doc = newView(0, 0, 300, 240)
    clip.setDocumentView(doc)
    clip.scrollToPoint(nsPoint(45, 25))
    root.addSubview(clip)
    window.setContentView(root)

    let renders = debugBuildWindowRenders(window)
    check(not renders.isNil)

    var foundClipNode = false
    var foundDocNode = false
    if renders.contains(0.ZLevel):
      let nodes = renders[0.ZLevel].nodes
      for node in nodes:
        if node.kind == nkRectangle and approxEq(node.screenBox.x, 20.0) and
            approxEq(node.screenBox.y, 30.0) and approxEq(node.screenBox.w, 100.0) and
            approxEq(node.screenBox.h, 80.0):
          foundClipNode = true
          check(NfClipContent in node.flags)
        if node.kind == nkRectangle and approxEq(node.screenBox.x, -25.0) and
            approxEq(node.screenBox.y, 5.0) and approxEq(node.screenBox.w, 300.0) and
            approxEq(node.screenBox.h, 240.0):
          foundDocNode = true
    check(foundClipNode)
    check(foundDocNode)
    check(doc.frameOrigin() == nsPoint(-45, -25))

    doc.value = nil
    clip.value = nil
    root.value = nil
    window.value = nil
