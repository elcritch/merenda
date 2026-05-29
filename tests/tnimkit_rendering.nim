import std/unittest

import figdraw/fignodes

import knutella/nimkit

suite "nimkit rendering":
  test "buildRenders emits root, text field, and button nodes":
    let root = newView(0, 0, 320, 200)
    root.setBackgroundColor(initColor(1, 1, 1))
    root.addSubview(newTextField(16, 16, 180, 32, "Ready"))
    root.addSubview(newButton(16, 64, 120, 36, "Click"))

    let renders = buildRenders(root)

    check 0.ZLevel in renders
    let list = renders[0.ZLevel]
    check list.rootIds.len >= 1
    check list.nodes.len >= 5

    var textNodeCount = 0
    var rectangleNodeCount = 0
    for node in list.nodes:
      case node.kind
      of nkText:
        inc textNodeCount
      of nkRectangle:
        inc rectangleNodeCount
      else:
        discard

    check textNodeCount >= 2
    check rectangleNodeCount >= 3

  test "buildRenders uses FigDraw hierarchy and clears invalid state":
    let
      root = newView(0, 0, 200, 160)
      child = newView(20, 30, 80, 50)

    root.addSubview(child)
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)
    child.setNeedsDisplayInRect(initRect(5, 6, 10, 11))

    let renders = buildRenders(root)
    let list = renders[0.ZLevel]

    check list.rootIds.len == 1
    check NfClipContent in list.nodes[int(list.rootIds[0])].flags

    var childNodeCount = 0
    for node in list.nodes:
      if node.parent != (-1).FigIdx:
        inc childNodeCount
    check childNodeCount > 0
    check not root.needsDisplay
    check root.invalidRects.len == 0
    check not child.needsDisplay
    check child.invalidRects.len == 0

  test "buildRenders leaves child overflow to FigDraw clipping":
    let
      root = newView(0, 0, 100, 80)
      child = newView(90, 90, 50, 40)

    root.setBounds(initRect(10, 20, 100, 80))
    root.addSubview(child)

    let renders = buildRenders(root)
    let list = renders[0.ZLevel]
    let rootIdx = list.rootIds[0]

    check list.nodes[int(rootIdx)].screenBox.x == 0.0
    check list.nodes[int(rootIdx)].screenBox.y == 0.0
    check list.nodes[int(rootIdx)].screenBox.w == 100.0
    check list.nodes[int(rootIdx)].screenBox.h == 80.0
    check NfClipContent in list.nodes[int(rootIdx)].flags

    var childIdx = (-1).FigIdx
    for idx in childIndex(list.nodes, rootIdx):
      childIdx = idx

    check childIdx != (-1).FigIdx
    check list.nodes[int(childIdx)].parent == rootIdx
    check list.nodes[int(childIdx)].screenBox.x == 80.0
    check list.nodes[int(childIdx)].screenBox.y == 70.0
    check list.nodes[int(childIdx)].screenBox.w == 50.0
    check list.nodes[int(childIdx)].screenBox.h == 40.0
    check NfClipContent in list.nodes[int(childIdx)].flags
