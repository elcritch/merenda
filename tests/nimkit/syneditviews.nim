import std/[strutils, unicode, unittest]

import sigils/core

import merenda/nimkit
import merenda/nimkit/text/syneditviews

type HighlightEventSpy = ref object of DynamicAgent
  attributeRanges: seq[TextRange]

proc rememberHighlightEdit(spy: HighlightEventSpy, edit: TextStorageEdit) {.slot.} =
  spy.attributeRanges.add edit.range

proc tokenAt(source, needle: string, language = langNim): SyntaxTokenClass =
  let
    index = source.find(needle)
    spans = synEditTokenSpans(source, language)
  check index >= 0
  spans.syntaxTokenAt(index)

suite "nimkit synedit views":
  test "tokenizer classifies Nim source spans":
    let source = """
proc answer*(): int =
  # comment
  0x2A + 3.5
""".strip()

    check source.tokenAt("proc") == stcKeyword
    check source.tokenAt("answer") == stcIdentifier
    check source.tokenAt("# comment") == stcComment
    check source.tokenAt("0x2A") == stcNumber
    check source.tokenAt("+") == stcOperator
    check source.tokenAt("3.5") == stcNumber

  test "gap buffer highlighter classifies additional source languages":
    check "int main() { return 0; }".tokenAt("int", langC) == stcKeyword
    check "def main():\n  return 1".tokenAt("def", langPython) == stcKeyword
    check "fn main() { let value = true; }".tokenAt("fn", langRust) == stcKeyword

  test "markdown fences highlight embedded source language":
    let source = """
```nim
proc answer(): int = 42
```
""".strip()

    check source.tokenAt("```", langMarkdown) == stcPunctuation
    check source.tokenAt("proc", langMarkdown) == stcKeyword

  test "widget installs embedded editor and line number gutter":
    let editor = newSynEditView("proc answer = 42\n", frame = rect(0, 0, 420, 220))

    check editor.textEditor() != nil
    check editor.textView() != nil
    check editor.scrollView() != nil
    check editor.gutterView() != nil
    check editor.scrollView().verticalHeaderView() == editor.gutterView()
    check editor.showLineNumbers()
    check editor.lineCount() == 2
    check editor.textEditor().textStorage().usesGapTextBuffer()
    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[stcKeyword]

  test "widget consumes a replaceable neutral syntax highlighter":
    var requestedLanguage = ""
    let highlighter: SyntaxHighlighter = proc(
        source, language: string
    ): seq[SyntaxTokenSpan] =
      requestedLanguage = language
      if source.len >= 3:
        result.add SyntaxTokenSpan(range: initTextRange(0, 3), tokenClass: stcKeyword)
    let editor = newSynEditView("abc value", syntaxHighlighter = highlighter)

    check requestedLanguage == "nim"
    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[stcKeyword]

    editor.syntaxHighlighter = nil
    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[stcOther]

  test "editing invalidates and reapplies only affected token lines":
    let
      source = "let first = 1\nlet second = 2\nlet third = 3\nlet fourth = 4\n"
      editor = newSynEditView(source)
      storage = editor.textEditor().textStorage()
      spy = HighlightEventSpy()
      insertion = source.find("2")

    storage.connect(storageAttributesDidChange, spy, rememberHighlightEdit)
    editor.textView().selectedRange = initTextRange(insertion, 0)
    editor.textView().insertTextValue("0")

    check editor.text() == source[0 ..< insertion] & "0" & source[insertion .. ^1]
    check spy.attributeRanges.len > 0
    check int(spy.attributeRanges[^1].location) == source.find("let second")
    check int(spy.attributeRanges[^1].length) < editor.text().runeLen
    check storage.attributesAt(insertion).foregroundColor ==
      editor.theme().foreground[stcNumber]
    check storage.attributesAt(editor.text().find("let fourth")).foregroundColor ==
      editor.theme().foreground[stcKeyword]

  test "widget keeps short lines fitted to gutter-adjusted viewport":
    let
      editor = newSynEditView("short\n".repeat(40), frame = rect(0, 0, 520, 120))
      scroll = editor.scrollView()

    editor.layoutSubtreeIfNeeded()

    check not scroll.verticalScrollerRect().isEmpty
    check scroll.horizontalScrollerRect().isEmpty
    check abs(scroll.maximumContentOffset().x) <= 0.001'f32

  test "widget restyles text replacements and language changes":
    let editor = newSynEditView("let value = 1")

    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[stcKeyword]

    editor.text = "echo \"merenda\""
    let quoteIndex = editor.text().find("\"")
    check quoteIndex >= 0
    check editor.textEditor().textStorage().attributesAt(quoteIndex).foregroundColor ==
      editor.theme().foreground[stcString]

    editor.language = langMarkdown
    editor.text = "# SynEdit"
    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[stcOther]

  test "line number visibility updates scroll view header":
    let editor = newSynEditView("one\ntwo\nthree")

    check editor.scrollView().verticalHeaderView() == editor.gutterView()
    editor.showLineNumbers = false
    check editor.scrollView().verticalHeaderView().isNil
    editor.showLineNumbers = true
    check editor.scrollView().verticalHeaderView() == editor.gutterView()
