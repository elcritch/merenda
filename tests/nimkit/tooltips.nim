import std/[times, unicode, unittest]

import figdraw

import merenda/nimkit

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

proc layerContainsText(renders: Renders, level: ZLevel, text: string): bool =
  if level notin renders.layers:
    return
  for node in renders[level].nodes:
    if node.kind == nkText and node.renderedText() == text:
      return true

suite "NimKit tooltips":
  test "tooltip style follows the active popup palette":
    var appearance = initAppearance()
    let
      surface = fill(color(0.18, 0.32, 0.46, 0.94))
      border = color(0.52, 0.68, 0.84, 0.88)
      textColor = color(0.92, 0.96, 1.0, 1.0)

    var builder = initThemeBuilder(appearance.theme)
    builder["comboBox.item.fill"] = surface
    builder["comboBox.border.color"] = border
    builder["comboBox.item.text.color"] = textColor
    appearance.theme = builder.finish()

    let style = appearance.resolveTooltipStyle()
    check style.box.fill == surface
    check style.box.borderColor == border
    check style.text.color == textColor

  test "hover shows a passive tooltip after the delay":
    let
      window = newWindow("Tooltips", frame = rect(0, 0, 220, 120))
      root = newView()
      button = newButton("Hover", frame = rect(20, 20, 80, 24))
      tip = "A helpful tooltip"

    button.toolTip = tip
    root.addSubview(button)
    window.setContentView(root)

    let hoverPoint = button.pointToWindow(initPoint(8, 8))
    discard window.mouseMovedAt(hoverPoint)
    discard window.animationScheduler().tick(initDuration(milliseconds = 499))
    check TooltipDrawLevel notin window.buildRenders().layers

    discard window.animationScheduler().tick(initDuration(milliseconds = 1))
    let renders = window.buildRenders()
    check TooltipDrawLevel in renders.layers
    check renders.layerContainsText(TooltipDrawLevel, tip)

    var bubbleFound = false
    for node in renders[TooltipDrawLevel].nodes:
      if node.kind == nkRectangle and node.screenBox.w > 0.0'f32 and
          node.screenBox.w < root.bounds().size.width:
        bubbleFound = true
        check node.screenBox.x >= 0.0'f32
        check node.screenBox.y >= 0.0'f32
        check node.screenBox.x + node.screenBox.w <= root.bounds().size.width
        check node.screenBox.y + node.screenBox.h <= root.bounds().size.height
    check bubbleFound
    check window.mouseDownAt(hoverPoint)
    check window.mouseUpAt(hoverPoint)
    check TooltipDrawLevel notin window.buildRenders().layers
    discard window.drainAnimations()

  test "ancestor tooltips cancel on exit and dismiss on mouse down":
    let
      window = newWindow("Tooltip dismissal", frame = rect(0, 0, 240, 140))
      root = newView()
      container = newView(frame = rect(20, 20, 100, 50))
      child = newView(frame = rect(5, 5, 40, 20))
      tip = "Inherited help"

    container.toolTip = tip
    container.addSubview(child)
    root.addSubview(container)
    window.setContentView(root)

    let hoverPoint = child.pointToWindow(initPoint(4, 4))
    discard window.mouseMovedAt(hoverPoint)
    discard window.mouseMovedAt(initPoint(200, 100))
    discard window.animationScheduler().tick(initDuration(milliseconds = 500))
    check TooltipDrawLevel notin window.buildRenders().layers

    discard window.mouseMovedAt(hoverPoint)
    discard window.animationScheduler().tick(initDuration(milliseconds = 500))
    check window.buildRenders().layerContainsText(TooltipDrawLevel, tip)

    discard window.mouseDownAt(hoverPoint)
    check TooltipDrawLevel notin window.buildRenders().layers
    check root.subviews().len == 1
    discard window.drainAnimations()
