import std/[monotimes, options, os, osproc, strutils, tempfiles, times, unittest]

import figdraw
import sigils/threads

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

proc numberedLines(prefix: string, count: Natural): string =
  var lines = newSeqOfCap[string](count)
  for index in 0 ..< count:
    lines.add prefix & " row " & $index
  lines.join("\n")

proc displayedText(view: KosmoEditorView): string =
  monoTextViews.stringValue(MonoTextView(view))

proc signalSubscriptionCount(source: Agent, signal: string): int =
  for _ in source.getSubscriptions(toSigilName(signal)):
    inc result

proc hasPaneOutline(pane: KosmoEditorPane, color: Color, width: float32): bool =
  let
    renders = buildRenders(pane)[DefaultDrawLevel]
    contentSize = pane.contentView.frame().size
  for node in renders.nodes:
    if node.kind == nkRectangle and node.stroke.weight == width and
        node.stroke.fill.kind == flColor and node.stroke.fill.color == color.rgba and
        abs(node.screenBox.w - (contentSize.width - width)) <= 0.01'f32 and
        abs(node.screenBox.h - (contentSize.height - width)) <= 0.01'f32:
      return true

suite "Kosmo":
  test "dragging a document tab to an editor edge creates a split group":
    let
      root = createTempDir("merenda-kosmo-dock-split-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Dock Split Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = frontend.dockView.pointToWindow(
        initPoint(
          frontend.dockView.bounds().maxX - 4.0'f32,
          frontend.dockView.bounds().minY +
            frontend.dockView.bounds().size.height * 0.5'f32,
        )
      )
      bufferCount = frontend.editorView.editor.tabs().len

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.dockView.dropTarget().position == dpRight
    check frontend.window.mouseUpAt(drop)
    frontend.contentView.layoutSubtreeIfNeeded()

    let groups = frontend.editorGroups()
    check groups.len == 2
    check frontend.dockView.rootView() of SplitView
    check SplitView(frontend.dockView.rootView()).splitAxis == laHorizontal
    check groups[0].editorView.documentTabs.len == 1
    check groups[1].editorView.documentTabs.len == 1
    check frontend.editorView.editor.tabs().len == bufferCount
    check groups[0].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
    check not groups[1].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)

    let
      paneIndicatorContext = controlStyle(srBox, id = KosmoPaneIndicatorStyleId)
      paneAppearance = groups[1].pane.documentTabs.effectiveAppearance()
      paneOutlineColor = paneAppearance.resolveColor(
        paneIndicatorContext, StyleBorderColor, color(0.0, 0.0, 0.0, 0.0)
      )
      paneOutlineWidth =
        paneAppearance.resolveLength(paneIndicatorContext, StyleBorderWidth, 0.0'f32)
      activeTabTextColor = paneAppearance.resolveColor(
        controlStyle(srDocumentTab, {ssSelected}),
        StyleTextColor,
        color(0.0, 0.0, 0.0, 1.0),
      )
      inactiveTabTextColor = paneAppearance.resolveColor(
        controlStyle(
          srDocumentTab, {ssSelected}, classes = @[KosmoInactivePaneStyleClass]
        ),
        StyleTextColor,
        color(0.0, 0.0, 0.0, 1.0),
      )
    check inactiveTabTextColor.a < activeTabTextColor.a
    check not groups[0].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)
    check groups[1].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)

    let sourceGroupPoint =
      groups[0].editorView.pointToWindow(initPoint(12.0'f32, 12.0'f32))
    check frontend.window.mouseDownAt(sourceGroupPoint)
    check frontend.window.mouseUpAt(sourceGroupPoint)
    check not groups[0].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
    check groups[1].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
    check groups[0].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)
    check not groups[1].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)

    check groups[1].editorView.documentTabs.closeDocumentTabAtIndex(0)
    check frontend.editorGroups().len == 1
    check frontend.dockView.len == 1
    check frontend.dockView.rootView() == groups[0].panel
    check not (frontend.dockView.rootView() of SplitView)

  test "mouse pane splits preserve unrelated pane width":
    let
      root = createTempDir("merenda-kosmo-dock-split-sizing-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
      thirdPath = root / "third.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    writeFile(thirdPath, "third")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeFile(thirdPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Dock Split Sizing Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)
    check frontend.openPath(thirdPath)

    let
      sourceTabs = frontend.documentTabs
      sourceTabRect = sourceTabs.documentTabRect(0)
      sourceStart = sourceTabs.pointToWindow(
        initPoint(
          sourceTabRect.minX + sourceTabRect.size.width * 0.5'f32,
          sourceTabRect.minY + sourceTabRect.size.height * 0.5'f32,
        )
      )
      firstDrop = frontend.dockView.pointToWindow(
        initPoint(
          frontend.dockView.bounds().maxX - 4.0'f32,
          frontend.dockView.bounds().minY +
            frontend.dockView.bounds().size.height * 0.5'f32,
        )
      )

    check frontend.window.mouseDownAt(sourceStart)
    check frontend.window.mouseDraggedAt(firstDrop)
    check frontend.window.mouseUpAt(firstDrop)
    frontend.contentView.layoutSubtreeIfNeeded()

    var groups = frontend.editorGroups()
    require groups.len == 2
    let unrelatedWidth = groups[0].panel.frame().size.width
    let
      movingTabs = groups[0].editorView.documentTabs
      movingTabRect = movingTabs.documentTabRect(0)
      movingStart = movingTabs.pointToWindow(
        initPoint(
          movingTabRect.minX + movingTabRect.size.width * 0.5'f32,
          movingTabRect.minY + movingTabRect.size.height * 0.5'f32,
        )
      )
      targetPanelBounds = groups[1].panel.bounds()
      secondDrop = groups[1].panel.pointToWindow(
        initPoint(
          targetPanelBounds.maxX - 4.0'f32,
          targetPanelBounds.minY + targetPanelBounds.size.height * 0.5'f32,
        )
      )

    check frontend.window.mouseDownAt(movingStart)
    check frontend.window.mouseDraggedAt(secondDrop)
    check frontend.dockView.dropTarget().position == dpRight
    check frontend.window.mouseUpAt(secondDrop)
    frontend.contentView.layoutSubtreeIfNeeded()

    groups = frontend.editorGroups()
    require groups.len == 3
    check abs(groups[0].panel.frame().size.width - unrelatedWidth) <= 0.01'f32
    check abs(groups[1].panel.frame().size.width - groups[2].panel.frame().size.width) <=
      0.01'f32

  test "keyboard pane splits preserve unrelated pane width":
    let frontend =
      newKosmoApplication(newApplication("Kosmo Keyboard Split Sizing Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: {})
    )
    frontend.contentView.layoutSubtreeIfNeeded()

    var groups = frontend.editorGroups()
    require groups.len == 2
    let unrelatedWidth = groups[0].panel.frame().size.width

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: {})
    )
    frontend.contentView.layoutSubtreeIfNeeded()

    groups = frontend.editorGroups()
    require groups.len == 3
    check abs(groups[0].panel.frame().size.width - unrelatedWidth) <= 0.01'f32
    check abs(groups[1].panel.frame().size.width - groups[2].panel.frame().size.width) <=
      0.01'f32

  when defined(posix):
    test "terminal shortcut opens a tab that can create an independent split pane":
      let frontend = newKosmoApplication(newApplication("Kosmo Terminal Split Test"))
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      check frontend.window.makeFirstResponder(frontend.editorView)
      let initialFocusObservers =
        frontend.window.signalSubscriptionCount("didChangeFirstResponder")
      check frontend.window.dispatchKeyDown(
        KeyEvent(
          key: keyT,
          keyCode: keyT.ord,
          modifiers: shortcutModifiers() + {nimkit.kmShift},
        )
      )

      let
        terminalView = TerminalView(frontend.editorPane.contentView)
        sourceTabs = frontend.documentTabs
        tabRect = sourceTabs.documentTabRect(sourceTabs.selectedIndex())
        start = sourceTabs.pointToWindow(
          initPoint(
            tabRect.minX + tabRect.size.width * 0.5'f32,
            tabRect.minY + tabRect.size.height * 0.5'f32,
          )
        )
        drop = frontend.dockView.pointToWindow(
          initPoint(
            frontend.dockView.bounds().maxX - 4.0'f32,
            frontend.dockView.bounds().minY +
              frontend.dockView.bounds().size.height * 0.5'f32,
          )
        )

      check frontend.window.mouseDownAt(start)
      check frontend.window.mouseDraggedAt(drop)
      check frontend.window.mouseUpAt(drop)

      let groups = frontend.editorGroups()
      check groups.len == 2
      check frontend.window.signalSubscriptionCount("didChangeFirstResponder") ==
        initialFocusObservers + 1
      check groups[0].documents.len == 0
      check groups[1].documents.len == 1
      check groups[1].pane.contentView == View(terminalView)
      check groups[1].pane.documentTabs.len == 1
      check terminalView.session().running()

      frontend.contentView.layoutSubtreeIfNeeded()
      let
        paneIndicatorContext = controlStyle(srBox, id = KosmoPaneIndicatorStyleId)
        paneAppearance = groups[1].pane.documentTabs.effectiveAppearance()
        paneOutlineColor = paneAppearance.resolveColor(
          paneIndicatorContext, StyleBorderColor, color(0.0, 0.0, 0.0, 0.0)
        )
        paneOutlineWidth =
          paneAppearance.resolveLength(paneIndicatorContext, StyleBorderWidth, 0.0'f32)
        editorPoint = groups[0].editorView.pointToWindow(initPoint(12.0'f32, 12.0'f32))
      check frontend.window.mouseDownAt(editorPoint)
      check frontend.window.mouseUpAt(editorPoint)
      check not groups[0].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
      check groups[1].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
      check groups[0].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)
      check not groups[1].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)

      let terminalPoint = terminalView.pointToWindow(initPoint(12.0'f32, 12.0'f32))
      check frontend.window.mouseDownAt(terminalPoint)
      check frontend.window.mouseUpAt(terminalPoint)
      check groups[0].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
      check not groups[1].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
      check not groups[0].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)
      check groups[1].pane.hasPaneOutline(paneOutlineColor, paneOutlineWidth)
      check groups[1].pane.documentTabs.selectedDocumentTabIdentifier.startsWith(
        "kosmo.terminal."
      )

      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      )
      check frontend.editorGroups().len == 2
      check frontend.window.sendAction(
        actionSelector(KosmoSplitVerticalAction), DynamicAgent(terminalView)
      )

      let splitGroups = frontend.editorGroups()
      require splitGroups.len == 3
      let
        duplicatedGroup = splitGroups[^1]
        duplicatedTerminal = TerminalView(duplicatedGroup.pane.contentView)
      check frontend.window.signalSubscriptionCount("didChangeFirstResponder") ==
        initialFocusObservers + 2
      check groups[1].documents.len == 1
      check duplicatedGroup.documents.len == 1
      check duplicatedGroup.documents[0].identifier != groups[1].documents[0].identifier
      check duplicatedTerminal != terminalView
      check terminalView.session().running()
      check duplicatedTerminal.session().running()

      check duplicatedGroup.pane.documentTabs.closeDocumentTabAtIndex(0)
      check frontend.editorGroups().len == 2
      check duplicatedTerminal.session().state() == tssClosed
      check frontend.window.signalSubscriptionCount("didChangeFirstResponder") ==
        initialFocusObservers + 1

      check groups[1].pane.documentTabs.closeDocumentTabAtIndex(0)
      check frontend.editorGroups().len == 1
      check frontend.dockView.len == 1
      check terminalView.session().state() == tssClosed
      check frontend.window.signalSubscriptionCount("didChangeFirstResponder") ==
        initialFocusObservers

  test "q and x commands close the active tab and its empty split":
    let
      root = createTempDir("merenda-kosmo-command-close-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Command Close Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = frontend.dockView.pointToWindow(
        initPoint(
          frontend.dockView.bounds().maxX - 4.0'f32,
          frontend.dockView.bounds().minY +
            frontend.dockView.bounds().size.height * 0.5'f32,
        )
      )

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.window.mouseUpAt(drop)
    frontend.contentView.layoutSubtreeIfNeeded()

    let groups = frontend.editorGroups()
    check groups.len == 2
    let commandGroupPoint = groups[1].editorView.pointToWindow(initPoint(12, 12))
    check frontend.window.mouseDownAt(commandGroupPoint)
    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("q")
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )

    check frontend.editorGroups().len == 1
    check frontend.dockView.len == 1
    check not (frontend.dockView.rootView() of SplitView)
    check frontend.editorView.editor.tabs().len == 1
    check frontend.editorView.editor.tabs()[0].title == "second.txt"

    check frontend.openPath(firstPath)
    check frontend.editorView.editor.tabs().len == 2
    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("x")
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )

    check frontend.editorGroups().len == 1
    check frontend.editorView.editor.tabs().len == 1
    check frontend.editorView.editor.tabs()[0].title == "second.txt"

  test "q closes the Moe config panel without closing its Kosmo tab":
    let
      root = createTempDir("merenda-kosmo-config-close-", "")
      filePath = root / "config-test.txt"
    writeFile(filePath, "config panel host")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Config Close Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)
    check frontend.window.makeFirstResponder(frontend.editorView)
    let tabIdentifier = frontend.documentTabs.selectedDocumentTabIdentifier
    check frontend.documentTabs.len == 1

    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("config")
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )
    check frontend.editorView.editor.mode() == KosmoEditorMode.Other
    check frontend.documentTabs.len == 1

    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("q")
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )

    check frontend.editorView.editor.mode() == KosmoEditorMode.Normal
    check frontend.documentTabs.len == 1
    check frontend.documentTabs.selectedDocumentTabIdentifier == tabIdentifier

  test "duplicated buffer panes keep independent selections during repeated refreshes":
    let pasteboard = generalPasteboard()
    var savedClipboard: seq[tuple[kind: string, item: PasteboardItem]]
    for kind in pasteboard.types():
      savedClipboard.add (kind, pasteboard.itemForType(kind))
    defer:
      pasteboard.clearContents()
      for (kind, item) in savedClipboard:
        discard pasteboard.setItem(kind, item)
    let frontend = newKosmoApplication(newApplication("Kosmo Split Selection Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let editor = frontend.editorView.editor
    require editor.handleKey("i")
    require editor.handleTextInput("alpha beta gamma\nsecond line text\nthird line")
    require editor.handleKey("Esc")
    frontend.editorView.refresh()
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    require frontend.window.dispatchKeyDown(KeyEvent(key: keyV, keyCode: keyV.ord))
    frontend.contentView.layoutSubtreeIfNeeded()
    let groups = frontend.editorGroups()
    require groups.len == 2
    check groups[0].pane.documentTabs.selectedDocumentTabIdentifier ==
      groups[1].pane.documentTabs.selectedDocumentTabIdentifier

    groups[0].editorView.refresh()
    require editor.revealLocation(0, 1)
    require editor.handleKey("v")
    require editor.handleKey("l")
    groups[0].editorView.refresh()
    let
      firstSelection = editor.currentSelection()
      firstCursor = editor.bufferCursor()
      firstText = editor.selectedText()
    require firstSelection.isSome

    groups[1].editorView.refresh()
    check editor.currentSelection().isNone
    check editor.bufferCursor() != firstCursor
    require editor.revealLocation(1, 2)
    require editor.handleKey("v")
    require editor.handleKey("l")
    groups[1].editorView.refresh()
    let
      secondSelection = editor.currentSelection()
      secondCursor = editor.bufferCursor()
      secondText = editor.selectedText()
    require secondSelection.isSome

    for _ in 0 .. 4:
      groups[0].editorView.refresh()
      check editor.currentSelection() == firstSelection
      check editor.bufferCursor() == firstCursor
      check editor.selectedText() == firstText
      groups[1].editorView.refresh()
      check editor.currentSelection() == secondSelection
      check editor.bufferCursor() == secondCursor
      check editor.selectedText() == secondText

    require groups[0].editorView.tryToPerform(actionSelector(KosmoCopyAction))
    check generalPasteboard().plainText() == firstText

    groups[0].editorView.refresh()
    require editor.handleKey("Esc")
    require editor.revealLocation(0, 1)
    groups[0].editorView.refresh()
    let
      startCursor = editor.cursor()
      metrics = groups[0].editorView.monoTextMetrics()
      startPoint = groups[0].editorView.pointToWindow(
        initPoint(
          (startCursor.column.float32 + 0.5'f32) * metrics.cellWidth,
          (startCursor.row.float32 + 0.5'f32) * metrics.lineHeight,
        )
      )
    require editor.revealLocation(1, 4)
    groups[0].editorView.refresh()
    let
      finishCursor = editor.cursor()
      finishPoint = groups[0].editorView.pointToWindow(
        initPoint(
          (finishCursor.column.float32 + 0.5'f32) * metrics.cellWidth,
          (finishCursor.row.float32 + 0.5'f32) * metrics.lineHeight,
        )
      )
    require frontend.window.mouseDownAt(startPoint)
    groups[1].editorView.refresh()
    require frontend.window.mouseDraggedAt(finishPoint)
    groups[1].editorView.refresh()
    require frontend.window.mouseUpAt(finishPoint)
    groups[0].editorView.refresh()
    let draggedSelection = editor.currentSelection()
    require draggedSelection.isSome
    check draggedSelection.get.anchor == KosmoBufferCursor(line: 0, column: 1)
    check draggedSelection.get.focus == KosmoBufferCursor(line: 1, column: 4)
    groups[1].editorView.refresh()
    check editor.currentSelection() == secondSelection

  test "split editor groups keep independent cursor scroll and motion state":
    let
      root = createTempDir("merenda-kosmo-split-state-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, numberedLines("first", 80))
    writeFile(secondPath, numberedLines("second", 80))
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Split State Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = frontend.dockView.pointToWindow(
        initPoint(
          frontend.dockView.bounds().maxX - 4.0'f32,
          frontend.dockView.bounds().minY +
            frontend.dockView.bounds().size.height * 0.5'f32,
        )
      )

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.window.mouseUpAt(drop)
    frontend.contentView.layoutSubtreeIfNeeded()

    let groups = frontend.editorGroups()
    check groups.len == 2
    check groups[0].editorView.documentTabs.documentTabModels()[0].title == "second.txt"
    check groups[1].editorView.documentTabs.documentTabModels()[0].title == "first.txt"

    groups[0].editorView.refresh()
    check groups[0].editorView.keyDown(
      KeyEvent(text: "j", key: keyJ, keyCode: keyJ.ord)
    )
    let firstCursor = frontend.editorView.editor.cursor()
    groups[1].editorView.refresh()
    check groups[1].editorView.keyDown(
      KeyEvent(text: "j", key: keyJ, keyCode: keyJ.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: "j", key: keyJ, keyCode: keyJ.ord)
    )
    groups[0].editorView.refresh()
    check frontend.editorView.editor.cursor() == firstCursor

    let scroll = groups[0].editorView.scrollBy(-8.0'f32, row = 2, column = 2)
    check scroll.appliedRows == 8
    let firstScrolledGrid = groups[0].editorView.displayedText()
    check "second row 8" in firstScrolledGrid

    groups[1].editorView.refresh()
    groups[0].editorView.refresh()
    check groups[0].editorView.displayedText() == firstScrolledGrid

    let secondScroll = groups[1].editorView.scrollBy(-3.0'f32, row = 2, column = 2)
    check secondScroll.appliedRows == 3
    let secondScrolledGrid = groups[1].editorView.displayedText()
    check "first row 3" in secondScrolledGrid

    groups[0].editorView.refresh()
    check groups[0].editorView.displayedText() == firstScrolledGrid
    groups[1].editorView.refresh()
    check groups[1].editorView.displayedText() == secondScrolledGrid

    let secondFocusPoint = groups[1].editorView.pointToWindow(initPoint(12, 12))
    check frontend.window.mouseDownAt(secondFocusPoint)
    check "first.txt" in frontend.statusLabel.text
    groups[0].editorView.refresh()
    check "first.txt" in frontend.statusLabel.text
    let firstFocusPoint = groups[0].editorView.pointToWindow(initPoint(12, 12))
    check frontend.window.mouseDownAt(firstFocusPoint)
    check "second.txt" in frontend.statusLabel.text
    groups[1].editorView.refresh()
    check "second.txt" in frontend.statusLabel.text

    let inactiveGridBeforeCommand = groups[1].editorView.displayedText()
    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("set")
    check not groups[0].pane.commandBar.hidden()
    check groups[1].pane.commandBar.hidden()
    check frontend.window.mouseDownAt(secondFocusPoint)
    check groups[0].pane.commandBar.hidden()
    check groups[1].pane.commandBar.hidden()
    check not frontend.editorView.editor.commandLine().visible
    check groups[1].editorView.displayedText() == inactiveGridBeforeCommand

    groups[0].editorView.refresh()
    let firstCursorBeforePageMotion = frontend.editorView.editor.cursor()
    groups[1].editorView.refresh()
    check groups[1].editorView.keyDown(
      KeyEvent(text: "f", key: keyF, keyCode: keyF.ord, modifiers: {kmControl})
    )
    groups[0].editorView.refresh()
    check frontend.editorView.editor.cursor() == firstCursorBeforePageMotion

    groups[1].editorView.refresh()
    check groups[1].editorView.keyDown(
      KeyEvent(text: "b", key: keyB, keyCode: keyB.ord, modifiers: {kmControl})
    )
    groups[0].editorView.refresh()
    check frontend.editorView.editor.cursor() == firstCursorBeforePageMotion

    let inactiveGridBeforeCompletion = groups[0].editorView.displayedText()
    let
      metrics = groups[1].editorView.monoTextMetrics()
      focusPoint = groups[1].editorView.pointToWindow(
        initPoint(metrics.cellWidth * 12.0'f32, metrics.lineHeight * 2.0'f32)
      )
    check frontend.window.mouseDownAt(focusPoint)
    check groups[1].editorView.keyDown(
      KeyEvent(text: "a", key: keyA, keyCode: keyA.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: " ", key: keySpace, keyCode: keySpace.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: "f", key: keyF, keyCode: keyF.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: "p", key: keyP, keyCode: keyP.ord, modifiers: {kmControl})
    )
    check frontend.editorView.editor.completionPopupVisible()
    let popupMenu = groups[1].editorView.editor.popupMenu()
    check popupMenu.isSome
    if popupMenu.isSome:
      check popupMenu.get.kind == KosmoPopupMenuKind.Completion
      check popupMenu.get.items.len > 0
    var popupListVisible = false
    for subview in groups[1].pane.subviews():
      if subview of PopupListView:
        let popupList = PopupListView(subview)
        popupListVisible = not popupList.hidden() and popupList.itemCount() > 0
        break
    check popupListVisible
    groups[0].editorView.refresh()
    check groups[0].editorView.displayedText() == inactiveGridBeforeCompletion

  test "dragging a document tab outside every workspace creates a window":
    let
      root = createTempDir("merenda-kosmo-dock-window-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Dock Window Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = initPoint(
        frontend.window.frame().size.width + 180.0'f32,
        frontend.window.frame().size.height + 180.0'f32,
      )

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.window.mouseUpAt(drop)
    check frontend.editorGroups().len == 2
    check frontend.detachedEditorWindows().len == 1
    let detachedWindow = frontend.detachedEditorWindows()[0]
    check detachedWindow.contentView() != nil
    check frontend.editorView.editor.tabs().len == 2

  test "native tab bar sits above the editor grid":
    let frontend = newKosmoApplication(newApplication("Kosmo Tabs Layout Test"))
    defer:
      frontend.close()
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()

    check frontend.documentTabs.frame().origin.y == 0.0'f32
    check frontend.documentTabs.frame().size.height == KosmoTabBarHeight
    check frontend.editorView.frame().origin.y == KosmoTabBarHeight
    check frontend.editorView.frame().size.height ==
      frontend.editorPane.bounds().size.height - KosmoTabBarHeight

    let editorStyle = frontend.editorView.effectiveAppearance.resolveMonoTextStyle(
      controlStyle(srMonoTextView, id = frontend.editorView.styleId)
    )
    check editorStyle.cursorColor.a == 0.45'f32
    check editorStyle.box.focusRingWidth == 0.0'f32
    check editorStyle.box.focusRingInset == 0.0'f32
    check editorStyle.box.cornerRadius == 0.0'f32
    check editorStyle.box.cornerRadii.isZero

  test "settled editor refresh does not re-dirty its containing layout":
    let frontend = newKosmoApplication(newApplication("Kosmo Layout Test"))
    defer:
      frontend.close()

    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.contentView.layoutSubtreeIfNeeded()

    check not frontend.contentView.needsLayout()
    check not frontend.contentView.contentView().needsLayout()
