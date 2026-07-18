import std/unittest

import figdraw
import merenda/nimkit

suite "SVG MTSDF resources":
  test "generates a reusable image from visible transformed paths":
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

    check resource.image != nil
    check resource.image.name == "svg-mtsdf-test"
    check resource.image.size == initSize(64.0, 32.0)
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

  test "rejects SVGs without visible paths":
    expect SvgMtsdfError:
      discard newSvgMtsdfResource(
        """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <path d="M0 0 H10 V10 H0 Z" display="none"/>
</svg>
"""
      )
