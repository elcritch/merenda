## Matter highlighting in Kosmo Markdown previews.
import std/[strutils, unicode, unittest]

import merenda/kosmo/kosmo
import merenda/nimkit

proc runeIndexOf(source, needle: string): int =
  result = -1
  let byteIndex = source.find(needle)
  if byteIndex >= 0:
    result = source[0 ..< byteIndex].runeLen

suite "Kosmo Matter highlighting":
  test "Markdown previews use Matter for fenced code":
    let frontend = newKosmoApplication(
      newApplication("Kosmo Matter Highlighting Test"), monitorsGitStatus = false
    )
    defer:
      frontend.close()

    let preview = frontend.editorPane.markdownView
    preview.markdown = "```go\nfunc main() {}\n```"
    require preview.waitForMarkdownParsing()
    require preview.waitForMarkdownRendering()
    let funcIndex = preview.textStorage().stringValue().runeIndexOf("func")
    require funcIndex >= 0
    check preview.textStorage().attributesAt(funcIndex).foregroundColor ==
      preview.markdownStyle().syntaxTokenColors[stcKeyword]
