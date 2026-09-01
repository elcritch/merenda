## SVG path loader behavior shared by the NimKit test runner.
import std/unittest

import merenda/nimkit/drawing/svgpathloader

suite "public SVG path loader":
  test "parses SVG documents through the public module path":
    let document = parseSvgDocument(
      """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 16">
  <path d="M2 2 H22 V14 H2 Z" fill="#123456"/>
</svg>
"""
    )

    check document.width == 24
    check document.height == 16
    check document.elements.len == 1
    check document.elements[0].kind == sekPath
    check document.elements[0].hasFill
