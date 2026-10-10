import std/[algorithm, os, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc collectEditorPanes(view: nimkit.View, panes: var seq[KosmoEditorPane]) =
  ## Collect the editor panes below the view in depth-first order.
  if view of KosmoEditorPane:
    panes.add KosmoEditorPane(view)
  for child in view.xSubviews:
    child.collectEditorPanes(panes)

proc paneFrame(pane: KosmoEditorPane, content: nimkit.View): Rect =
  ## Frame of the pane in content view coordinates; a pane's own frame is
  ## relative to its parent dock panel, so ordering needs the converted one.
  pane.rectToView(pane.bounds(), content)

proc sortedEditorPanes(content: nimkit.View): seq[KosmoEditorPane] =
  ## Editor panes below the view, sorted left to right and top to bottom by
  ## their position in the content view.
  var panes: seq[KosmoEditorPane]
  collectEditorPanes(content, panes)
  panes.sort(
    proc(a, b: KosmoEditorPane): int =
      let
        first = paneFrame(a, content)
        second = paneFrame(b, content)
      if first.origin.x != second.origin.x:
        cmp(first.origin.x, second.origin.x)
      else:
        cmp(first.origin.y, second.origin.y)
  )
  panes

suite "Kosmo editor pane tab navigation":
  test "<tab> cycles etabs on the strip without entering the editor":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let models = frontend.documentTabs.documentTabModels()
    require models.len == 2

    # <tab> from the first etab selects the next etab and keeps focus on the
    # strip instead of entering the editor.
    check frontend.documentTabs.selectDocumentTabWithIdentifier(models[0].identifier)
    check frontend.window.makeFirstResponder(frontend.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(frontend.documentTabs)
    check frontend.documentTabs.selectedDocumentTabIdentifier == models[1].identifier

    # <tab> from the last etab leaves the strip but must not enter the editor.
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "")
    )
    check frontend.window.firstResponder() != Responder(frontend.editorView)
    check frontend.documentTabs.selectedDocumentTabIdentifier == models[1].identifier

    # <shift><tab> from the first etab moves to the previous element and never
    # into the editor.
    check frontend.documentTabs.selectDocumentTabWithIdentifier(models[0].identifier)
    check frontend.window.makeFirstResponder(frontend.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "", modifiers: {kmShift})
    )
    check frontend.window.firstResponder() != Responder(frontend.editorView)

  test "<shift><tab> cycles etabs back on the strip":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let models = frontend.documentTabs.documentTabModels()
    require models.len == 2

    # <shift><tab> from the second etab selects the previous etab and keeps
    # focus on the strip.
    check frontend.window.makeFirstResponder(frontend.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "", modifiers: {kmShift})
    )
    check frontend.window.firstResponder() == Responder(frontend.documentTabs)
    check frontend.documentTabs.selectedDocumentTabIdentifier == models[0].identifier

    # <tab> cycles forward again from the first etab.
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(frontend.documentTabs)
    check frontend.documentTabs.selectedDocumentTabIdentifier == models[1].identifier

  test "<return> on an etab enters the editor":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    check frontend.window.makeFirstResponder(frontend.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord, text: "\r")
    )
    check frontend.window.firstResponder() == Responder(frontend.editorView)

  test "editor normal mode <tab> leaves the editor and <shift><tab> returns to the strip":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)
    require frontend.editorView.editor.mode() == KosmoEditorMode.Normal

    # <tab> in normal mode cycles out of the editor to the next element.
    check frontend.window.makeFirstResponder(frontend.editorView)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "")
    )
    check frontend.window.firstResponder() != Responder(frontend.editorView)

    # <shift><tab> in normal mode returns to the pane's etab strip.
    check frontend.window.makeFirstResponder(frontend.editorView)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "", modifiers: {kmShift})
    )
    check frontend.window.firstResponder() == Responder(frontend.documentTabs)

  test "focus outside the pane unhighlights the selected etab":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    # Focusing the editor pane keeps its selected etab highlighted: the strip
    # carries no kosmo-inactive-pane style class.
    check frontend.window.makeFirstResponder(frontend.editorView)
    check not frontend.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)

    # Cycling out of the strip at the last etab moves focus to the next ui
    # element (the menubar) and unhighlights the selected etab.
    check frontend.window.makeFirstResponder(frontend.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, text: "")
    )
    check frontend.window.firstResponder() != Responder(frontend.editorView)
    check frontend.window.firstResponder() != Responder(frontend.documentTabs)
    check frontend.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)

    # Focusing the pane again re-highlights the selected etab.
    check frontend.window.makeFirstResponder(frontend.editorView)
    check not frontend.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)

  test "<right> and <left> move between split panes and exit at the edges":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    # Split the pane to the right so two panes sit side by side.
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()

    let panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 2
    let
      left = panes[0]
      right = panes[1]

    # <right> from the left pane's strip focuses the pane to the right.
    check frontend.window.makeFirstResponder(left.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(right.documentTabs)

    # <left> moves back to the left pane.
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(left.documentTabs)

    # <left> at the left edge leaves the pane for the previous ui element.
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord, text: "")
    )
    check frontend.window.firstResponder() != Responder(left.documentTabs)
    check frontend.window.firstResponder() != Responder(right.documentTabs)
    check frontend.window.firstResponder() != Responder(left.editorView)
    check frontend.window.firstResponder() != Responder(right.editorView)

    # <right> from the rightmost pane leaves the pane for the next ui element.
    check frontend.window.makeFirstResponder(right.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() != Responder(left.documentTabs)
    check frontend.window.firstResponder() != Responder(right.documentTabs)

  test "<down> and <up> move between vertically split panes and never leave the pane":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    # Split the pane so two panes stack vertically.
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()

    let panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 2
    let
      top = panes[0]
      bottom = panes[1]

    # <down> from the top pane's strip focuses the pane below.
    check frontend.window.makeFirstResponder(top.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(bottom.documentTabs)

    # <down> at the bottom edge has no pane below and stays on the strip.
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(bottom.documentTabs)

    # <up> moves back to the pane above.
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(top.documentTabs)

    # <up> at the top edge has no pane above and stays on the strip.
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(top.documentTabs)

  test "<right> from a split middle column picks the pane in the same row":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    # Build the three-column layout with the middle and right columns split
    # into a top and bottom pane.
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitVerticalAction))
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    var panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 3
    check panes[1].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    check panes[2].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 5
    # Column order left to right; the middle and right columns hold a top and
    # a bottom pane.
    let
      middleTop = panes[1]
      middleBottom = panes[2]
      rightTop = panes[3]
      rightBottom = panes[4]

    # <right> from the middle column's bottom pane stays in the same row.
    check frontend.window.makeFirstResponder(middleBottom.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(rightBottom.documentTabs)

    # <right> from the middle column's top pane stays in the same row.
    check frontend.window.makeFirstResponder(middleTop.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(rightTop.documentTabs)

  test "<right> from a full-height pane picks the topmost pane of the neighbor column":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    # Build the reported layout: a full-height pane on the left and a right
    # column split into a top and a bottom pane.
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    let columns = frontend.contentView.sortedEditorPanes()
    require columns.len == 2
    check columns[1].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()

    let panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 3
    let
      left = panes[0]
      rightTop = panes[1]
      rightBottom = panes[2]

    # Both panes of the right column are equidistant from the full-height
    # pane, so the topmost one must win instead of leaving the choice to
    # layout float noise.
    check frontend.window.makeFirstResponder(left.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(rightTop.documentTabs)

  test "<right> from a full-height pane picks the topmost pane with uneven splits":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    # Build the reported layout: a full-height pane on the left, the middle
    # column split into three stacked panes and the right column split into
    # three stacked panes.
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitVerticalAction))
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    var panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 3
    check panes[1].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 4
    check panes[2].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 5
    check panes[4].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 6
    check panes[5].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 7
    # Column order left to right; the middle and right columns hold a tall
    # top pane and two shorter panes below.
    let
      middleTop = panes[1]
      middleMiddle = panes[2]
      middleBottom = panes[3]
      rightTop = panes[4]
      rightMiddle = panes[5]
      rightBottom = panes[6]

    # The full-height pane spans every row, so <right> must land on the
    # topmost pane of the nearest column instead of the pane whose center is
    # closest to the window middle.
    check frontend.window.makeFirstResponder(panes[0].documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(middleTop.documentTabs)

    # Short panes keep the same-row behavior.
    check frontend.window.makeFirstResponder(middleMiddle.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(rightMiddle.documentTabs)

    check frontend.window.makeFirstResponder(middleBottom.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() == Responder(rightBottom.documentTabs)

    # The right column is the rightmost one: <right> from its bottom pane has
    # no pane neighbor and must leave the pane area entirely.
    check frontend.window.makeFirstResponder(rightBottom.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() != Responder(rightTop.documentTabs)
    check frontend.window.firstResponder() != Responder(rightBottom.documentTabs)
    check frontend.window.firstResponder() != Responder(rightBottom.editorView)

  test "<right> from a rightmost stacked pane leaves the pane area":
    let
      root = createTempDir("merenda-kosmo-tabnav-", "")
      filePath = root / "first.txt"
    writeFile(filePath, "first")
    defer:
      removeFile(filePath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tab Navigation Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(filePath)

    # Full-height pane on the left and a right column split into a top and a
    # bottom pane.
    check frontend.editorView.tryToPerform(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    let columns = frontend.contentView.sortedEditorPanes()
    require columns.len == 2
    check columns[1].editorView.tryToPerform(actionSelector(KosmoSplitHorizontalAction))
    frontend.contentView.layoutSubtreeIfNeeded()

    let panes = frontend.contentView.sortedEditorPanes()
    require panes.len == 3
    let
      left = panes[0]
      rightTop = panes[1]
      rightBottom = panes[2]

    # The right column is the rightmost one: <right> from its top pane has no
    # pane neighbor and must leave the pane area entirely instead of landing
    # on the sibling strip below.
    check frontend.window.makeFirstResponder(rightTop.documentTabs)
    discard frontend.window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, text: "")
    )
    check frontend.window.firstResponder() != Responder(left.documentTabs)
    check frontend.window.firstResponder() != Responder(rightTop.documentTabs)
    check frontend.window.firstResponder() != Responder(rightBottom.documentTabs)
    check frontend.window.firstResponder() != Responder(left.editorView)
    check frontend.window.firstResponder() != Responder(rightTop.editorView)
    check frontend.window.firstResponder() != Responder(rightBottom.editorView)
