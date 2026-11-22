## FigDraw SVG integration with NimKit's drawing context.
import std/unittest

import figdraw
import merenda/nimkit

const FilledPath = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 30">
  <path d="M4 4 L36 4 L20 26 Z" fill="#cc7226"/>
</svg>
"""

suite "SVG drawing resources":
  test "draws FigDraw SVGs beneath the current parent and applies a tint":
    let
      resource = newSvgMtsdfResource(FilledPath)
      context = initDrawContext()
      layer = PopupDrawLevel
      parent = context.addFig(layer, FigIdx(-1), Fig(kind: nkRectangle))
      bounds = rect(0, 0, 100, 80)
      tint = fill(rgba(51, 128, 230, 255))
    context.beginDraw(
      parent, parent, initPoint(10, 20), bounds, bounds, initAppearance(), layer
    )

    let
      target = rect(0, 0, 80, 60)
      sourceIndex = context.addSvgMtsdf(target, resource)
      tintIndex = context.addSvgMtsdf(target, resource, tint)
      nodes = context.renders[layer].nodes
    require sourceIndex.int == 1
    require tintIndex.int == 2
    for index in [sourceIndex.int, tintIndex.int]:
      check nodes[index].parent == parent
      check nodes[index].zlevel == layer
      require nodes[index].kind == nkMtsdfImage
      check nodes[index].mtsdfImage.id == resource.image().id
    check nodes[sourceIndex.int].mtsdfImage.fill.color == rgba(204, 114, 38, 255)
    check nodes[tintIndex.int].mtsdfImage.fill == tint
    check nodes[sourceIndex.int].screenBox.x == 10 + resource.layers[0].frame.x * 2
    check nodes[sourceIndex.int].screenBox.y == 20 + resource.layers[0].frame.y * 2
    check context.resources.imageCount == 1

  test "retains only the raster images emitted by FigDraw":
    var
      context = initDrawContext()
      renderedId, unusedId: ImageId
    block:
      let raster = newSvgMtsdfResource(FilledPath, renderMode = srmRaster)
      require raster.layers.len == 1
      require raster.layers[0].kind == slkRasterGroup
      let index =
        context.addSvgMtsdf(rect(0, 0, 80, 60), raster, fill(rgba(0, 0, 255, 255)))
      require index.int == 0
      let node = context.renderList.nodes[index.int]
      require node.kind == nkImage
      renderedId = node.image.id
      unusedId = raster.layers[0].rasterImage.id
      check renderedId == raster.layers[0].tintImage.id

    check context.resources.imageCount == 1
    check context.resources.containsImage(renderedId)
    check hasImage(renderedId)
    check not hasImage(unusedId)
    context = nil
    check not hasImage(renderedId)
