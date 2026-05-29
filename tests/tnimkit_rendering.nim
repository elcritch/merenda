import std/unittest

import figdraw/fignodes

import knutella/nimkit
import knutella/nimkit/types as nimkitTypes

type CustomDrawView = ref object of View

var customDrawCount: int

protocol CustomDrawing of ViewDrawingProtocol:
  method draw(view: CustomDrawView, context: DrawContext) =
    inc customDrawCount
    context.addRectangle(initRect(4, 5, 20, 10), initColor(0.8, 0.1, 0.1))
    context.addText(initRect(4, 5, 20, 10), "C", initColor(1, 1, 1))

proc newCustomDrawView(frame: nimkitTypes.Rect): CustomDrawView =
  result = CustomDrawView()
  initViewFields(result, frame)
  discard result.withProtocol(CustomDrawing)

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

  test "buildRenders uses theme colors and metrics for built-in controls":
    let
      root = newView(0, 0, 180, 120)
      field = newTextField(10, 20, 100, 30, "Field")
      button = newButton(10, 60, 80, 24, "Button")

    var theme = initTheme()
    theme.button.fill[tcsNormal] = initColor(0.31, 0.42, 0.53, 1.0)
    theme.button.borderColor[tcsNormal] = initColor(0.11, 0.12, 0.13, 1.0)
    theme.button.borderWidth = 3.0
    theme.button.cornerRadius = 6.0
    theme.button.contentInsets = initEdgeInsets(1.0, 9.0)
    theme.textField.fill = initColor(0.91, 0.92, 0.93, 1.0)
    theme.textField.borderColor = initColor(0.21, 0.22, 0.23, 1.0)
    theme.textField.borderWidth = 2.0
    theme.textField.cornerRadius = 5.0
    theme.textField.textInsets = initEdgeInsets(2.0, 7.0)

    root.addSubview(field)
    root.addSubview(button)

    let renders = buildRenders(root, theme)
    let list = renders[0.ZLevel]

    var
      themedButtonFound = false
      themedTextFieldFound = false
      buttonTextBoxFound = false
      fieldTextBoxFound = false

    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == theme.button.fill[tcsNormal].rgba:
        themedButtonFound = true
        check node.stroke.weight == theme.button.borderWidth
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == theme.button.borderColor[tcsNormal].rgba
        check node.corners[dcTopLeft] == 6'u16

      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == theme.textField.fill.rgba:
        themedTextFieldFound = true
        check node.stroke.weight == theme.textField.borderWidth
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == theme.textField.borderColor.rgba
        check node.corners[dcTopLeft] == 5'u16

      if node.kind == nkText and node.screenBox.x == 19.0 and node.screenBox.y == 61.0 and
          node.screenBox.w == 62.0 and node.screenBox.h == 22.0:
        buttonTextBoxFound = true

      if node.kind == nkText and node.screenBox.x == 17.0 and node.screenBox.y == 22.0 and
          node.screenBox.w == 86.0 and node.screenBox.h == 26.0:
        fieldTextBoxFound = true

    check themedButtonFound
    check themedTextFieldFound
    check buttonTextBoxFound
    check fieldTextBoxFound

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

  test "buildRenders calls selector-backed custom drawing":
    let
      root = newView(0, 0, 100, 80)
      custom = newCustomDrawView(initRect(10, 20, 50, 40))

    customDrawCount = 0
    root.addSubview(custom)

    let renders = buildRenders(root)
    let list = renders[0.ZLevel]

    check customDrawCount == 1

    var customRoot = (-1).FigIdx
    for idx in childIndex(list.nodes, list.rootIds[0]):
      if list.nodes[int(idx)].screenBox.x == 10.0 and
          list.nodes[int(idx)].screenBox.y == 20.0:
        customRoot = idx

    check customRoot != (-1).FigIdx

    var customRectFound = false
    var customTextFound = false
    for idx in childIndex(list.nodes, customRoot):
      let node = list.nodes[int(idx)]
      if node.kind == nkRectangle and node.screenBox.x == 14.0 and
          node.screenBox.y == 25.0 and node.screenBox.w == 20.0 and
          node.screenBox.h == 10.0:
        customRectFound = true
      if node.kind == nkText and node.screenBox.x == 14.0 and node.screenBox.y == 25.0 and
          node.screenBox.w == 20.0 and node.screenBox.h == 10.0:
        customTextFound = true

    check customRectFound
    check customTextFound
