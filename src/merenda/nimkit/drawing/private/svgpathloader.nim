# SPDX-License-Identifier: Apache-2.0
# Adapted from sdfy/src/sdfy/msdfgenSvg.nim.

import std/math

import pkg/pixie
include pixie/fileformats/svg

proc normalizeSvgData(data: string): string =
  result = data.replace(",", " ")
  let
    key = "viewBox=\""
    start = result.find(key)
  if start < 0:
    return

  let
    valueStart = start + key.len
    valueEnd = result.find('"', valueStart)
  if valueEnd < 0:
    return

  let
    viewBox = result[valueStart ..< valueEnd]
    parts = viewBox.splitWhitespace()
  if parts.len != 4:
    return

  var
    fixed = parts
    updated = false
  for index in 0 ..< fixed.len:
    if fixed[index].contains('.'):
      let value =
        try:
          parseFloat(fixed[index])
        except ValueError:
          return
      fixed[index] = $int(round(value))
      updated = true

  if updated:
    let normalizedViewBox = fixed.join(" ")
    result = result[0 ..< valueStart] & normalizedViewBox & result[valueEnd .. ^1]

proc svgToPath(svg: Svg): tuple[path: Path, elements: int] =
  let combined = newPath()
  var count = 0
  for (path, properties) in svg.elements:
    if properties.display and properties.opacity > 0:
      let local = path.copy()
      local.transform(properties.transform)
      combined.addPath(local)
      inc count
  (combined, count)

proc parseSvgPath*(svgData: string): tuple[path: Path, elements: int] =
  parseSvg(normalizeSvgData(svgData)).svgToPath()
