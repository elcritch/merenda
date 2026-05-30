import std/unittest

import merenda/appkit

proc approxEq(a, b: float32, epsilon = 0.001'f32): bool =
  abs(a - b) <= epsilon

suite "appkit nsgraphicscontext":
  test "context defaults and device description":
    let context = NSGraphicsContext.new()
    check context.shouldAntialias()
    check context.imageInterpolation() == NSImageInterpolationDefault
    check context.colorRenderingIntent() == NSColorRenderingIntentDefault
    check context.compositingOperation() == NSCompositeSourceOver
    let description = context.deviceDescription()
    check not description.isNil
    check description.len >= 1

  test "current context stack save and restore":
    NSGraphicsContext.setCurrentContext(NSGraphicsContext(value: nil))
    let contextA = NSGraphicsContext.graphicsContextWithGraphicsPort(
      cast[pointer](0x1), flipped = false
    )
    let contextB = NSGraphicsContext.graphicsContextWithGraphicsPort(
      cast[pointer](0x2), flipped = true
    )
    NSGraphicsContext.setCurrentContext(contextA)
    check NSGraphicsContext.currentContext().graphicsPort() == cast[pointer](0x1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.setCurrentContext(contextB)
    check NSGraphicsContext.currentContext().graphicsPort() == cast[pointer](0x2)
    NSGraphicsContext.restoreGraphicsState()
    check NSGraphicsContext.currentContext().graphicsPort() == cast[pointer](0x1)

  test "focus stack drives flipped lookup":
    NSGraphicsContext.setCurrentContext(NSGraphicsContext(value: nil))
    let context = NSGraphicsContext.graphicsContextWithGraphicsPort(
      cast[pointer](0x3), flipped = false
    )
    NSGraphicsContext.setCurrentContext(context)
    let scroller = NSScroller.new()
    NSGraphicsContext.currentContext().pushFocusView(scroller.NSView)
    let stack = NSGraphicsContext.currentContext().focusStack()
    check stack.len == 1
    check context.isFlipped()
    discard NSGraphicsContext.currentContext().popFocusView()
    check not context.isFlipped()

  test "quartz debug toggles":
    NSGraphicsContext.setQuartzDebuggingEnabled(true)
    check NSGraphicsContext.quartzDebuggingIsEnabled()
    check not NSGraphicsContext.inQuartzDebugMode()
    NSGraphicsContext.setQuartzDebugMode(true)
    check NSGraphicsContext.inQuartzDebugMode()
    NSGraphicsContext.setQuartzDebugMode(false)
    check not NSGraphicsContext.inQuartzDebugMode()
    NSGraphicsContext.setQuartzDebuggingEnabled(false)

  test "setFill and setStroke update context and restore with state stack":
    NSGraphicsContext.setCurrentContext(NSGraphicsContext(value: nil))
    let context = NSGraphicsContext.graphicsContextWithGraphicsPort(
      cast[pointer](0x4), flipped = false
    )
    NSGraphicsContext.setCurrentContext(context)

    NSColor.blueColor().setFill()
    NSColor.greenColor().setStroke()

    let beforeFill = NSGraphicsContext.currentContext().fillColor()
    let beforeStroke = NSGraphicsContext.currentContext().strokeColor()
    check approxEq(beforeFill.r, NSColor.blueColor().r)
    check approxEq(beforeFill.g, NSColor.blueColor().g)
    check approxEq(beforeFill.b, NSColor.blueColor().b)
    check approxEq(beforeStroke.r, NSColor.greenColor().r)
    check approxEq(beforeStroke.g, NSColor.greenColor().g)
    check approxEq(beforeStroke.b, NSColor.greenColor().b)

    NSGraphicsContext.saveGraphicsState()
    NSColor.redColor().setFill()
    NSColor.whiteColor().setStroke()
    NSGraphicsContext.restoreGraphicsState()

    let restoredFill = NSGraphicsContext.currentContext().fillColor()
    let restoredStroke = NSGraphicsContext.currentContext().strokeColor()
    check approxEq(restoredFill.r, beforeFill.r)
    check approxEq(restoredFill.g, beforeFill.g)
    check approxEq(restoredFill.b, beforeFill.b)
    check approxEq(restoredStroke.r, beforeStroke.r)
    check approxEq(restoredStroke.g, beforeStroke.g)
    check approxEq(restoredStroke.b, beforeStroke.b)
