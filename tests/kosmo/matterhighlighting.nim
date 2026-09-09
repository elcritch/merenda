## Matter highlighting in Kosmo editors and Markdown previews.
import std/[monotimes, os, strutils, tempfiles, unicode, unittest]

import celina/core/colors as celinaColors
import sigils/threads

import merenda/kosmo/kosmo
import merenda/kosmo/matterworkers
import merenda/nimkit
from merenda/nimkit/foundation/mainthreadwork import
  drainMainThreadWork, hasPendingMainThreadWork

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
    let column = line.runeIndexOf(needle)
    if column >= 0:
      return (column: column, row: row)

proc renderedLocation(
    view: nimkit.MonoTextView, needle: string
): tuple[column, row: int] =
  result = (column: -1, row: -1)
  for row in 0 ..< view.lineCount():
    var line: string
    for column in 0 ..< view.columnCount(row):
      line.add view.cellAt(row, column).text
    let column = line.runeIndexOf(needle)
    if column >= 0:
      return (column: column, row: row)

proc renderUntilMatterHighlightingReady(
    editor: KosmoEditor, buffer: var RenderBuffer
): bool =
  let deadline = getMonoTime() + initDuration(seconds = 60)
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

proc sourceLine(source, needle: string): int =
  let byteIndex = source.find(needle)
  doAssert byteIndex >= 0
  if byteIndex > 0:
    result = source[0 ..< byteIndex].count('\n')

proc renderMoeFileAcross(
    fileName, source: string, needles: openArray[string]
): seq[RenderCell] =
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

  var buffer = newRenderBuffer(96, 16)
  for needle in needles:
    doAssert editor.revealLocation(source.sourceLine(needle), 0, true)
    doAssert editor.renderUntilMatterHighlightingReady(buffer)
    let location = buffer.renderedLocation(needle)
    doAssert location.column >= 0
    result.add buffer.cell(location.column, location.row)

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
    let
      longHtml = "<div>" & "x".repeat(KosmoMatterMaximumLineBytes) & "</div>"
      source = "# Before\n" & longHtml & "\n# After\nNative Nim\n"
      buffer = renderMoeFile("matter.md", source, KosmoMatterMaximumLineBytes + 16, 8)
    let
      heading = buffer.renderedLocation("Before")
      body = buffer.renderedLocation("Native Nim")
      recovered = buffer.renderedLocation("After")
    require heading.column >= 0
    require body.column >= 0
    require recovered.column >= 0
    check buffer.cell(heading.column, heading.row).style.fg !=
      buffer.cell(body.column, body.row).style.fg
    check buffer.cell(recovered.column, recovered.row).style.fg !=
      buffer.cell(body.column, body.row).style.fg

  test "Moe resumes Markdown block highlighting after a list":
    let
      source =
        "# Before\n\n- first item\n- second item\n\n---\n\n## After list\nPlain body\n"
      buffer = renderMoeFile("matter.md", source, 48, 16)
      opening = buffer.renderedLocation("Before")
      closing = buffer.renderedLocation("After list")
      body = buffer.renderedLocation("Plain body")
    require opening.column >= 0
    require closing.column >= 0
    require body.column >= 0
    check buffer.cell(closing.column, closing.row).style.fg ==
      buffer.cell(opening.column, opening.row).style.fg
    check buffer.cell(closing.column, closing.row).style.fg !=
      buffer.cell(body.column, body.row).style.fg

  test "Moe preserves fenced Markdown backgrounds after Matter":
    let
      source = "# Heading\n```sh\necho $HOME\n```\n## After shell\nPlain body\n"
      buffer = renderMoeFile("matter.md", source, 48, 16)
      opening = buffer.renderedLocation("Heading")
      code = buffer.renderedLocation("echo $HOME")
      closing = buffer.renderedLocation("After shell")
      plain = buffer.renderedLocation("Plain body")
    require opening.column >= 0
    require code.column >= 0
    require closing.column >= 0
    require plain.column >= 0
    check buffer.cell(code.column, code.row).style.bg !=
      buffer.cell(plain.column, plain.row).style.bg
    check buffer.cell(buffer.width - 1, code.row).style.bg !=
      buffer.cell(buffer.width - 1, plain.row).style.bg
    check buffer.cell(closing.column, closing.row).style.fg ==
      buffer.cell(opening.column, opening.row).style.fg

  test "Markdown fence recovery matches the opening delimiter":
    let
      source = "# Before\n\n````text\n```\n~~~\n````\n## After fence\nPlain body\n"
      buffer = renderMoeFile("matter.md", source, 48, 16)
      opening = buffer.renderedLocation("Before")
      closing = buffer.renderedLocation("After fence")
      body = buffer.renderedLocation("Plain body")
    require opening.column >= 0
    require closing.column >= 0
    require body.column >= 0
    check buffer.cell(closing.column, closing.row).style.fg ==
      buffer.cell(opening.column, opening.row).style.fg
    check buffer.cell(closing.column, closing.row).style.fg !=
      buffer.cell(body.column, body.row).style.fg

  test "Moe completes Matter highlighting through the end of README":
    let
      source = readFile(RepositoryRoot / "README.md")
      rendered = renderMoeFileAcross(
        "README.md",
        source,
        [
          "## Why Try It?", "Native Nim", "## Install", "## Kosmo Install",
          "## Quick Start", "## Native Markdown Viewer", "## Cached URL Assets",
          "## Controls", "## Keyboard And Focus", "## Workspace And Services",
          "## Examples", "## Tests",
        ],
      )
    require rendered.len == 12
    for index in 2 ..< rendered.len:
      check rendered[index].style.fg != rendered[1].style.fg

  when KosmoMatterMaximumLineBytes > 128:
    test "Moe highlights the complete workflow YAML sequence":
      let source = readFile(RepositoryRoot / ".github/workflows/build-full.yml")
      let rendered = renderMoeFileAcross(
        "build-full.yml",
        source,
        ["on:", "jobs:", "runs-on:", "steps:", "uses:", "Compile Examples"],
      )
      require rendered.len == 6
      for index in 1 .. 4:
        check rendered[0].style.fg == rendered[index].style.fg
      check rendered[5].style.fg != rendered[0].style.fg

  test "Moe ends YAML block scalars on dedent":
    for indicator in [">-", "|", ">", "|+"]:
      let
        source =
          "jobs:\n  nimargs: " & indicator &
          "\n    --opt:none\n    -d:Example=96\n  # after scalar\n  steps:\n  - uses: actions/checkout@v5\n"
        rendered = renderMoeFileAcross(
          "build.yml", source, ["jobs:", "--opt:none", "steps:", "uses:"]
        )
      require rendered.len == 4
      check rendered[0].style.fg != rendered[1].style.fg
      check rendered[0].style.fg == rendered[2].style.fg
      check rendered[0].style.fg == rendered[3].style.fg

  test "Moe resumes YAML after dense GitHub Actions expressions":
    let
      source =
        "name: tests (${{ matrix.os }}, ${{ matrix.version }}, ${{ matrix.ui }})\n" &
        "timeout-minutes: 40\n" & "display: x11\n"
      rendered =
        renderMoeFileAcross("build.yml", source, ["name:", "timeout-minutes:", "x11"])
    require rendered.len == 3
    check rendered[1].style.fg != rendered[2].style.fg

  test "Moe resumes YAML after an over-limit mapping value":
    let
      source =
        "jobs:\n  steps:\n  - uses: action/example@v1\n" & "    key: " &
        "x".repeat(KosmoMatterMaximumLineBytes) &
        "\n\n  - name: After skipped value\n    timeout-minutes: 40\n"
      rendered = renderMoeFileAcross(
        "build.yml", source, ["After skipped value", "timeout-minutes:", "40"]
      )
    require rendered.len == 3
    check rendered[0].style.fg != rendered[1].style.fg
    check rendered[1].style.fg != rendered[2].style.fg

  test "Moe keeps Matter YAML highlighting after edit and save":
    let
      root = createTempDir("kosmo-moe-matter-", "")
      path = root / "build.yml"
      source = "jobs:\n  timeout-minutes: 40\n"
    writeFile(path, source)
    defer:
      removeFile(path)
      removeDir(root)

    let editor = newKosmoEditor()
    defer:
      editor.close()
    require editor.openFile(path).loaded

    var buffer = newRenderBuffer(48, 12)
    require editor.renderUntilMatterHighlightingReady(buffer)
    let initial = buffer.renderedLocation("jobs:")
    require initial.column >= 0
    let initialColor = buffer.cell(initial.column, initial.row).style.fg

    require editor.handleKey("i")
    require editor.handleTextInput("# touched\n")
    require editor.handleKey("Esc")
    require editor.renderUntilMatterHighlightingReady(buffer)
    let edited = buffer.renderedLocation("jobs:")
    require edited.column >= 0
    check buffer.cell(edited.column, edited.row).style.fg == initialColor

    require editor.save().saved
    require editor.renderUntilMatterHighlightingReady(buffer)
    let saved = buffer.renderedLocation("jobs:")
    require saved.column >= 0
    check buffer.cell(saved.column, saved.row).style.fg == initialColor

  test "Matter completion refreshes the retained editor grid":
    let
      root = createTempDir("kosmo-moe-matter-view-", "")
      path = root / "delayed.yml"
    writeFile(path, "jobs:\n  runs-on: ubuntu-latest\n")
    defer:
      removeFile(path)
      removeDir(root)

    discard drainMainThreadWork()
    let
      editor = newKosmoEditor()
      view = newKosmoEditorView(editor)
    defer:
      editor.close()
    view.frame = rect(0, 0, 640, 240)
    require view.openFile(path)

    let location = nimkit.MonoTextView(view).renderedLocation("jobs:")
    require location.column >= 0
    let sentinel = nimkit.initMonoTextCell(
      "!", foregroundColor = nimkit.color(1.0, 0.0, 1.0, 1.0), hasForegroundColor = true
    )
    view.setCell(location.row, location.column, sentinel)

    let deadline = getMonoTime() + initDuration(seconds = 5)
    while view.cellAt(location.row, location.column).text == "!" and
        getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      if hasPendingMainThreadWork():
        discard drainMainThreadWork()
      sleep(1)
    let refreshed = view.cellAt(location.row, location.column)
    require refreshed.text == "j"
    check refreshed.foregroundColor != sentinel.foregroundColor
    check editor.matterHighlightingReady()

  test "queued Matter refresh retains a released editor view":
    let
      root = createTempDir("kosmo-moe-matter-lifetime-", "")
      path = root / "released.yml"
    writeFile(path, "jobs:\n  runs-on: ubuntu-latest\n")
    defer:
      removeFile(path)
      removeDir(root)

    discard drainMainThreadWork()
    let editor = newKosmoEditor()
    defer:
      editor.close()
    var view = newKosmoEditorView(editor)
    view.frame = rect(0, 0, 640, 240)
    require view.openFile(path)

    let deadline = getMonoTime() + initDuration(seconds = 5)
    while not hasPendingMainThreadWork() and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(1)
    require hasPendingMainThreadWork()
    view = nil
    check drainMainThreadWork() > 0
    check editor.matterHighlightingReady()

  when KosmoMatterMaximumLineBytes > 128:
    test "Matter supplies fenced backgrounds before native parsing reaches EOF":
      let
        prefixLines = 2050
        source = "plain\n".repeat(prefixLines) & "```sh\necho ready\n```\nPlain tail\n"
        root = createTempDir("kosmo-moe-matter-large-", "")
        path = root / "large.md"
      writeFile(path, source)
      defer:
        removeFile(path)
        removeDir(root)

      let editor = newKosmoEditor()
      defer:
        editor.close()
      require editor.openFile(path).loaded
      var buffer = newRenderBuffer(48, 12)
      editor.render(buffer)

      let deadline = getMonoTime() + initDuration(seconds = 60)
      while not editor.matterHighlightingReady() and getMonoTime() < deadline:
        sleep(1)
      require editor.matterHighlightingReady()
      require editor.revealLocation(prefixLines + 1, 0, true)
      editor.render(buffer)
      let
        code = buffer.renderedLocation("echo ready")
        plain = buffer.renderedLocation("Plain tail")
      require code.column >= 0
      require plain.column >= 0
      check buffer.cell(buffer.width - 1, code.row).style.bg !=
        buffer.cell(buffer.width - 1, plain.row).style.bg

  test "Moe covers long UTF-8 lines and resumes Markdown highlighting":
    let
      longLine =
        "# " & "é".repeat(KosmoMatterMaximumLineBytes div "é".len + 1) & " END"
      buffer = renderMoeFile(
        "long.md", longLine & "\n# Recovered\nPlain body\n", longLine.runeLen + 8, 8
      )
      first = buffer.renderedLocation("é")
      last = buffer.renderedLocation("END")
      heading = buffer.renderedLocation("Recovered")
      body = buffer.renderedLocation("Plain body")
    require first.column >= 0
    require last.column >= 0
    require heading.column >= 0
    require body.column >= 0
    check buffer.cell(first.column, first.row).style.fg ==
      buffer.cell(body.column, body.row).style.fg
    check buffer.cell(last.column, last.row).style.fg ==
      buffer.cell(body.column, body.row).style.fg
    check buffer.cell(heading.column, heading.row).style.fg !=
      buffer.cell(body.column, body.row).style.fg

  test "Moe preserves fenced state across an over-limit line":
    let
      longCode = "x".repeat(KosmoMatterMaximumLineBytes + 1)
      source =
        "# Before\n```sh\n" & longCode & "\necho after\n```\n## After\nPlain body\n"
      buffer =
        renderMoeFile("long-fence.md", source, KosmoMatterMaximumLineBytes + 16, 12)
      before = buffer.renderedLocation("Before")
      longLine = buffer.renderedLocation(longCode)
      code = buffer.renderedLocation("echo after")
      after = buffer.renderedLocation("After")
      body = buffer.renderedLocation("Plain body")
    require before.column >= 0
    require longLine.column >= 0
    require code.column >= 0
    require after.column >= 0
    require body.column >= 0
    check buffer.cell(buffer.width - 1, longLine.row).style.bg !=
      buffer.cell(buffer.width - 1, body.row).style.bg
    check buffer.cell(buffer.width - 1, code.row).style.bg !=
      buffer.cell(buffer.width - 1, body.row).style.bg
    check buffer.cell(after.column, after.row).style.fg ==
      buffer.cell(before.column, before.row).style.fg
    check buffer.cell(after.column, after.row).style.fg !=
      buffer.cell(body.column, body.row).style.fg

  test "queued Matter refresh is cancelled when a workspace closes":
    let
      root = createTempDir("kosmo-moe-matter-close-", "")
      path = root / "closing.yml"
      frontend = newKosmoApplication(
        newApplication("Kosmo Matter Close Test"), root, monitorsGitStatus = false
      )
      view = frontend.editorView
    writeFile(path, "jobs:\n  runs-on: ubuntu-latest\n")
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)

    discard drainMainThreadWork()
    view.frame = rect(0, 0, 640, 240)
    require view.openFile(path)
    let location = nimkit.MonoTextView(view).renderedLocation("jobs:")
    require location.column >= 0

    let deadline = getMonoTime() + initDuration(seconds = 5)
    while not hasPendingMainThreadWork() and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(1)
    require hasPendingMainThreadWork()

    let sentinel = nimkit.initMonoTextCell(
      "!", foregroundColor = nimkit.color(1.0, 0.0, 1.0, 1.0), hasForegroundColor = true
    )
    view.setCell(location.row, location.column, sentinel)
    frontend.close()
    check drainMainThreadWork() > 0
    check view.cellAt(location.row, location.column).text == "!"

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
