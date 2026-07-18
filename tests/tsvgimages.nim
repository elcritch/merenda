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

  test "uses FigDraw vector layers for stroked lines curves and ellipses":
    let resource = newSvgMtsdfResource(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
  <line x1="5" y1="10" x2="40" y2="30" stroke="black" stroke-width="2"/>
  <circle cx="65" cy="20" r="12" fill="none" stroke="black" stroke-width="3"/>
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
    check resource.layers[2].kind == slkCircle
    check resource.layers[3].kind == slkStrokePath
    check resource.layers[3].segments[0].kind == spsCubic
    check resource.image.isNil

    let context = initDrawContext()
    discard context.addSvgMtsdf(
      DefaultDrawLevel,
      FigIdx(-1),
      rect(0.0, 0.0, 240.0, 160.0),
      resource,
      fill(color(0.2, 0.5, 0.9, 1.0)),
    )
    check context.resources.imageCount == 0
    check context.renderList.nodes.len == 6

  test "rejects SVGs without visible painted elements":
    expect SvgMtsdfError:
      discard newSvgMtsdfResource(
        """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <path d="M0 0 H10 V10 H0 Z" display="none"/>
</svg>
"""
      )
