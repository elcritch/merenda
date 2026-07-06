import std/[strutils, unittest]

import merenda/nimkit
import merenda/nimkit/text/syneditviews

proc tokenAt(source, needle: string, language = langNim): SynEditTokenClass =
  let
    index = source.find(needle)
    spans = synEditTokenSpans(source, language)
  check index >= 0
  spans.synEditTokenAt(index)

suite "nimkit synedit views":
  test "tokenizer classifies Nim source spans":
    let source = """
proc answer*(): int =
  # comment
  0x2A + 3.5
""".strip()

    check source.tokenAt("proc") == SynEditTokenClass.Keyword
    check source.tokenAt("answer") == SynEditTokenClass.Identifier
    check source.tokenAt("# comment") == SynEditTokenClass.Comment
    check source.tokenAt("0x2A") == SynEditTokenClass.HexNumber
    check source.tokenAt("+") == SynEditTokenClass.Operator
    check source.tokenAt("3.5") == SynEditTokenClass.FloatNumber

  test "gap buffer highlighter classifies additional source languages":
    check "int main() { return 0; }".tokenAt("int", langC) == SynEditTokenClass.Keyword
    check "def main():\n  return 1".tokenAt("def", langPython) ==
      SynEditTokenClass.Keyword
    check "fn main() { let value = true; }".tokenAt("fn", langRust) ==
      SynEditTokenClass.Keyword

  test "markdown fences highlight embedded source language":
    let source = """
```nim
proc answer(): int = 42
```
""".strip()

    check source.tokenAt("```", langMarkdown) == SynEditTokenClass.MarkdownFence
    check source.tokenAt("proc", langMarkdown) == SynEditTokenClass.Keyword

  test "widget installs embedded editor and line number gutter":
    let editor = newSynEditView("proc answer = 42\n", frame = rect(0, 0, 420, 220))

    check editor.textEditor() != nil
    check editor.textView() != nil
    check editor.scrollView() != nil
    check editor.gutterView() != nil
    check editor.scrollView().verticalHeaderView() == editor.gutterView()
    check editor.showLineNumbers()
    check editor.lineCount() == 2
    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[SynEditTokenClass.Keyword]

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
      editor.theme().foreground[SynEditTokenClass.Keyword]

    editor.text = "echo \"merenda\""
    let quoteIndex = editor.text().find("\"")
    check quoteIndex >= 0
    check editor.textEditor().textStorage().attributesAt(quoteIndex).foregroundColor ==
      editor.theme().foreground[SynEditTokenClass.StringLit]

    editor.language = langMarkdown
    editor.text = "# SynEdit"
    check editor.textEditor().textStorage().attributesAt(0).foregroundColor ==
      editor.theme().foreground[SynEditTokenClass.Text]

  test "line number visibility updates scroll view header":
    let editor = newSynEditView("one\ntwo\nthree")

    check editor.scrollView().verticalHeaderView() == editor.gutterView()
    editor.showLineNumbers = false
    check editor.scrollView().verticalHeaderView().isNil
    editor.showLineNumbers = true
    check editor.scrollView().verticalHeaderView() == editor.gutterView()
