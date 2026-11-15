## Exercise Cocoa NSTextInputClient callbacks through the actual native window.
when defined(macosx):
  import std/[os, unittest]
  import darwin/app_kit/[nsevent, nsview, nswindow]
  import darwin/foundation/[nsgeometry, nsrange, nsstring]
  import darwin/objc/runtime
  from figdraw/windowing/siwinshim import WindowCocoa, nativeWindowHandle
  import merenda/nimkit
  import merenda/nimkit/directviews
  import ../../examples/direct_collection_demo
  import ../intrinsic_collection_fixture

  proc setNativeMarkedText(
    view: NSView, text: NSString, selected, replacement: NSRange
  ) {.objc: "setMarkedText:selectedRange:replacementRange:".}

  proc insertNativeText(
    view: NSView, text: NSString, replacement: NSRange
  ) {.objc: "insertText:replacementRange:".}

  proc nativeMarkedRange(view: NSView): NSRange {.objc: "markedRange".}
  proc nativeSelectedRange(view: NSView): NSRange {.objc: "selectedRange".}
  proc nativeCaretRect(
    view: NSView, range: NSRange, actual: NSRangePointer
  ): NSRect {.objc: "firstRectForCharacterRange:actualRange:".}

  proc nativeWindowNumber(window: NSWindow): NSInteger {.objc: "windowNumber".}
  proc makeKeyEvent(
    eventClass: typedesc[NSEvent],
    kind: NSInteger,
    point: NSPoint,
    modifiers: NSUInteger,
    timestamp: float64,
    windowNumber: NSInteger,
    context: ID,
    characters, ignoringModifiers: NSString,
    repeated: BOOL,
    keyCode: uint16,
  ): NSEvent {.
    objc:
      "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"
  .}

  proc nativeKeyDown(view: NSView, event: NSEvent) {.objc: "keyDown:".}

  suite "native virtualized row composition":
    test "Cocoa marked text survives viewport eviction and commits":
      const policies = [false, true]
      for cache in policies:
        let demo = newIntrinsicCollectionFixture(5000, cache)
        let window = newWindow("Native composition", frame = rect(0, 0, 640, 480))
        defer:
          demo.rows.close()
          window.close()
        window.setContentView(demo.view)
        window.makeKeyAndOrderFront()
        window.ensureNativeWindow()
        require window.nativeReady
        discard window.buildRenders()
        let row = DirectView(demo.view.itemViewAtIndex(0))
        require not row.isNil
        let field = TextField(StackView(row.arrangedSubviews[0]).arrangedSubviews[1])
        require window.makeFirstResponder(field)
        let editor = TextView(field.currentEditor)
        editor.selectAllText()
        let native =
          cast[NSWindow](WindowCocoa(window.nativeWindowOrNil()).nativeWindowHandle())
        let view = native.contentView()
        view.setNativeMarkedText("かな".toNSString, NSMakeRange(1, 0), NSRangeEmpty)
        require editor.hasMarkedText
        check view.nativeMarkedRange() == NSMakeRange(0, 2)
        check view.nativeSelectedRange() == NSMakeRange(1, 0)
        var actual: NSRange
        let caret = view.nativeCaretRect(NSMakeRange(1, 0), addr actual)
        check caret.size.height > 0
        let marked = editor.markedRange
        let selected = editor.selectedRange
        demo.view.scrollView.contentOffset = initPoint(0, 1600)
        discard window.buildRenders()
        check field.currentEditor == editor
        check editor.markedRange == marked
        check editor.selectedRange == selected
        view.setNativeMarkedText("漢字".toNSString, NSMakeRange(2, 0), NSRangeEmpty)
        check editor.hasMarkedText
        view.insertNativeText("漢字".toNSString, NSRangeEmpty)
        check not editor.hasMarkedText
        check editor.stringValue == "漢字"
        editor.stringValue = "A😀B"
        view.setNativeMarkedText("か".toNSString, NSMakeRange(1, 0), NSMakeRange(1, 2))
        check editor.stringValue == "AかB"
        view.setNativeMarkedText("".toNSString, NSMakeRange(0, 0), NSRangeEmpty)
        check editor.stringValue == "AB"
        check not editor.hasMarkedText

    if getEnv("MERENDA_TEST_JAPANESE_IME") == "1":
      test "Japanese input method composes into the virtualized field":
        let demo = newDirectCollectionDemo(5000)
        let window = newWindow("Japanese IME", frame = rect(0, 0, 640, 480))
        defer:
          demo.rows.close()
          window.close()
        window.setContentView(demo.view)
        window.makeKeyAndOrderFront()
        window.ensureNativeWindow()
        require window.nativeReady
        discard window.buildRenders()
        let row = DirectView(demo.view.itemViewAtIndex(0))
        require not row.isNil
        let field = TextField(StackView(row.arrangedSubviews[0]).arrangedSubviews[1])
        require window.makeFirstResponder(field)
        let editor = TextView(field.currentEditor)
        editor.selectAllText()
        let native =
          cast[NSWindow](WindowCocoa(window.nativeWindowOrNil()).nativeWindowHandle())
        let view = native.contentView()
        for key in [("k", 40'u16), ("a", 0'u16)]:
          let event = NSEvent.makeKeyEvent(
            10,
            NSMakePoint(0, 0),
            0,
            0,
            native.nativeWindowNumber(),
            nil,
            key[0].toNSString,
            key[0].toNSString,
            false,
            key[1],
          )
          require event != nil
          view.nativeKeyDown(event)
        require editor.hasMarkedText
        check editor.stringValue == "か"
        let marked = editor.markedRange
        demo.view.scrollView.contentOffset = initPoint(0, 1600)
        discard window.buildRenders()
        check field.currentEditor == editor
        check editor.markedRange == marked
