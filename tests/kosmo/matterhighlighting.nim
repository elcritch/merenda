## Matter highlighting in Kosmo editors and Markdown previews.
import std/[monotimes, os, strutils, tempfiles, unicode, unittest]

import celina/core/colors as celinaColors

import merenda/kosmo/kosmo
import merenda/nimkit

const RepositoryRoot = currentSourcePath().parentDir.parentDir.parentDir

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

proc renderUntilMatterHighlightingReady(
    editor: KosmoEditor, buffer: var RenderBuffer
): bool =
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while not editor.matterHighlightingReady() and getMonoTime() < deadline:
    editor.render(buffer)
    sleep(1)
  editor.render(buffer)
  editor.matterHighlightingReady()

proc renderMoeFile(fileName, source: string, width = 48, height = 16): RenderBuffer =
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
  result = newRenderBuffer(width, height)
  doAssert editor.renderUntilMatterHighlightingReady(result)

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
    require editor.renderUntilMatterHighlightingReady(buffer)
    let
      keyword = buffer.renderedLocation("proc")
      parameterless = buffer.renderedLocation("answer")
      explicit = buffer.renderedLocation("explicit")
    require keyword.column >= 0
    require parameterless.column >= 0
    require explicit.column >= 0
    check buffer.cell(keyword.column, keyword.row).style.fg.kind == celinaColors.Rgb
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
      "root.hcl",
      "# =============================================================================\n" &
        "# Root Terragrunt Configuration\n" &
        "# =============================================================================\n" &
        "# This is the root terragrunt.hcl that all environments include.\n" &
        "# It defines the common S3 backend pattern and generates the AWS provider block.\n" &
        "\n" & "terragrunt_version_constraint = \">= 1.1.2, < 2.0.0\"\n",
      "Root",
      "1.1.2",
    )

  test "Moe highlights Markdown headings and inline code":
    checkDistinctHighlight(
      "matter.md", "# Matter heading\nUse `kosmo` here.\n", "Matter heading", "Use"
    )
    checkDistinctHighlight(
      "matter.md", "# Matter heading\nUse `kosmo` here.\n", "Use", "kosmo"
    )

  test "Moe keeps Markdown highlighting after a long HTML line":
    let buffer =
      renderMoeFile("README.md", readFile(RepositoryRoot / "README.md"), 1024, 32)
    let heading = buffer.renderedLocation("Why Try It?")
    let body = buffer.renderedLocation("Native Nim")
    require heading.column >= 0
    require body.column >= 0
    check buffer.cell(heading.column, heading.row).style.fg !=
      buffer.cell(body.column, body.row).style.fg

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
