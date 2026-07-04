import std/[unittest, unicode]

import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/view/uirelaysviews
import uirelays as ui

type HookRelaysView = ref object of UIRelaysView

var
  hookDrawCount: int
  sentinelFillCount: int

let
  ClosureFill = color(0.20, 0.45, 0.85, 1.0)
  PointFill = color(0.90, 0.20, 0.15, 1.0)
  HookFill = color(0.10, 0.70, 0.30, 1.0)
  TextBackground = color(0.88, 0.90, 0.94, 1.0)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

func renderedRect(node: Fig): nimkitTypes.Rect =
  nimkitTypes.rect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

func rectsClose(left, right: nimkitTypes.Rect): bool =
  abs(left.origin.x - right.origin.x) <= 0.01'f32 and
    abs(left.origin.y - right.origin.y) <= 0.01'f32 and
    abs(left.size.width - right.size.width) <= 0.01'f32 and
    abs(left.size.height - right.size.height) <= 0.01'f32

proc containsRect(
    nodes: openArray[Fig], expected: nimkitTypes.Rect, fillValue: Fill
): bool =
  for node in nodes:
    if node.kind == nkRectangle and node.fill == fillValue and
        node.renderedRect().rectsClose(expected):
      return true

proc containsText(
    nodes: openArray[Fig], text: string, expectedOrigin: nimkitTypes.Point
): bool =
  for node in nodes:
    if node.kind == nkText and node.renderedText() == text and
        abs(node.screenBox.x.float32 - expectedOrigin.x) <= 0.01'f32 and
        abs(node.screenBox.y.float32 - expectedOrigin.y) <= 0.01'f32:
      return true

proc sentinelFillRect(rect: ui.Rect, color: ui.Color) {.nimcall.} =
  discard rect
  discard color
  inc sentinelFillCount

protocol HookRelaysDrawing of UIRelaysViewHooks:
  method drawUIRelays(view: HookRelaysView) =
    inc hookDrawCount
    ui.fillRect(ui.rect(6, 7, 8, 9), ui.color(26'u8, 179'u8, 77'u8))

proc newHookRelaysView(frame: nimkitTypes.Rect): HookRelaysView =
  result = HookRelaysView()
  initUIRelaysViewFields(result, frame = frame)
  discard result.withProtocol(HookRelaysDrawing)

suite "nimkit uirelays views":
  test "draw proc can issue uirelays drawing commands":
    let view = newUIRelaysView(
      proc(view: UIRelaysView) {.closure.} =
        discard view
        ui.fillRect(ui.rect(4, 5, 20, 10), ui.color(51'u8, 115'u8, 217'u8))
        ui.drawPoint(30, 18, ui.color(230'u8, 51'u8, 38'u8)),
      frame = nimkitTypes.rect(10, 20, 80, 60),
    )

    let nodes = buildRenders(view)[DefaultDrawLevel].nodes

    check nodes.containsRect(nimkitTypes.rect(14, 25, 20, 10), fill(ClosureFill.rgba))
    check nodes.containsRect(nimkitTypes.rect(40, 38, 1, 1), fill(PointFill.rgba))

  test "font relays measure and draw text":
    var
      extent: ui.TextExtent
      measured: ui.TextExtent
      metrics: ui.FontMetrics
      fetchedMetrics: ui.FontMetrics
      closedMetrics: ui.FontMetrics
      closedMeasured: ui.TextExtent
      closedExtent: ui.TextExtent
    let view = newUIRelaysView(
      proc(view: UIRelaysView) {.closure.} =
        discard view
        let font = ui.openFont("", 13, metrics)
        fetchedMetrics = ui.getFontMetrics(font)
        measured = ui.measureText(font, "Hi")
        extent = ui.drawText(
          font,
          3,
          4,
          "Hi",
          ui.color(13'u8, 15'u8, 18'u8),
          ui.color(224'u8, 230'u8, 240'u8),
        )
        ui.closeFont(font)
        closedMetrics = ui.getFontMetrics(font)
        closedMeasured = ui.measureText(font, "Closed")
        closedExtent = ui.drawText(
          font,
          10,
          12,
          "Closed",
          ui.color(13'u8, 15'u8, 18'u8),
          ui.color(224'u8, 230'u8, 240'u8),
        ),
      frame = nimkitTypes.rect(20, 30, 100, 40),
    )

    let nodes = buildRenders(view)[DefaultDrawLevel].nodes

    check metrics.ascent == 13
    check metrics.descent >= 0
    check metrics.lineHeight >= 13
    check fetchedMetrics == metrics
    check measured == extent
    check extent.w > 0
    check extent.h >= 13
    check nodes.containsText("Hi", initPoint(23.0, 34.0))
    check nodes.containsRect(
      nimkitTypes.rect(23, 34, extent.w.float32, extent.h.float32),
      fill(TextBackground.rgba),
    )
    check closedMetrics == ui.FontMetrics()
    check closedMeasured == ui.TextExtent()
    check closedExtent == ui.TextExtent()
    check not nodes.containsText("Closed", initPoint(30.0, 42.0))

  test "subclasses can draw through the drawUIRelays hook":
    hookDrawCount = 0
    let view = newHookRelaysView(nimkitTypes.rect(12, 14, 80, 60))

    let nodes = buildRenders(view)[DefaultDrawLevel].nodes

    check hookDrawCount == 1
    check nodes.containsRect(nimkitTypes.rect(18, 21, 8, 9), fill(HookFill.rgba))

  test "temporary relays are restored after drawing":
    let saved = ui.drawRelays
    sentinelFillCount = 0
    ui.drawRelays = ui.DrawRelays(
      fillRect: sentinelFillRect,
      drawLine: saved.drawLine,
      drawPoint: saved.drawPoint,
      loadImage: saved.loadImage,
      freeImage: saved.freeImage,
      drawImage: saved.drawImage,
    )
    try:
      let view = newUIRelaysView(
        proc(view: UIRelaysView) {.closure.} =
          discard view
          ui.fillRect(ui.rect(1, 2, 3, 4), ui.color(255'u8, 255'u8, 255'u8)),
        frame = nimkitTypes.rect(0, 0, 40, 40),
      )
      discard buildRenders(view)

      check sentinelFillCount == 0
      ui.fillRect(ui.rect(0, 0, 1, 1), ui.color(0'u8, 0'u8, 0'u8))
      check sentinelFillCount == 1
    finally:
      ui.drawRelays = saved
