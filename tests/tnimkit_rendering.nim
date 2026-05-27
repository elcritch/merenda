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
