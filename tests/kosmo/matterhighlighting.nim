## Matter highlighting in Kosmo editors and Markdown previews.
import std/[os, strutils, tempfiles, unicode, unittest]

import celina/core/colors as celinaColors

import merenda/kosmo/kosmo
import merenda/nimkit

proc runeIndexOf(source, needle: string): int =
  result = -1
  let byteIndex = source.find(needle)
  if byteIndex >= 0:
    result = source[0 ..< byteIndex].runeLen

proc renderedLocation(buffer: RenderBuffer, needle: string): tuple[column, row: int] =
  result = (column: -1, row: -1)
  for row in 0 ..< buffer.height:
    var line: string
    for column in 0 ..< buffer.width:
      line.add buffer.cell(column, row).symbol
    let column = line.find(needle)
    if column >= 0:
      return (column: column, row: row)

proc renderMoeFile(fileName, source: string): RenderBuffer =
  let
    root = createTempDir("kosmo-moe-matter-", "")
    path = root / fileName
  writeFile(path, source)
  defer:
    removeFile(path)
    removeDir(root)

  let editor = newKosmoEditor()
  defer:
    editor.close()
  doAssert editor.openFile(path).loaded
  result = newRenderBuffer(48, 8)
  editor.render(result)

template checkDistinctHighlight(fileName, source, firstNeedle, secondNeedle: string) =
  block:
    let
      buffer = renderMoeFile(fileName, source)
      first = buffer.renderedLocation(firstNeedle)
      second = buffer.renderedLocation(secondNeedle)
    require first.column >= 0
    require second.column >= 0
    check buffer.cell(first.column, first.row).style.fg !=
      buffer.cell(second.column, second.row).style.fg

suite "Kosmo Matter highlighting":
  test "Moe editors use Matter highlighting by default":
    let
      root = createTempDir("kosmo-moe-matter-", "")
      path = root / "matter-default.nim"
    writeFile(path, "proc answer = discard\nproc explicit() = discard\n")
    defer:
      removeFile(path)
      removeDir(root)

    let editor = newKosmoEditor()
    defer:
      editor.close()
    require editor.openFile(path).loaded

    var buffer = newRenderBuffer(32, 8)
    editor.render(buffer)
    let
      keyword = buffer.renderedLocation("proc")
      parameterless = buffer.renderedLocation("answer")
      explicit = buffer.renderedLocation("explicit")
    require keyword.column >= 0
    require parameterless.column >= 0
    require explicit.column >= 0
    check buffer.cell(parameterless.column, parameterless.row).style.fg ==
      buffer.cell(explicit.column, explicit.row).style.fg
    check buffer.cell(parameterless.column, parameterless.row).style.fg !=
      buffer.cell(keyword.column, keyword.row).style.fg

  test "Moe highlights JavaScript files":
    checkDistinctHighlight("matter.js", "const answer = \"kosmo\";\n", "const", "kosmo")

  test "Moe highlights Python files":
    checkDistinctHighlight(
      "matter.py", "def answer():\n  return \"kosmo\"\n", "def", "kosmo"
    )

  test "Moe highlights Terraform HCL files":
    checkDistinctHighlight(
      "matter.hcl", "resource \"thing\" \"example\" {\n  enabled = true\n}\n", "thing",
      "true",
    )

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
