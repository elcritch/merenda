## Kosmo's public API and frontend-specific adapters.
import std/[strutils, unicode, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import kosmo/cli
import kosmo/config
import kosmo/editorsearch
import kosmo/filetreeinteractions
import kosmo/matterhighlighting
import kosmo/panelshortcuts
import kosmo/quickopen
import kosmo/terminalclipboard
import kosmo/terminalsearch
import kosmo/workspaceroots

proc runeIndexOf(source, needle: string): int =
  let byteIndex = source.find(needle)
  if byteIndex >= 0:
    result = source[0 ..< byteIndex].runeLen

suite "Kosmo public adapters":
  test "main menu keeps both Kosmo and Merenda settings":
    let app = newApplication("Kosmo Test")
    let frontend = newKosmoApplication(app)
    defer:
      frontend.close()
    let settingsItem = app.mainMenu()[0].submenu()[2]
    check settingsItem.action().name == actionSelector(KosmoShowSettingsAction).name
    var includesMerendaSettings = false
    for item in app.windowsMenu().items():
      if item.action().name == actionSelector("showMerendaSettings").name:
        check item.title == "Merenda Settings"
        includesMerendaSettings = true
    check includesMerendaSettings

  test "Moe syntax highlighting maps broad languages to neutral rune spans":
    let
      nimSource = "proc π(): int = 42 # answer"
      nimSpans = moeSyntaxHighlighter(nimSource, "nim")
      goSource = "func main() { value := \"κόσμος\" }"
      goSpans = moeSyntaxHighlighter(goSource, "go")

    check nimSpans.syntaxTokenAt(nimSource.runeIndexOf("proc")) == stcKeyword
    check nimSpans.syntaxTokenAt(nimSource.runeIndexOf("π")) == stcIdentifier
    check nimSpans.syntaxTokenAt(nimSource.runeIndexOf("42")) == stcNumber
    check nimSpans.syntaxTokenAt(nimSource.runeIndexOf("# answer")) == stcComment
    check goSpans.syntaxTokenAt(goSource.runeIndexOf("func")) == stcKeyword
    check goSpans.syntaxTokenAt(goSource.runeIndexOf("\"κόσμος\"")) == stcString
    check moeSyntaxHighlighter("value", "not-a-language").len == 0

  test "Moe adapter installs on editors and Markdown fenced code":
    let editor = newSynEditView("proc answer = 42", syntaxHighlighter = nil)
    editor.installMoeSyntaxHighlighter()
    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[stcKeyword]

    let preview = newMarkdownView("```go\nfunc main() {}\n```", syntaxHighlighter = nil)
    require preview.waitForMarkdownParsing()
    preview.installMoeSyntaxHighlighter()
    require preview.waitForMarkdownRendering()
    let funcIndex = preview.textStorage().stringValue().runeIndexOf("func")
    check preview.textStorage().attributesAt(funcIndex).foregroundColor ==
      preview.markdownStyle().syntaxTokenColors[stcKeyword]
