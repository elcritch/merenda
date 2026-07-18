import std/unittest

import figdraw
import merenda/nimkit

suite "SVG drawing resources":
  test "generates a compact MTSDF from a visible transformed fill":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0.5 0.5 100.0 50.0">
  <path d="M0 0 H100 V50 H0 Z" transform="translate(2 3)"/>
  <path d="M10 10 H20 V20 H10 Z" opacity="0"/>
</svg>
""",
      name = "svg-mtsdf-test",
      longEdge = 64,
      minimumShortEdge = 16,
      pixelRange = 4.0,
    )

    check resource.size == initSize(100.0, 50.0)
    check resource.layers.len == 1
    check resource.layers[0].kind == slkMtsdfFill
    check resource.image != nil
    check resource.image.name == "svg-mtsdf-test"
    check resource.image.size.width <= 64.0
    check resource.image.size.height == 32.0
    check resource.elementCount == 1
    check abs(resource.pixelRange - 4.0'f32) < 0.001'f32

    let context = initDrawContext()
    let imageIndex = context.addSvgMtsdf(
      DefaultDrawLevel,
      FigIdx(-1),
      rect(0.0, 0.0, 128.0, 64.0),
      resource,
      fill(color(0.2, 0.5, 0.9, 1.0)),
    )
    check imageIndex.int >= 0
    check context.resources.imageCount == 1

  test "keeps independently filled elements in separate MTSDF layers":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50">
  <path d="M0 5 H20 V25 H0 Z"/>
  <path d="M70 25 H90 V45 H70 Z"/>
</svg>
""",
      name = "separate-fills",
      longEdge = 64,
      minimumShortEdge = 16,
      pixelRange = 4.0,
    )

    check resource.layers.len == 2
    check resource.layers[0].kind == slkMtsdfFill
    check resource.layers[1].kind == slkMtsdfFill
    check resource.layers[0].image.name == "separate-fills:0"
    check resource.layers[1].image.name == "separate-fills:1"
    check resource.layers[0].frame.origin.x < resource.layers[1].frame.origin.x
    check resource.layers[0].frame.origin.y < resource.layers[1].frame.origin.y

    let context = initDrawContext()
    discard context.addSvgMtsdf(
      DefaultDrawLevel,
      FigIdx(-1),
      rect(0.0, 0.0, 200.0, 100.0),
      resource,
      fill(color(0.2, 0.5, 0.9, 1.0)),
    )
    check context.resources.imageCount == 2

  test "preserves inherited source paints while retaining tint overrides":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 30">
  <g fill="#cc7226" stroke="#102030" stroke-width="2">
    <path d="M4 4 H36 V26 H4 Z" fill-opacity="0.5"/>
  </g>
</svg>
""",
      longEdge = 48,
      minimumShortEdge = 24,
      pixelRange = 4.0,
    )

    check resource.layers.len == 2
    check resource.layers[0].kind == slkMtsdfFill
    check resource.layers[0].paint.rgba == rgba(204, 114, 38, 128)
    check resource.layers[1].kind == slkStrokePath
    check resource.layers[1].paint.rgba == rgba(16, 32, 48, 255)

    let sourceContext = initDrawContext()
    discard sourceContext.addSvgMtsdf(
      DefaultDrawLevel, FigIdx(-1), rect(0.0, 0.0, 80.0, 60.0), resource
    )
    check sourceContext.renderList.nodes.len == 2
    check sourceContext.renderList.nodes[0].mtsdfImage.fill.color ==
      rgba(204, 114, 38, 128)
    check sourceContext.renderList.nodes[1].drawStroke.fill.color ==
      rgba(16, 32, 48, 255)

    let
      tintContext = initDrawContext()
      tint = color(0.2, 0.5, 0.9, 1.0)
    discard tintContext.addSvgMtsdf(
      DefaultDrawLevel, FigIdx(-1), rect(0.0, 0.0, 80.0, 60.0), resource, fill(tint)
    )
    check tintContext.renderList.nodes[0].mtsdfImage.fill.color == tint.rgba
    check tintContext.renderList.nodes[1].drawStroke.fill.color == tint.rgba

  test "ignores zero-area fills":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 30">
  <path d="M4 4 H20"/>
  <path d="M4 8 H36 V26 H4 Z" fill="#cc7226"/>
</svg>
""",
      name = "nondegenerate-fill",
      longEdge = 48,
      minimumShortEdge = 24,
      pixelRange = 4.0,
    )

    check resource.elementCount == 1
    check resource.layers.len == 1
    check resource.image.name == "nondegenerate-fill"

  test "keeps compact field padding outside complex SVG fills":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="50 90 80 120">
  <path d="m65.8 102s17.698 26.82 17.1 31.6c-1.3 10.4-1.5 20 1.7 24
    3.201 4 12.001 37.2 12.001 37.2s-.4 1.2 11.999-36.8c0 0 11.6-16-8.4-34.4
    0 0-35.2-28.8-34.4-21.6z" fill="#ccc"/>
</svg>
""",
      longEdge = 64,
      minimumShortEdge = 24,
      pixelRange = 4.0,
    )
    let pixels = resource.image.pixels()

    for x in 0 ..< pixels.width:
      check pixels.data[x].a < 128
      check pixels.data[(pixels.height - 1) * pixels.width + x].a < 128
    for y in 0 ..< pixels.height:
      check pixels.data[y * pixels.width].a < 128
      check pixels.data[y * pixels.width + pixels.width - 1].a < 128

  test "uses vector strokes but MTSDFs for ellipses":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
  <line x1="5" y1="10" x2="40" y2="30" stroke="black" stroke-width="2"/>
  <circle cx="65" cy="20" r="12" fill="#f00" stroke="#00f" stroke-width="3"/>
  <ellipse cx="95" cy="20" rx="16" ry="10" fill="none" stroke="black"/>
  <path d="M10 65 C30 35 60 35 80 65" fill="none" stroke="black"
    stroke-width="2" stroke-linecap="round"/>
</svg>
"""
    )

    check resource.elementCount == 4
    check resource.layers.len == 4
    check resource.layers[0].kind == slkStrokePath
    check resource.layers[0].segments[0].kind == spsLine
    check resource.layers[1].kind == slkCircle
    check resource.layers[1].paint.rgba == rgba(255, 0, 0, 255)
    check resource.layers[1].strokePaint.rgba == rgba(0, 0, 255, 255)
    check resource.layers[2].kind == slkMtsdfStroke
    check resource.layers[3].kind == slkStrokePath
    check resource.layers[3].segments[0].kind == spsCubic
    check resource.image != nil
    check resource.layers[2].mtsdfStrokeWidth == 1.0'f32

    let context = initDrawContext()
    discard context.addSvgMtsdf(
      DefaultDrawLevel,
      FigIdx(-1),
      rect(0.0, 0.0, 240.0, 160.0),
      resource,
      fill(color(0.2, 0.5, 0.9, 1.0)),
    )
    check context.resources.imageCount == 1
    check context.renderList.nodes.len == 5

  test "filled and stroked ellipses share one MTSDF image":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 80 50">
  <ellipse cx="40" cy="25" rx="30" ry="16" fill="black" stroke="black"
    stroke-width="3"/>
</svg>
"""
    )

    check resource.layers.len == 2
    check resource.layers[0].kind == slkMtsdfFill
    check resource.layers[1].kind == slkMtsdfStroke
    check resource.layers[0].image == resource.layers[1].image

    let context = initDrawContext()
    discard context.addSvgMtsdf(
      DefaultDrawLevel,
      FigIdx(-1),
      rect(0.0, 0.0, 160.0, 100.0),
      resource,
      fill(color(0.2, 0.5, 0.9, 1.0)),
    )
    check context.resources.imageCount == 1
    check context.renderList.nodes.len == 2

  test "rejects SVGs without visible painted elements":
    expect SvgMtsdfError:
      discard newSvgMtsdfResource(
        """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <path d="M0 0 H10 V10 H0 Z" display="none"/>
</svg>
"""
      )
