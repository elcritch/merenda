import std/[os, strutils, tempfiles, unicode, unittest]

import figdraw

import merenda/nimkit
import merenda/kosmo/kosmo

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

proc renderedTextStartingWith(view: View, prefix: string): string =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText:
      let text = node.renderedText()
      if text.startsWith(prefix):
        return text

proc rendersFill(view: View, fillValue: Fill): bool =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkRectangle and node.fill == fillValue:
      return true

proc rendersTextWithColor(view: View, text: string, textColor: Color): bool =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText and node.renderedText() == text:
      for spanColor in node.textLayout.spanColors:
        if spanColor.kind == flColor and spanColor.color == textColor.rgba:
          return true

suite "Kosmo file tree interactions":
  test "Git status refresh redraws retained file rows":
    let
      root = createTempDir("merenda-kosmo-tree-git-redraw-", "")
      ignoredPath = root / "ignored.log"
      ignoredColor = color(0.50, 0.52, 0.56, 0.72)
    writeFile(ignoredPath, "ignored")
    let tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
    defer:
      removeFile(ignoredPath)
      removeDir(root)

    discard buildRenders(tree)
    check not tree.rendersTextWithColor("ignored.log", ignoredColor)

    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: absolutePath(root),
        isRepository: true,
        entries: @[GitStatusEntry(path: ignoredPath, state: gfsIgnored)],
      )
    )

    check tree.rendersTextWithColor("ignored.log", ignoredColor)

  test "hover input redraws the highlighted row":
    let
      root = createTempDir("merenda-kosmo-tree-hover-", "")
      filePath = root / "hover-target.txt"
    writeFile(filePath, "hover target")
    defer:
      removeFile(filePath)
      removeDir(root)

    let
      window = newWindow("Kosmo File Tree Hover", frame = rect(0, 0, 300, 120))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
      hoverFill = fill(color(0.91, 0.23, 0.67, 1.0))
    var appearance = initAppearance()
    appearance[srRowItem, {ssHovered}, StyleFill] = hoverFill
    tree.appearance = appearance
    window.setContentView(tree)
    discard buildRenders(tree)

    let
      row = tree.rowForItem(filePath)
      rowRect = tree.rowItemRect(row)
      point = tree.pointToWindow(
        initPoint(rowRect.origin.x + 40.0'f32, rowRect.origin.y + 12.0'f32)
      )
    check not tree.rendersFill(hoverFill)
    check window.mouseMovedAt(point)
    check tree.highlightedIndex() == row
    check tree.rendersFill(hoverFill)

  test "wheel input lazily renders newly visible rows":
    let root = createTempDir("merenda-kosmo-tree-scroll-", "")
    var paths: seq[string]
    for index in 0 ..< 12:
      let path = root / align($index, 2, '0') & "-row.txt"
      writeFile(path, "row " & $index)
      paths.add path
    defer:
      for path in paths:
        removeFile(path)
      removeDir(root)

    let
      window = newWindow("Kosmo File Tree Scroll", frame = rect(0, 0, 300, 74))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 74))
    window.setContentView(tree)

    check tree.renderedTextStartingWith("00-row") == "00-row.txt"
    check window.scrollWheelAt(
      tree.pointToWindow(initPoint(40.0'f32, 40.0'f32)), deltaY = -3.0'f32
    )
    check tree.firstVisibleIndex() == 3
    check tree.renderedTextStartingWith("02-row") == "02-row.txt"
    check tree.renderedTextStartingWith("00-row").len == 0
