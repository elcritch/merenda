import std/[os, strutils, tempfiles, unittest]
import merenda/nimkit
import merenda/kosmo/kosmo
import merenda/kosmo/viewersearch
import fixtures/ui

suite "Kosmo viewer search":
  test "literal Unicode search reports rune ranges and overlapping matches":
    check plainSearchRanges("λ Straße λ", "Λ") ==
      @[initTextRange(0, 1), initTextRange(9, 1)]
    check plainSearchRanges("[a] . [A]", "[a]") ==
      @[initTextRange(0, 3), initTextRange(6, 3)]
    check plainSearchRanges("aaaa", "aa") ==
      @[initTextRange(0, 2), initTextRange(1, 2), initTextRange(2, 2)]
    check plainSearchRanges("anything", "").len == 0

  test "Markdown find selects rendered text, wraps, and restores preview focus":
    let root = createTempDir("kosmo-markdown-find-", "")
    let path = root / "search.md"
    writeFile(path, "# Search\n\nλ **Needle** and needle.\n")
    let frontend =
      newKosmoApplication(newApplication("Markdown search"), monitorsGitStatus = false)
    defer:
      frontend.close()
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 900, 600)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    let view = frontend.editorPane.markdownView
    require view.waitForMarkdownRendering()
    require frontend.window.makeFirstResponder(view.textView())
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: shortcutModifiers())
    )
    check view.searchVisible()
    view.searchField().checkVisibleIn(view)
    require frontend.window.dispatchTextInput("needle")
    check view.searchMatchCount() == 2
    check view.textView().selectedText() == "Needle"
    let first = view.textView().selectedRange()
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    check view.textView().selectedText() == "needle"
    check view.textView().selectedRange().location > first.location
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyG, keyCode: keyG.ord, modifiers: shortcutModifiers())
    )
    check view.textView().selectedRange() == first
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check not view.searchVisible()
    check view.textView().selectedRange().length == 0
    check frontend.window.firstResponder() == view
    check readFile(path) == "# Search\n\nλ **Needle** and needle.\n"

  test "Git diff find searches collapsed files and reveals selected text":
    let snapshot = parseGitDiff(
      "diff --git a/a.txt b/a.txt\n@@ -1 +1 @@\n-before\n+λ needle\n" &
        "diff --git a/b.txt b/b.txt\n@@ -1 +1 @@\n-before\n+other NEEDLE\n"
    )
    let panel = newKosmoGitDiffPanel(snapshot)
    let window = newWindow("Diff search", frame = rect(0, 0, 700, 420))
    defer:
      panel.close()
      window.close()
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    panel.toggleFile(1)
    check panel.isFileCollapsed(1)
    require window.makeFirstResponder(panel.markdownView.textView())
    require window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: shortcutModifiers())
    )
    check panel.searchVisible()
    panel.searchField().checkVisibleIn(panel)
    require window.dispatchTextInput("needle")
    require panel.waitForDiff()
    check panel.searchMatchCount() == 2
    check panel.textViewForFile(0).selectedText() == "needle"
    require window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    require panel.waitForDiff()
    check not panel.isFileCollapsed(1)
    check panel.textViewForFile(1).selectedText() == "NEEDLE"
    require window.dispatchKeyDown(KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord))
    require panel.waitForDiff()
    check panel.textViewForFile(0).selectedText() == "needle"
    require window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not panel.searchVisible()
    check panel.textViewForFile(0).selectedRange().length == 0

  test "Markdown search reveals matches in horizontally scrolling code":
    let root = createTempDir("kosmo-markdown-code-find-", "")
    let path = root / "code.md"
    writeFile(path, "# Code\n\n```text\n" & repeat("wide ", 100) & "needle\n```\n")
    let frontend =
      newKosmoApplication(newApplication("Code search"), monitorsGitStatus = false)
    defer:
      frontend.close()
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 700, 460)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    let view = frontend.editorPane.markdownView
    require view.waitForMarkdownParsing()
    require view.waitForMarkdownLayout()
    require view.showSearch()
    require frontend.window.dispatchTextInput("needle")
    require view.waitForMarkdownLayout()
    check view.searchMatchCount() == 1
    var found = false
    for child in view.textView().subviews():
      if child of ScrollView:
        let scroll = ScrollView(child)
        if scroll.documentView() of TextView and not scroll.hidden:
          let code = TextView(scroll.documentView())
          if code.selectedText() == "needle":
            found = true
            check scroll.contentOffset().x > 0
            let matchRect = code.characterRect(code.selectedRange().location)
            let lastRect = code.characterRect(code.selectedRange().maxIndex - 1)
            check lastRect.maxX <= scroll.contentOffset().x + scroll.viewportSize().width
            check matchRect.minX >= scroll.contentOffset().x
            check matchRect.maxX <=
              scroll.contentOffset().x + scroll.viewportSize().width
    check found
