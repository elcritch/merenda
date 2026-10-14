## Search controls exercised through the same keyboard dispatch as user input.

import std/[unicode, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

proc pressSearchKey(
    window: Window, key: Key, modifiers: set[nimkit.KeyModifier] = {}
): bool =
  let text =
    case key
    of keyTab: "\t"
    of keyEnter: "\n"
    else: ""
  let event = KeyEvent(text: text, key: key, keyCode: key.ord, modifiers: modifiers)
  result = window.dispatchKeyDown(event)
  discard window.dispatchKeyUp(event)
  discard window.buildRenders()

proc typeSearchText(window: Window, text: string) =
  for rune in text.runes:
    let value = rune.toUTF8()
    discard window.dispatchKeyDown(
      KeyEvent(key: keyForText(value), keyCode: keyCodeForText(value))
    )
    require window.dispatchTextInput(value)
    discard window.buildRenders()

proc newSearchInputFrontend(): KosmoApplication =
  result = newKosmoApplication(
    newApplication("Kosmo search synthetic input"), monitorsGitStatus = false
  )
  result.application.addWindow(result.window)
  result.window.setContentView(result.contentView)
  result.contentView.frame = rect(0, 0, 900, 600)
  result.contentView.layoutSubtreeIfNeeded()
  require result.window.makeFirstResponder(result.editorView)
  result.application.activateWindow(result.window)

proc openSearchInput(frontend: KosmoApplication, inFiles, replacing: bool): TextField =
  var modifiers = frontend.shortcutProfile().primaryModifiers()
  if inFiles:
    modifiers.incl(nimkit.kmShift)
  if replacing:
    modifiers.incl(nimkit.kmOption)
  require frontend.window.pressSearchKey(keyF, modifiers)
  if inFiles:
    result = frontend.searchPanel.queryField
  else:
    result = frontend.editorView.searchField()
  require frontend.window.fieldEditorClient() == result

proc tabToSearchControl(window: Window, control: View): bool =
  for _ in 0 ..< 20:
    if window.firstResponder() == control or window.fieldEditorClient() == control:
      return true
    if not window.pressSearchKey(keyTab):
      return

template withSearchClipboard(body: untyped) =
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

suite "Kosmo search synthetic input":
  for inFiles in [false, true]:
    let panelName = if inFiles: "file search" else: "editor search"
    for replacing in [false, true]:
      let fieldName = if replacing: "replacement" else: "query"
      test "paste inserts clipboard text into the focused " & panelName & " " & fieldName:
        checkpoint "inFiles=" & $inFiles & ", replacing=" & $replacing
        let frontend = newSearchInputFrontend()
        defer:
          frontend.close()
        let
          window = frontend.window
          query = frontend.openSearchInput(inFiles, replacing)
          bufferId = frontend.editorView.editor.tabs()[0].id
        if replacing:
          require window.pressSearchKey(keyTab)
          require window.pressSearchKey(keyTab)
        let field =
          if not replacing:
            query
          elif inFiles:
            frontend.searchPanel.replacementField
          else:
            frontend.editorView.replacementField()
        require window.fieldEditorClient() == field
        window.typeSearchText("prefix ")
        withSearchClipboard:
          require pasteboard.replaceWithPlainText(" λ needle ")
          require window.pressSearchKey(
            keyV, frontend.shortcutProfile().primaryModifiers()
          )
          check field.text() == "prefix  λ needle "
          require window.pressSearchKey(keyTab)
          check field.text() == "prefix  λ needle "
          check frontend.editorView.editor.bufferText(bufferId).get == ""
          check frontend.editorView.editor.mode() == KosmoEditorMode.Normal

      test panelName & " " & fieldName & " owns select all copy cut undo redo and paste":
        checkpoint "inFiles=" & $inFiles & ", replacing=" & $replacing
        let frontend = newSearchInputFrontend()
        defer:
          frontend.close()
        let
          window = frontend.window
          query = frontend.openSearchInput(inFiles, replacing)
          modifiers = frontend.shortcutProfile().primaryModifiers()
          bufferId = frontend.editorView.editor.tabs()[0].id
        if replacing:
          require window.pressSearchKey(keyTab)
          require window.pressSearchKey(keyTab)
        let field =
          if not replacing:
            query
          elif inFiles:
            frontend.searchPanel.replacementField
          else:
            frontend.editorView.replacementField()
        require window.fieldEditorClient() == field
        window.typeSearchText("λ needle")
        withSearchClipboard:
          require pasteboard.replaceWithPlainText("previous clipboard")
          require window.pressSearchKey(keyA, modifiers)
          check field.selectedRange() == initTextRange(0, "λ needle".runeLen)
          require window.pressSearchKey(keyC, modifiers)
          check pasteboard.plainText() == "λ needle"
          require window.pressSearchKey(keyX, modifiers)
          check field.text() == ""
          check pasteboard.plainText() == "λ needle"
          require window.pressSearchKey(keyZ, modifiers)
          check field.text() == "λ needle"
          require window.pressSearchKey(keyZ, modifiers + {nimkit.kmShift})
          check field.text() == ""
          require window.pressSearchKey(keyV, modifiers)
          check field.text() == "λ needle"
          require window.pressSearchKey(keyTab)
          check field.text() == "λ needle"
          check frontend.editorView.editor.bufferText(bufferId).get == ""
          check frontend.editorView.editor.mode() == KosmoEditorMode.Normal

    test "Tab Enter Tab on replacement disclosure preserves the query in " & panelName:
      checkpoint "inFiles=" & $inFiles
      let frontend = newSearchInputFrontend()
      defer:
        frontend.close()
      frontend.window.typeSearchText("ineedle needle")
      require frontend.window.pressSearchKey(keyEscape)
      let
        window = frontend.window
        query = frontend.openSearchInput(inFiles, replacing = false)
        searchView =
          if inFiles:
            View(frontend.searchPanel)
          else:
            View(frontend.editorView)
      window.typeSearchText("needle")
      for expanding in [true, false, true]:
        let disclosure = searchView.buttonWithLabel(
          if expanding: "Show replacement controls" else: "Hide replacement controls"
        )
        require not disclosure.isNil
        require window.tabToSearchControl(disclosure)
        require window.pressSearchKey(keyEnter)
        check query.text() == "needle"
        let replacement =
          if inFiles:
            frontend.searchPanel.replacementField
          else:
            frontend.editorView.replacementField()
        check replacement.hidden == not expanding
        require window.pressSearchKey(keyTab)
        check query.text() == "needle"
        if expanding:
          require window.pressSearchKey(keyTab)
          check window.fieldEditorClient() == replacement
          check query.text() == "needle"
        require window.pressSearchKey(keyTab, {nimkit.kmShift})
        check query.text() == "needle"

    for queryText in [" needle ", " "]:
      test "replacement disclosure preserves literal query " & repr(queryText) & " in " &
        panelName:
        let frontend = newSearchInputFrontend()
        defer:
          frontend.close()
        let
          window = frontend.window
          query = frontend.openSearchInput(inFiles, replacing = false)
          searchView =
            if inFiles:
              View(frontend.searchPanel)
            else:
              View(frontend.editorView)
          disclosure = searchView.buttonWithLabel("Show replacement controls")
        window.typeSearchText(queryText)
        require window.tabToSearchControl(disclosure)
        require window.pressSearchKey(keyEnter)
        check query.text() == queryText
        require window.pressSearchKey(keyTab)
        check query.text() == queryText
