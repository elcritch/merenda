import std/[monotimes, options, os, strutils, tempfiles, times, unicode, unittest]

import figdraw
import sigils/threads

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo
import fixtures/ui
import ../nimkit/fixtures/rendergeometry

proc renderedFigText(node: Fig): string =
  for glyphIndex in 0 ..< node.textLayout.glyphCount():
    result.add node.textLayout.displayRune(glyphIndex).toUTF8()

proc renderedTexts(view: View): seq[string] =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText:
      result.add node.renderedFigText()

proc hasSidebarPaneOutline(
    view: View, outlineColor: Color, outlineWidth: float32
): bool =
  let renders = buildRenders(view)[DefaultDrawLevel]
  for node in renders.nodes:
    if node.kind == nkRectangle and node.stroke.weight == outlineWidth and
        node.stroke.fill.kind == flColor and node.stroke.fill.color == outlineColor.rgba:
      return true

suite "Kosmo":
  test "sidebar focus highlights file and search panes with the pane accent outline":
    let frontend = newKosmoApplication(newApplication("Kosmo Sidebar Focus Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 760, 520)
    frontend.contentView.layoutSubtreeIfNeeded()

    let
      paneIndicatorContext = controlStyle(srBox, id = KosmoPaneIndicatorStyleId)
      paneAppearance = frontend.editorView.effectiveAppearance()
      paneOutlineColor = paneAppearance.resolveColor(
        paneIndicatorContext, StyleBorderColor, color(0.0, 0.0, 0.0, 0.0)
      )
      paneOutlineWidth =
        paneAppearance.resolveLength(paneIndicatorContext, StyleBorderWidth, 0.0'f32)
      sidebarAppearance = frontend.sidebarTabs.effectiveAppearance()
      activeSidebarTabTextColor = sidebarAppearance.resolveColor(
        controlStyle(srTab, {ssSelected, ssFocused}),
        StyleTextColor,
        color(0.0, 0.0, 0.0, 1.0),
      )
      inactiveSidebarTabTextColor = sidebarAppearance.resolveColor(
        controlStyle(srTab, {ssSelected}), StyleTextColor, color(0.0, 0.0, 0.0, 1.0)
      )
      cancelButtonStyle = frontend.searchPanel.cancelButton
        .effectiveAppearance()
        .resolveButtonStyle(controlStyle(srButton, id = KosmoCancelSearchButtonStyleId))
    check paneOutlineColor.a > 0.0'f32
    check paneOutlineColor.a < 1.0'f32
    check paneOutlineWidth > 0.0'f32
    check inactiveSidebarTabTextColor.a < activeSidebarTabTextColor.a
    check frontend.searchPanel.cancelButton.title == "X"
    check frontend.searchPanel.cancelButton.styleId == KosmoCancelSearchButtonStyleId
    check cancelButtonStyle.chrome == DefaultChromeName
    check cancelButtonStyle.box.fill.centerColor().r < cancelButtonStyle.text.color.r
    check cancelButtonStyle.box.fill.centerColor().g < cancelButtonStyle.text.color.g
    check cancelButtonStyle.box.fill.centerColor().b < cancelButtonStyle.text.color.b

    check frontend.window.makeFirstResponder(frontend.editorView)
    check not frontend.sidebarTabs.focused
    frontend.fileTree.selectedItemIdentifier = frontend.fileTree.rootPath
    check not frontend.fileTree.showsFocusedRowHighlight
    check not frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check not frontend.sidebarPane.hasSidebarPaneOutline(
      paneOutlineColor, paneOutlineWidth
    )

    check frontend.showFileExplorer()
    check frontend.sidebarTabs.focused
    check frontend.window.firstResponder == frontend.fileTree
    check frontend.fileTree.showsFocusedRowHighlight
    check frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check frontend.sidebarPane.hasSidebarPaneOutline(paneOutlineColor, paneOutlineWidth)

    check frontend.window.makeFirstResponder(frontend.editorView)
    check not frontend.sidebarTabs.focused
    check not frontend.fileTree.showsFocusedRowHighlight
    check not frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check not frontend.sidebarPane.hasSidebarPaneOutline(
      paneOutlineColor, paneOutlineWidth
    )

    check frontend.showFindInFiles()
    check frontend.sidebarTabs.focused
    check frontend.window.firstResponder == frontend.window.fieldEditor()
    check frontend.window.fieldEditorClient() == frontend.searchPanel.queryField
    check frontend.fileTree.showsFocusedRowHighlight
    check frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check frontend.sidebarPane.hasSidebarPaneOutline(paneOutlineColor, paneOutlineWidth)

    check frontend.window.makeFirstResponder(frontend.searchPanel.resultsView)
    check frontend.sidebarPane.hasSidebarPaneOutline(paneOutlineColor, paneOutlineWidth)
    check frontend.window.makeFirstResponder(frontend.editorView)
    check not frontend.sidebarPane.hasSidebarPaneOutline(
      paneOutlineColor, paneOutlineWidth
    )

  test "sidebar shortcuts focus the explorer and open clicked search results":
    let
      root = createTempDir("merenda-kosmo-find-sidebar-", "")
      alphaPath = root / "alpha.txt"
      betaPath = root / "beta.nim"
      frontend =
        newKosmoApplication(newApplication("Kosmo Find Sidebar Test"), filePath = root)
    var alphaContents = ""
    for line in 1 .. 80:
      if line == 41:
        alphaContents.add "second λ needle\n"
      else:
        alphaContents.add "alpha line " & $line & "\n"
    writeFile(alphaPath, alphaContents)
    writeFile(betaPath, "let needleValue = 1\n")
    defer:
      frontend.close()
      removeFile(alphaPath)
      removeFile(betaPath)
      removeDir(root)

    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 760, 520)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(root)
    check frontend.sidebarTabs.selectedIndex == 0
    check not frontend.fileTree.isHiddenOrHasHiddenAncestor()
    check frontend.searchPanel.hidden
    let findTabPoint = frontend.statusLabel.pointToWindow(
      initPoint(47.0'f32, KosmoStatusBarHeight * 0.5'f32)
    )
    check frontend.window.mouseDownAt(findTabPoint)
    check frontend.window.mouseUpAt(findTabPoint)
    check frontend.sidebarTabs.selectedIndex == 1
    let filesTabPoint = frontend.statusLabel.pointToWindow(
      initPoint(17.0'f32, KosmoStatusBarHeight * 0.5'f32)
    )
    check frontend.window.mouseDownAt(filesTabPoint)
    check frontend.window.mouseUpAt(filesTabPoint)
    check frontend.sidebarTabs.selectedIndex == 0
    check frontend.window.makeFirstResponder(frontend.editorView)
    let sidebarShortcutModifiers =
      frontend.shortcutProfile().primaryModifiers() + {nimkit.kmShift}

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: sidebarShortcutModifiers)
    )
    check frontend.sidebarTabs.selectedIndex == 1
    check frontend.fileTree.isHiddenOrHasHiddenAncestor()
    check not frontend.searchPanel.hidden
    check frontend.searchPanel.queryField.isEditing
    check frontend.window.firstResponder == frontend.window.fieldEditor()

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: sidebarShortcutModifiers)
    )
    check frontend.sidebarTabs.selectedIndex == 0
    check not frontend.fileTree.isHiddenOrHasHiddenAncestor()
    check frontend.searchPanel.hidden
    check frontend.window.firstResponder == frontend.fileTree

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: sidebarShortcutModifiers)
    )
    check frontend.sidebarTabs.selectedIndex == 1
    check frontend.searchPanel.queryField.isEditing

    check frontend.window.dispatchTextInput("needle")
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    check not frontend.searchPanel.progressIndicator.hidden
    check frontend.searchPanel.progressIndicator.animating
    check not frontend.searchPanel.cancelButton.hidden
    check frontend.searchPanel.waitForSearch(timeoutMilliseconds = 10_000)
    check frontend.searchPanel.progressIndicator.hidden
    check not frontend.searchPanel.progressIndicator.animating
    check frontend.searchPanel.cancelButton.hidden
    check frontend.searchPanel.resultsView.matches.len == 2
    check frontend.searchPanel.resultsView.rowCount == 4
    check frontend.searchPanel.statusLabel.text == "2 results"

    let
      firstResultIdentifier = frontend.searchPanel.resultsView.matchIdentifier(0)
      firstFileIdentifier =
        frontend.searchPanel.resultsView.parentIdentifierForItem(firstResultIdentifier)
      firstFileItem =
        frontend.searchPanel.resultsView.outlineItemWithIdentifier(firstFileIdentifier)
    check firstFileIdentifier.len > 0
    check firstFileItem.title == "alpha.txt"
    check firstFileItem.decoration.badge == "1"
    check frontend.searchPanel.resultsView.isItemExpanded(firstFileIdentifier)

    frontend.contentView.layoutSubtreeIfNeeded()
    discard frontend.window.buildRenders()
    let
      resultRow = frontend.searchPanel.resultsView.rowForItem(firstResultIdentifier)
      resultRect = frontend.searchPanel.resultsView.rowItemRect(resultRow)
      resultPoint = frontend.searchPanel.resultsView.pointToWindow(
        initPoint(
          resultRect.origin.x + resultRect.size.width * 0.5'f32,
          resultRect.origin.y + resultRect.size.height * 0.5'f32,
        )
      )
    check frontend.window.mouseDownAt(resultPoint)
    check frontend.window.mouseUpAt(resultPoint)
    let tabs = frontend.editorView.editor.tabs()
    check tabs.len == 1
    check tabs[0].title == "alpha.txt"
    check tabs[0].temporary
    check frontend.editorView.editor.bufferCursor() ==
      KosmoBufferCursor(line: 40, column: 9)
    check abs(
      frontend.editorView.editor.cursor().row - frontend.editorView.lineCount div 2
    ) <= 1
    check frontend.window.mouseDownAt(resultPoint, clickCount = 2)
    check frontend.window.mouseUpAt(resultPoint, clickCount = 2)
    check not frontend.editorView.editor.tabs()[0].temporary

  test "find sidebar cancel button stops an active search":
    let
      root = createTempDir("merenda-kosmo-find-cancel-", "")
      path = root / "search.txt"
      panel = newKosmoFileSearchPanel(root)
      window = newWindow("Kosmo Find Cancel Test", rect(0, 0, 280, 320))
    writeFile(path, "needle\n")
    defer:
      panel.close()
      window.close()
      removeFile(path)
      removeDir(root)

    window.setContentView(panel)
    panel.frame = window.contentView().bounds()
    panel.layoutSubtreeIfNeeded()
    check window.makeFirstResponder(panel.queryField)
    check window.dispatchTextInput("needle")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    let handle = panel.activeSearch()
    check not handle.isNil
    check not panel.progressIndicator.hidden
    check panel.progressIndicator.animating
    check not panel.cancelButton.hidden

    panel.layoutSubtreeIfNeeded()
    let cancelPoint = panel.cancelButton.pointToWindow(
      initPoint(
        panel.cancelButton.bounds().size.width * 0.5'f32,
        panel.cancelButton.bounds().size.height * 0.5'f32,
      )
    )
    check window.mouseDownAt(cancelPoint)
    check window.mouseUpAt(cancelPoint)
    check handle.cancelRequested
    check not panel.cancelButton.enabled
    check panel.statusLabel.text == "Cancelling…"
    check panel.waitForSearch(timeoutMilliseconds = 10_000)
    check panel.statusLabel.text == "Search cancelled"
    check panel.progressIndicator.hidden
    check not panel.progressIndicator.animating
    check panel.cancelButton.hidden

  test "find sidebar streams results while recursive search remains active":
    let
      root = createTempDir("merenda-kosmo-find-stream-", "")
      nested = root / "nested"
      latePath = nested / "late.txt"
      panel = newKosmoFileSearchPanel(root)
      window = newWindow("Kosmo Find Stream Test", rect(0, 0, 320, 420))
    createDir(nested)
    writeFile(root / "first.txt", "needle\n" & repeat('x', 8 * 1024 * 1024))
    defer:
      panel.close()
      window.close()
      removeDir(root)

    window.setContentView(panel)
    panel.frame = window.contentView().bounds()
    panel.layoutSubtreeIfNeeded()
    check window.makeFirstResponder(panel.queryField)
    check window.dispatchTextInput("needle")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    let handle = panel.activeSearch()

    let deadline = getMonoTime() + initDuration(seconds = 10)
    while panel.resultsView.matches.len == 0 and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      if panel.resultsView.matches.len == 0:
        sleep(1)

    let
      streamedMatchCount = panel.resultsView.matches.len
      streamedRowCount = panel.resultsView.rowCount
      searchWasFinished = handle.isFinished()
      streamedStatus = panel.statusLabel.text
    writeFile(latePath, "late needle\n")

    check streamedMatchCount == 1
    check streamedRowCount == 2
    check not searchWasFinished
    check streamedStatus == "1 result…"
    check panel.waitForSearch(timeoutMilliseconds = 10_000)
    check panel.resultsView.matches.len == 2
    check panel.resultsView.matches[1].path == latePath

  test "find sidebar materializes all visible rows after streamed results grow":
    let
      root = createTempDir("merenda-kosmo-find-stream-render-", "")
      nested = root / "nested"
      panel = newKosmoFileSearchPanel(root)
      window = newWindow("Kosmo Find Stream Render Test", rect(0, 0, 320, 420))
    createDir(nested)
    writeFile(root / "00-initial.txt", "needle\n" & repeat('x', 8 * 1024 * 1024))
    defer:
      panel.close()
      window.close()
      removeDir(root)

    window.setContentView(panel)
    panel.frame = window.contentView().bounds()
    panel.layoutSubtreeIfNeeded()
    check window.makeFirstResponder(panel.queryField)
    check window.dispatchTextInput("needle")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    let handle = panel.activeSearch()

    let deadline = getMonoTime() + initDuration(seconds = 10)
    while panel.resultsView.matches.len == 0 and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      if panel.resultsView.matches.len == 0:
        sleep(1)

    check panel.resultsView.matches.len == 1
    check not handle.isFinished()
    check window.contentView().renderedTexts().contains("00-initial.txt")

    for index in 0 ..< 24:
      writeFile(nested / ("late-" & align($index, 2, '0') & ".txt"), "needle\n")

    check panel.waitForSearch(timeoutMilliseconds = 10_000)
    check panel.resultsView.matches.len == 25
    check not panel.resultsView.needsLayout()

    let
      visibleRows = panel.resultsView.visibleRowSummaries()
      texts = window.contentView().renderedTexts()
    check visibleRows.len > 12
    for row in visibleRows:
      check texts.contains(row.text)

  test "find results group by file and reveal more matches in fixed-size pages":
    let
      root = createTempDir("merenda-kosmo-find-groups-", "")
      path = root / "many.txt"
      panel = newKosmoFileSearchPanel(root)
      window = newWindow("Kosmo Find Groups Test", rect(0, 0, 320, 420))
    var contents = ""
    for line in 1 .. 65:
      contents.add "needle " & $line & "\n"
    writeFile(path, contents)
    defer:
      panel.close()
      window.close()
      removeFile(path)
      removeDir(root)

    var
      openedLine = 0
      openDisposition = fodPermanent
    panel.onOpenResult = proc(
        match: FileSearchMatch, disposition: FileTreeOpenDisposition
    ) =
      openedLine = match.line
      openDisposition = disposition
    window.setContentView(panel)
    panel.frame = window.contentView().bounds()
    panel.layoutSubtreeIfNeeded()
    check window.makeFirstResponder(panel.queryField)
    check window.dispatchTextInput("needle")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check panel.waitForSearch(timeoutMilliseconds = 10_000)

    let
      results = panel.resultsView
      firstResultIdentifier = results.matchIdentifier(0)
      fileIdentifier = results.parentIdentifierForItem(firstResultIdentifier)
      fileItem = results.outlineItemWithIdentifier(fileIdentifier)
    check results.matches.len == 65
    check results.rowCount == 32
    check fileItem.title == "many.txt"
    check fileItem.decoration.badge == "65"
    check results.isItemExpanded(fileIdentifier)

    proc clickSearchRow(identifier: string): bool =
      if not results.selectItemWithIdentifier(identifier):
        return false
      discard window.buildRenders()
      let
        row = results.rowForItem(identifier)
        rowRect = results.rowItemRect(row)
        point = results.pointToWindow(
          initPoint(
            rowRect.origin.x + rowRect.size.width * 0.5'f32,
            rowRect.origin.y + rowRect.size.height * 0.5'f32,
          )
        )
      window.mouseDownAt(point, clickCount = 1) and
        window.mouseUpAt(point, clickCount = 1)

    check clickSearchRow(fileIdentifier)
    check results.rowCount == 1
    check not results.isItemExpanded(fileIdentifier)
    check clickSearchRow(fileIdentifier)
    check results.rowCount == 32

    var loadMoreIdentifier = results.itemIdentifierForRow(results.rowCount - 1)
    check results.outlineItemWithIdentifier(loadMoreIdentifier).title.startsWith(
      "Load 30"
    )
    check clickSearchRow(loadMoreIdentifier)
    check results.rowCount == 62

    loadMoreIdentifier = results.itemIdentifierForRow(results.rowCount - 1)
    check results.outlineItemWithIdentifier(loadMoreIdentifier).title.startsWith(
      "Load 5"
    )
    check clickSearchRow(loadMoreIdentifier)
    check results.rowCount == 66

    let lastResultIdentifier = results.matchIdentifier(64)
    check results.rowForItem(lastResultIdentifier) == 65
    check clickSearchRow(lastResultIdentifier)
    check openedLine == 65
    check openDisposition == fodTemporary

  test "selecting a result activates it at the search result limit":
    let
      root = createTempDir("merenda-kosmo-find-limit-", "")
      frontend =
        newKosmoApplication(newApplication("Kosmo Find Limit Test"), filePath = root)
      contents = "needle\n".repeat(1_000)
    for index in 0 ..< 10:
      writeFile(root / (align($index, 2, '0') & ".txt"), contents)
    defer:
      frontend.close()
      removeDir(root)

    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 760, 520)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(root)
    check frontend.window.makeFirstResponder(frontend.editorView)
    let findShortcutModifiers =
      frontend.shortcutProfile().primaryModifiers() + {nimkit.kmShift}
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: findShortcutModifiers)
    )
    require frontend.sidebarTabs.selectedIndex == 1
    require frontend.searchPanel.queryField.isEditing
    check frontend.window.dispatchTextInput("needle")
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    require frontend.searchPanel.waitForSearch(timeoutMilliseconds = 10_000)
    require frontend.searchPanel.resultsView.matches.len == DefaultFileSearchMaxResults

    frontend.contentView.layoutSubtreeIfNeeded()
    discard frontend.window.buildRenders()
    let
      resultIdentifier = frontend.searchPanel.resultsView.matchIdentifier(10)
      resultRow = frontend.searchPanel.resultsView.rowForItem(resultIdentifier)
      resultRect = frontend.searchPanel.resultsView.rowItemRect(resultRow)
      resultPoint = frontend.searchPanel.resultsView.pointToWindow(
        initPoint(
          resultRect.origin.x + resultRect.size.width * 0.5'f32,
          resultRect.origin.y + resultRect.size.height * 0.5'f32,
        )
      )
    check frontend.window.mouseDownAt(resultPoint)
    check frontend.window.mouseUpAt(resultPoint)

    check frontend.editorView.editor.bufferCursor() ==
      KosmoBufferCursor(line: 10, column: 0)
    check frontend.editorView.editor.tabs()[0].temporary

  when defined(posix):
    test "File menu opens a terminal as a fully managed pane tab":
      let
        frontend = newKosmoApplication(newApplication("Kosmo Terminal Tab Test"))
        fileMenu = frontend.application.mainMenu()[1].submenu()
        terminalItem = fileMenu.menuItemWithIdentifier(KosmoNewTerminalAction)
        initialTabCount = frontend.documentTabs.len
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      check frontend.window.makeFirstResponder(frontend.editorView)

      check frontend.terminalOptionAsMeta
      check frontend.terminalLinksEnabled
      frontend.terminalOptionAsMeta = false
      frontend.terminalLinksEnabled = false
      let terminalActionPerformed = terminalItem.perform(Responder(frontend.editorView))
      require terminalActionPerformed
      check frontend.editorGroups().len == 1
      check frontend.editorGroups()[0].documents.len == 1
      check frontend.documentTabs.len == initialTabCount + 1
      let selectedTitle = frontend.documentTabs.selectedDocumentTabItem().title
      check selectedTitle == "Terminal 1"
      let terminalVisible = frontend.editorPane.contentView of TerminalView
      require terminalVisible
      let terminalView = TerminalView(frontend.editorPane.contentView)
      let optionAsMeta = terminalView.optionAsMeta
      let allowsLinkActivation = terminalView.allowsLinkActivation
      let terminalRunning = terminalView.session().running()
      let terminalIsFirstResponder =
        frontend.window.firstResponder() == Responder(terminalView)
      let terminalFocusVisible = terminalView.focusVisible
      let terminalFocusRingType = terminalView.focusRingType
      check not optionAsMeta
      check not allowsLinkActivation
      check terminalRunning
      check terminalIsFirstResponder
      check terminalFocusVisible
      check terminalFocusRingType == frtNone
      let tabShortcutModifiers =
        frontend.shortcutProfile().primaryModifiers() + {nimkit.kmShift}

      let previousShortcutHandled = frontend.window.dispatchKeyDown(
        KeyEvent(
          key: keyLeftBracket,
          keyCode: keyLeftBracket.ord,
          modifiers: tabShortcutModifiers,
        )
      )
      check previousShortcutHandled
      let editorVisible = frontend.editorPane.contentView == View(frontend.editorView)
      require editorVisible
      let nextShortcutHandled = frontend.window.dispatchKeyDown(
        KeyEvent(
          key: keyRightBracket,
          keyCode: keyRightBracket.ord,
          modifiers: tabShortcutModifiers,
        )
      )
      check nextShortcutHandled
      let terminalRestored = frontend.editorPane.contentView == View(terminalView)
      require terminalRestored

      when defined(macosx) or defined(macos):
        let closeShortcutHandled = frontend.window.dispatchKeyDown(
          KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmCommand})
        )
      else:
        let closeShortcutHandled = frontend.window.dispatchKeyDown(
          KeyEvent(key: keyF4, keyCode: keyF4.ord, modifiers: {kmControl})
        )
      check closeShortcutHandled
      check frontend.editorGroups()[0].documents.len == 0
      check frontend.documentTabs.len == initialTabCount
      let editorRestored = frontend.editorPane.contentView == View(frontend.editorView)
      check editorRestored
      check terminalView.session().state() == tssClosed
      let editorIsFirstResponder =
        frontend.window.firstResponder() == Responder(frontend.editorView)
      check editorIsFirstResponder

suite "Kosmo file replacement":
  test "search controls retain visible toggle state and vector disclosure in both modes":
    let
      panel = newKosmoFileSearchPanel()
      window = newWindow("Search appearance", frame = rect(0, 0, 360, 400))
    defer:
      panel.close()
      window.close()
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    let toggle = panel.buttonWithLabel("Use Reni regular expressions")
    let point = toggle.pointToWindow(initPoint(14, 13))
    for enabled in [true, false]:
      require window.clickAt(point)
      check panel.regularExpression == enabled
      check window.fieldEditorClient() == panel.queryField
      let states =
        if enabled:
          {ssSelected}
        else:
          {}
      let style = toggle.effectiveAppearance().resolveButtonStyle(
          controlStyle(srButton, states, classes = toggle.styleClasses)
        )
      var foundFace = false
      for node in buildRenders(toggle)[DefaultDrawLevel].resolvedNodes():
        if node.kind == nkRectangle and node.fill == style.box.fill:
          foundFace = true
      check foundFace
    let disclosure = panel.buttonWithLabel("Show replacement controls")
    for expanded in [false, true, false]:
      panel.replacementVisible = expanded
      var iconCount = 0
      for node in buildRenders(disclosure)[DefaultDrawLevel].resolvedNodes():
        if node.kind == nkMtsdfImage and node.screenBox.w > 0 and node.screenBox.h > 0:
          inc iconCount
      check iconCount > 0

  test "editor search draws a tinted FigDraw backdrop behind its controls":
    let
      editor = newKosmoEditor(text = "Readable text beneath the search overlay")
      view = newKosmoEditorView(editor)
      window = newWindow("Search backdrop", frame = rect(0, 0, 640, 360))
    defer:
      window.close()
      editor.close()
    window.setContentView(view)
    view.layoutSubtreeIfNeeded()
    view.refresh()
    for expanded in [false, true]:
      require view.showSearch(replacing = expanded)
      let box = view.searchField().superview().superview()
      let frame = box.rectToWindow(box.bounds)
      var blurCount = 0
      for node in window.buildRenders()[DefaultDrawLevel].resolvedNodes():
        if node.kind == nkBackdropBlur:
          inc blurCount
          check node.backdropBlur.blur >= 16
          check node.fill.centerColor().a >= 0.7
          check node.screenBox.x == frame.minX
          check node.screenBox.y == frame.minY
          check node.screenBox.w == frame.size.width
          check node.screenBox.h == frame.size.height
      check blurCount == 1
      for label in ["Previous editor text match", "Next editor text match"]:
        let button = view.buttonWithLabel(label)
        var iconCount = 0
        for node in buildRenders(button)[DefaultDrawLevel].resolvedNodes():
          if node.kind == nkMtsdfImage:
            inc iconCount
        check iconCount > 0

  test "file search tabs through regex then replacement and skips hidden controls":
    let
      panel = newKosmoFileSearchPanel()
      window = newWindow("File search focus", frame = rect(0, 0, 360, 400))
      tab = KeyEvent(key: keyTab, keyCode: keyTab.ord)
      backtab = KeyEvent(key: keyTab, keyCode: keyTab.ord, modifiers: {kmShift})
      regex = panel.buttonWithLabel("Use Reni regular expressions")
    defer:
      window.close()
    window.setContentView(panel)
    panel.replacementVisible = true
    panel.layoutSubtreeIfNeeded()
    require panel.focusQuery()
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == regex
    require window.dispatchKeyDown(tab)
    check window.fieldEditorClient() == panel.replacementField
    require window.dispatchKeyDown(backtab)
    check window.firstResponder() == regex
    let point = panel.replacementField.pointToWindow(initPoint(40, 13))
    require window.mouseDownAt(point)
    discard window.mouseUpAt(point)
    require window.fieldEditorClient() == panel.replacementField
    require window.dispatchTextInput("dog")
    check panel.replacementField.text == "dog"
    check panel.queryField.text == ""
    panel.replacementVisible = false
    check window.fieldEditorClient() == panel.queryField
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == regex
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == panel.buttonWithLabel("Show replacement controls")

  test "file search hides replacement until expanded and preserves results on mode changes":
    let root = createTempDir("kosmo-search-modes-", "")
    writeFile(root / "sample.txt", "cat cat\n")
    let frontend = newKosmoApplication(
      newApplication("File search modes"), filePath = root, monitorsGitStatus = false
    )
    defer:
      frontend.close()
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 900, 600)
    frontend.contentView.layoutSubtreeIfNeeded()
    let window = frontend.window
    let panel = frontend.searchPanel
    let modifiers = frontend.shortcutProfile().primaryModifiers() + {nimkit.kmShift}
    let find = KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: modifiers)
    let replace =
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: modifiers + {nimkit.kmOption})
    require window.makeFirstResponder(frontend.editorView)
    require window.dispatchKeyDown(find)
    check not panel.replacementVisible
    check panel.replacementField.hidden
    check panel.replaceButton.hidden
    check panel.replaceAllButton.hidden
    let compactResultsY = panel.resultsView.frame().minY
    require window.dispatchTextInput("cat")
    require panel.performSearch()
    require panel.waitForSearch()
    check panel.resultsView.matches.len == 2
    let handle = panel.activeSearch()
    let selected = panel.resultsView.matchIdentifier(0)
    panel.resultsView.selectedItemIdentifier = selected

    let toggle = panel.buttonWithLabel("Show replacement controls")
    require not toggle.isNil
    let point = toggle.pointToWindow(
      initPoint(toggle.bounds().size.width / 2, toggle.bounds().size.height / 2)
    )
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    check panel.replacementVisible
    panel.replacementField.checkVisibleIn(panel)
    panel.replaceAllButton.checkVisibleIn(panel)
    check panel.resultsView.frame().minY > compactResultsY
    let replacementPoint = panel.replacementField.pointToWindow(initPoint(40, 13))
    require window.mouseDownAt(replacementPoint)
    discard window.mouseUpAt(replacementPoint)
    require window.fieldEditorClient() == panel.replacementField
    require window.dispatchTextInput("dog")
    require window.dispatchKeyDown(find)
    check not panel.replacementVisible
    check panel.replacementField.hidden
    check window.fieldEditorClient() == panel.queryField
    check panel.resultsView.frame().minY == compactResultsY

    require window.dispatchKeyDown(replace)
    check panel.replacementVisible
    check panel.queryField.text() == "cat"
    check panel.replacementField.text() == "dog"
    check panel.activeSearch() == handle
    check panel.resultsView.matches.len == 2
    check panel.resultsView.selectedItemIdentifier == selected
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    check not panel.replacementVisible
    check panel.resultsView.frame().minY == compactResultsY
    require window.makeFirstResponder(frontend.editorView)
    require window.dispatchKeyDown(replace)
    check panel.replacementVisible
    require frontend.showFileExplorer()
    require window.dispatchKeyDown(find)
    check not panel.replacementVisible

  test "selected and all matches replace literal text and preserve CRLF":
    let root = createTempDir("kosmo-replace-files-", "")
    let path = root / "unicode.txt"
    let second = root / "second.txt"
    writeFile(path, "λ Cat cat\r\ncat\r\n")
    writeFile(second, "cat\n")
    let panel = newKosmoFileSearchPanel(root)
    defer:
      panel.close()
      removeDir(root)
    panel.queryField.text = "cat"
    require panel.performSearch()
    require panel.waitForSearch()
    check panel.resultsView.matches.len == 4
    panel.replacementField.text = "$1"
    for index, match in panel.resultsView.matches:
      if match.path == path and match.line == 1 and match.column == 4:
        panel.resultsView.selectedItemIdentifier =
          panel.resultsView.matchIdentifier(index)
    check panel.replaceMatches() == 1
    require panel.waitForSearch()
    check readFile(path) == "λ $1 cat\r\ncat\r\n"
    panel.replacementField.text = ""
    check panel.replaceMatches(all = true) == 3
    require panel.waitForSearch()
    check readFile(path) == "λ $1 \r\n\r\n"
    check readFile(second) == "\n"
    check panel.resultsView.matches.len == 0
    check "Replaced 3 matches" in panel.statusLabel.text

  test "stale lines and changed queries cannot overwrite a file":
    let root = createTempDir("kosmo-replace-stale-", "")
    let path = root / "sample.txt"
    writeFile(path, "cat cat\n")
    let panel = newKosmoFileSearchPanel(root)
    defer:
      panel.close()
      removeDir(root)
    panel.queryField.text = "cat"
    panel.replacementField.text = "dog"
    require panel.performSearch()
    require panel.waitForSearch()
    panel.queryField.text = "dog"
    check panel.replaceMatches(all = true) == 0
    check readFile(path) == "cat cat\n"
    panel.queryField.text = "cat"
    writeFile(path, "bat cat\n")
    check panel.replaceMatches(all = true) == 0
    require panel.waitForSearch()
    check readFile(path) == "bat cat\n"
    check "skipped 1 files" in panel.statusLabel.text

  test "workspace replacement refreshes clean editors and skips unsaved buffers":
    let root = createTempDir("kosmo-replace-open-", "")
    let path = root / "sample.txt"
    writeFile(path, "cat cat\n")
    let frontend = newKosmoApplication(
      newApplication("Replace open buffers"), filePath = root, monitorsGitStatus = false
    )
    defer:
      frontend.close()
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    require frontend.openPath(path)
    let editor = frontend.editorView.editor
    let id = editor.tabs()[0].id
    let panel = frontend.searchPanel
    panel.queryField.text = "cat"
    panel.replacementField.text = "dog"
    require panel.performSearch()
    require panel.waitForSearch()
    check panel.replaceMatches(all = true) == 2
    require panel.waitForSearch()
    check editor.bufferText(id).get == "dog dog"
    check not editor.tabs()[0].modified
    check editor.replaceSearch("dog", "cat", all = true) == 2
    panel.queryField.text = "dog"
    require panel.performSearch()
    require panel.waitForSearch()
    panel.replacementField.text = "lost"
    check panel.replaceMatches(all = true) == 0
    require panel.waitForSearch()
    check readFile(path) == "dog dog\n"
    check editor.bufferText(id).get == "cat cat"
    check "Unsaved changes" in panel.statusLabel.text

  test "replace all stays within the returned result limit":
    let root = createTempDir("kosmo-replace-limit-", "")
    let path = root / "sample.txt"
    writeFile(path, "cat cat cat\n")
    let panel = newKosmoFileSearchPanel(root)
    defer:
      panel.close()
      removeDir(root)
    panel.searchOptions = initFileSearchOptions(maxResults = 2)
    panel.queryField.text = "cat"
    panel.replacementField.text = "dog"
    require panel.performSearch()
    require panel.waitForSearch()
    check panel.replaceMatches(all = true) == 2
    require panel.waitForSearch()
    check readFile(path) == "dog dog cat\n"
    check panel.resultsView.matches.len == 1

  test "file replacement uses named captures and rejects invalid templates before saving":
    let root = createTempDir("kosmo-reni-files-", "")
    let first = root / "first.txt"
    let second = root / "second.txt"
    writeFile(first, "λ pre:cat\r\n")
    writeFile(second, "pre:dog\n")
    let panel = newKosmoFileSearchPanel(root)
    defer:
      panel.close()
      removeDir(root)
    panel.queryField.text = r"pre:\K(?<animal>\w+)"
    require panel.performSearch()
    require panel.waitForSearch()
    check panel.resultsView.matches.len == 0
    panel.regularExpression = true
    require panel.waitForSearch()
    require panel.resultsView.matches.len == 2
    panel.replacementField.text = "${missing}"
    check panel.replaceMatches(all = true) == 0
    check "Replacement error" in panel.statusLabel.text
    check readFile(first) == "λ pre:cat\r\n"
    check readFile(second) == "pre:dog\n"
    panel.replacementField.text = "${animal}-$0-$$"
    check panel.replaceMatches(all = true) == 2
    require panel.waitForSearch()
    check readFile(first) == "λ pre:cat-cat-$\r\n"
    check readFile(second) == "pre:dog-dog-$\n"
    panel.regularExpression = false
    require panel.waitForSearch()
    check panel.resultsView.matches.len == 0

  test "file expression toggle refreshes results and reports invalid patterns":
    let root = createTempDir("kosmo-reni-toggle-", "")
    writeFile(root / "sample.txt", "a.b axb\n")
    let panel = newKosmoFileSearchPanel(root)
    let window = newWindow("Reni file controls", frame = rect(0, 0, 360, 400))
    defer:
      panel.close()
      window.close()
      removeDir(root)
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    panel.queryField.text = "a.b"
    require panel.performSearch()
    require panel.waitForSearch()
    check panel.resultsView.matches.len == 1
    let toggle = panel.buttonWithLabel("Use Reni regular expressions")
    require not toggle.isNil
    toggle.checkVisibleIn(panel)
    let point = toggle.pointToWindow(
      initPoint(toggle.bounds().size.width / 2, toggle.bounds().size.height / 2)
    )
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    require panel.waitForSearch()
    check panel.regularExpression
    check panel.resultsView.matches.len == 2
    panel.queryField.text = "("
    check not panel.performSearch()
    check panel.activeSearch().isNil
    check not panel.replaceAllButton.enabled
    check panel.statusLabel.text.len > 0
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    require panel.waitForSearch()
    check not panel.regularExpression
    check panel.resultsView.matches.len == 0
