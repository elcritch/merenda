import std/[os, strutils, tempfiles, unicode, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc pressClipboardKey(frontend: KosmoApplication, key: Key): bool =
  let event = KeyEvent(
    key: key, keyCode: key.ord, modifiers: frontend.shortcutProfile().primaryModifiers()
  )
  result = frontend.window.dispatchKeyDown(event)
  discard frontend.window.dispatchKeyUp(event)

proc runViewerCommand(frontend: KosmoApplication, command: string) =
  require frontend.window.makeFirstResponder(frontend.editorView)
  require frontend.window.dispatchTextInput(":")
  require frontend.window.dispatchTextInput(command)
  require frontend.window.dispatchKeyDown(
    KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
  )

template withViewerClipboard(body: untyped) =
  block:
    let
      pasteboard {.inject.} = generalPasteboard()
      previousProvider = pasteboard.provider
    pasteboard.provider = nil
    pasteboard.clearContents()
    defer:
      pasteboard.clearContents()
      pasteboard.provider = previousProvider
    body

suite "Kosmo view clipboard commands":
  for viewer in [
    "Markdown", "GitHub", "Git diff summary", "Git diff hunk", "Help", "Command Output",
    "custom reader",
  ]:
    test viewer & " owns copy and select all without editing the hidden buffer":
      let
        root = createTempDir("kosmo-view-clipboard-", "")
        frontend = newKosmoApplication(
          newApplication("Kosmo view clipboard"), monitorsGitStatus = false
        )
        window = frontend.window
        editor = frontend.editorView.editor
      defer:
        frontend.close()
        removeDir(root)
      frontend.application.addWindow(window)
      window.setContentView(frontend.contentView)
      frontend.contentView.frame = rect(0, 0, 900, 600)
      require editor.handleKey("i")
      require editor.handleTextInput("hidden editor text")
      require editor.handleKey("Esc")
      frontend.editorView.refresh()
      frontend.application.activateWindow(window)

      var text: TextView
      var container: View
      var diff: KosmoGitDiffPanel
      var github: KosmoGitHubPanel
      defer:
        if not diff.isNil:
          diff.close()
        if not github.isNil:
          github.close()
      case viewer
      of "Markdown":
        let path = root / "preview.md"
        writeFile(path, "# Visible λ\n\nA **rendered** paragraph.\n")
        require frontend.openPath(path)
        let preview = frontend.editorPane.markdownView
        require preview.waitForMarkdownParsing()
        text = preview.textView()
        container = preview
      of "GitHub":
        github = newKosmoGitHubPanel(
          GitHubSnapshot(
            items:
              @[
                GitHubItem(
                  kind: ghikIssue,
                  number: 7,
                  title: "Visible λ",
                  body: "Issue body",
                  state: "OPEN",
                ),
                GitHubItem(
                  kind: ghikPullRequest,
                  number: 8,
                  title: "A PR",
                  body: "PR body",
                  state: "OPEN",
                ),
              ]
          )
        )
        text = github.markdownView.textView()
        container = github
        require frontend.openDocument(
          newKosmoPaneDocument(
            "test.github", "GitHub", github, preferredFirstResponder = text
          )
        )
        require github.waitForGitHub()
      of "Git diff summary", "Git diff hunk":
        diff = newKosmoGitDiffPanel(
          parseGitDiff(
            "diff --git a/query.sql b/query.sql\n@@ -1 +1 @@\n-old λ\n+new 猫\n"
          )
        )
        require frontend.openDocument(
          newKosmoPaneDocument(
            "test.diff",
            "Git Diff",
            diff,
            preferredFirstResponder = diff.markdownView.textView(),
          )
        )
        require diff.waitForDiff()
        container = diff
        text =
          if viewer == "Git diff hunk":
            diff.textViewForFile(0)
          else:
            diff.markdownView.textView()
      of "Help":
        frontend.runViewerCommand("help")
        let help = MarkdownView(frontend.editorPane.contentView)
        require help.waitForMarkdownParsing()
        text = help.textView()
        container = help
      of "Command Output":
        frontend.runViewerCommand("jobs")
        let scroll = ScrollView(frontend.editorPane.contentView)
        text = TextView(scroll.documentView())
        container = scroll
      else:
        text = newTextView("Visible λ\nSecond line 猫")
        text.editable = false
        container = newScrollView(documentView = text)
        require frontend.openDocument(
          newKosmoPaneDocument(
            "test.reader", "Reader", container, preferredFirstResponder = text
          )
        )
      require not text.isNil
      frontend.contentView.layoutSubtreeIfNeeded()
      let visible = text.stringValue()
      require visible.runeLen > 3
      var bufferId: KosmoBufferId
      for tab in editor.tabs():
        if tab.active:
          bufferId = tab.id
      let original = editor.bufferText(bufferId).get()
      require editor.selectAll()

      withViewerClipboard:
        for profile in KosmoShortcutProfile:
          frontend.setShortcutProfile(profile)
          require window.makeFirstResponder(text)
          text.selectedRange = initTextRange(1, 3)
          let selected = text.selectedText()
          require pasteboard.replaceWithPlainText("previous clipboard")
          require frontend.pressClipboardKey(keyC)
          check pasteboard.plainText() == selected
          require frontend.application.performMenuKeyEquivalent(
            KeyEvent(
              key: keyC, keyCode: keyC.ord, modifiers: profile.primaryModifiers()
            )
          )
          check pasteboard.plainText() == selected
          for action in ["copy", KosmoCopyAction]:
            require pasteboard.replaceWithPlainText("previous clipboard")
            require window.sendAction(actionSelector(action))
            check pasteboard.plainText() == selected

          require frontend.pressClipboardKey(keyA)
          check text.selectedText() == visible
          require frontend.pressClipboardKey(keyC)
          check pasteboard.plainText() == visible
          for action in [
            "cut", "paste", "undo", "redo", KosmoCutAction, KosmoPasteAction,
            KosmoUndoAction, KosmoRedoAction,
          ]:
            require window.sendAction(actionSelector(action))
            check text.stringValue() == visible
            check editor.bufferText(bufferId).get() == original
          for key in [keyX, keyV, keyZ]:
            require frontend.pressClipboardKey(key)
            check editor.bufferText(bufferId).get() == original

          text.selectedRange = initTextRange(0, 0)
          require pasteboard.replaceWithPlainText("keep empty selection")
          require frontend.pressClipboardKey(keyC)
          check pasteboard.plainText() == "keep empty selection"

        if viewer != "Git diff hunk" and container.acceptsFirstResponder():
          require window.makeFirstResponder(container)
          require window.sendAction(actionSelector(KosmoSelectAllAction))
          require window.sendAction(actionSelector(KosmoCopyAction))
          check pasteboard.plainText() == visible
        check editor.bufferText(bufferId).get() == original

  test "overflowing Markdown code and tables copy their own focused selections":
    let frontend = newKosmoApplication(
      newApplication("Kosmo nested Markdown clipboard"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 600, 500)
    let preview = newMarkdownView(
      "# Outer selection\n\n```sql\nSELECT λ " & "column ".repeat(30) &
        "\n```\n\n| A | B | C | D | E | F | G | H |\n" &
        "| - | - | - | - | - | - | - | - |\n" &
        "| 猫 row | 猫 row | 猫 row | 猫 row | 猫 row | 猫 row | 猫 row | 猫 row |"
    )
    require frontend.openDocument(
      newKosmoPaneDocument(
        "test.nested-markdown",
        "Markdown",
        preview,
        preferredFirstResponder = preview.textView(),
      )
    )
    require preview.waitForMarkdownParsing()
    frontend.contentView.layoutSubtreeIfNeeded()
    discard buildRenders(preview)
    require preview.waitForMarkdownLayout()
    var embedded: seq[TextView]
    for child in preview.textView().subviews():
      if child of ScrollView:
        let document = ScrollView(child).documentView()
        if document of TextView:
          embedded.add TextView(document)
    require embedded.len == 2
    preview.textView().selectedRange = initTextRange(0, 5)
    withViewerClipboard:
      for text in embedded:
        require frontend.window.makeFirstResponder(text)
        text.selectedRange = initTextRange(1, 3)
        let selected = text.selectedText()
        require frontend.pressClipboardKey(keyC)
        check pasteboard.plainText() == selected
        require frontend.pressClipboardKey(keyA)
        require frontend.pressClipboardKey(keyC)
        check pasteboard.plainText() == text.stringValue()
        text.selectedRange = initTextRange(0, 0)
        require pasteboard.replaceWithPlainText("keep clipboard")
        require frontend.pressClipboardKey(keyC)
        check pasteboard.plainText() == "keep clipboard"
        require frontend.pressClipboardKey(keyV)
        check frontend.editorView.editor
        .bufferText(frontend.editorView.editor.tabs()[0].id)
        .get() == ""

  test "an editable document receives paste cut undo and redo":
    let frontend = newKosmoApplication(
      newApplication("Kosmo editable document clipboard"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    let
      text = newTextView("original λ")
      bufferId = frontend.editorView.editor.tabs()[0].id
    require frontend.openDocument(
      newKosmoPaneDocument("test.editable", "Editable", text)
    )
    withViewerClipboard:
      require pasteboard.replaceWithPlainText("replacement 猫")
      require frontend.pressClipboardKey(keyA)
      require frontend.pressClipboardKey(keyV)
      check text.stringValue() == "replacement 猫"
      require frontend.window.sendAction(actionSelector(KosmoUndoAction))
      check text.stringValue() == "original λ"
      require frontend.window.sendAction(actionSelector(KosmoRedoAction))
      check text.stringValue() == "replacement 猫"
      require frontend.pressClipboardKey(keyA)
      require frontend.pressClipboardKey(keyX)
      check text.stringValue() == ""
      check pasteboard.plainText() == "replacement 猫"
      check frontend.editorView.editor.bufferText(bufferId).get() == ""
