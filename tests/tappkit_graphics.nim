import std/unittest

import figdraw/fignodes

import knutella/appkit

proc approxEq(a, b: float32, epsilon = 0.01'f32): bool =
  abs(a - b) <= epsilon

proc isMostlyRed(c: Color): bool =
  c.r >= 0.85 and c.g <= 0.35 and c.b <= 0.35

proc isMostlyGreen(c: Color): bool =
  c.g >= 0.65 and c.r <= 0.45 and c.b <= 0.45

objcImpl:
  type GraphicsProbeView = object of NSView

  method drawRect*(self: GraphicsProbeView, rect: NSRect) =
    discard self
    discard rect
    NSColor.redColor().setFill()
    NSRectFill(nsRect(10.0, 5.0, 20.0, 8.0))
    NSColor.greenColor().setStroke()
    NSFrameRectWithWidth(nsRect(2.0, 2.0, 12.0, 10.0), 2.0)

suite "appkit nsgraphics":
  test "depth helper functions mirror AppKit depth encoding":
    check NSBitsPerSampleFromDepth(NSWindowDepthTwentyfourBitRGB) == 8
    check NSBitsPerPixelFromDepth(NSWindowDepthTwentyfourBitRGB) == 24
    check NSBitsPerSampleFromDepth(NSWindowDepthSixtyfourBitRGB) == 16
    check NSBitsPerPixelFromDepth(NSWindowDepthSixtyfourBitRGB) == 48
    check not NSColorSpaceFromDepth(NSWindowDepthTwentyfourBitRGB).isNil
    check NSNumberOfColorComponents(NSCalibratedRGBColorSpace) == 3
    check NSNumberOfColorComponents(NSDeviceCMYKColorSpace) == 4

  test "NSRectFill and NSFrameRectWithWidth emit figdraw nodes":
    var window = newWindow(0.0, 0.0, 100.0, 80.0, "graphics-probe")
    var viewAlloc = GraphicsProbeView.alloc()
    var root = viewAlloc.initWithFrame(0.0, 0.0, 100.0, 80.0)
    viewAlloc.value = nil
    window.setContentView(root)

    let renders = debugBuildWindowRenders(window)
    check(not renders.isNil)

    var foundFillRect = false
    var foundStrokeRect = false
    var foundTransform = false

    if renders.contains(0.ZLevel):
      for node in renders[0.ZLevel].nodes:
        if node.kind == nkTransform:
          foundTransform = true
          continue
        if node.kind != nkRectangle:
          continue

        if approxEq(node.screenBox.x, 10.0) and approxEq(node.screenBox.y, 5.0) and
            approxEq(node.screenBox.w, 20.0) and approxEq(node.screenBox.h, 8.0):
          let fillColor = node.fill.centerColor()
          if isMostlyRed(fillColor):
            foundFillRect = true

        if approxEq(node.screenBox.x, 2.0) and approxEq(node.screenBox.y, 2.0) and
            approxEq(node.screenBox.w, 12.0) and approxEq(node.screenBox.h, 10.0):
          if approxEq(node.stroke.weight, 2.0):
            let strokeColor = node.stroke.fill.centerColor()
            if isMostlyGreen(strokeColor):
              foundStrokeRect = true

    check(foundTransform)
    check(foundFillRect)
    check(foundStrokeRect)
