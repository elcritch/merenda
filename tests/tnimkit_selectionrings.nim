import std/unittest

import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type RingDrawView = ref object of View

var ringDrawCount: int

protocol RingBaseDrawing of ViewDrawingProtocol:
  method draw(view: RingDrawView, context: DrawContext) =
    inc ringDrawCount
    context.addRectangle(initRect(4, 5, 20, 10), initColor(0.8, 0.1, 0.1))

proc newRingDrawView(frame: nimkitTypes.Rect): RingDrawView =
  result = RingDrawView()
  initViewFields(result, frame)
  discard result.withProtocol(RingBaseDrawing)

proc childRootFor(list: RenderList, frame: nimkitTypes.Rect): FigIdx =
  for idx in childIndex(list.nodes, list.rootIds[0]):
    let node = list.nodes[int(idx)]
    if node.screenBox.x == frame.origin.x and node.screenBox.y == frame.origin.y and
        node.screenBox.w == frame.size.width and node.screenBox.h == frame.size.height:
      return idx
  (-1).FigIdx

proc containsBaseDraw(list: RenderList, rootIdx: FigIdx): bool =
  for idx in childIndex(list.nodes, rootIdx):
    let node = list.nodes[int(idx)]
    if node.kind == nkRectangle and node.screenBox.x == 14.0 and node.screenBox.y == 25.0 and
        node.screenBox.w == 20.0 and node.screenBox.h == 10.0:
      return true

proc containsSelectionRing(
    list: RenderList, rootIdx: FigIdx, strokeColor: nimkitTypes.Color
): bool =
  for idx in childIndex(list.nodes, rootIdx):
    let node = list.nodes[int(idx)]
    if node.kind == nkRectangle and node.screenBox.x == 12.0 and node.screenBox.y == 22.0 and
        node.screenBox.w == 46.0 and node.screenBox.h == 36.0 and
        node.stroke.weight == 5.0 and node.stroke.fill.kind == flColor and
        node.stroke.fill.color == strokeColor.rgba:
      return true

suite "nimkit selection rings":
  test "selection ring wraps existing draw method and can uninstall":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      selected = newRingDrawView(initRect(10, 20, 50, 40))
      strokeColor = initColor(0.9, 0.15, 0.2, 1.0)
      style = initSelectionRingStyle(
        strokeColor = strokeColor,
        lineWidth = 5.0,
        cornerRadius = 6.0,
        insets = insets(2.0),
      )

    root.addSubview(selected)

    var ring = installSelectionRing(selected, style)
    check ring.installed
    check ring.view == selected
    check DynamicAgent(selected).methodStack(draw()).len == 2

    ringDrawCount = 0
    let
      ringRenders = buildRenders(root)
      ringList = ringRenders[DefaultDrawLevel]
      ringRoot = ringList.childRootFor(selected.frame)

    check ringDrawCount == 1
    check ringRoot != (-1).FigIdx
    check ringList.containsBaseDraw(ringRoot)
    check ringList.containsSelectionRing(ringRoot, strokeColor)

    check ring.uninstall()
    check not ring.installed
    check ring.view.isNil
    check DynamicAgent(selected).methodStack(draw()).len == 1

    ringDrawCount = 0
    let
      cleanRenders = buildRenders(root)
      cleanList = cleanRenders[DefaultDrawLevel]
      cleanRoot = cleanList.childRootFor(selected.frame)

    check ringDrawCount == 1
    check cleanRoot != (-1).FigIdx
    check cleanList.containsBaseDraw(cleanRoot)
    check not cleanList.containsSelectionRing(cleanRoot, strokeColor)
