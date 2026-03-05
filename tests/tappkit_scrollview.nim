import std/unittest

import figdraw/fignodes

import knutella/appkit

proc approxEq(a, b: float32, epsilon = 0.01'f32): bool =
  abs(a - b) <= epsilon

suite "appkit nsscrollview integration":
  test "class size helpers account for scrollers and border":
    let content = nsSize(180.0, 120.0)
    let scroller = NSScroller.scrollerWidth()

    let frameSize =
      NSScrollView.frameSizeForContentSize(content, true, true, NSLineBorder)
    check(approxEq(frameSize.width, content.width + scroller + 1.0))
    check(approxEq(frameSize.height, content.height + scroller + 1.0))

    let roundTrip =
      NSScrollView.contentSizeForFrameSize(frameSize, true, true, NSLineBorder)
    check(approxEq(roundTrip.width, content.width))
    check(approxEq(roundTrip.height, content.height))

  test "tile computes clip and scroller frames":
    var scroll = NSScrollView.new()
    scroll.setFrame(nsRect(0.0, 0.0, 220.0, 160.0))
    scroll.setBorderType(NSNoBorder)
    scroll.setHasVerticalScroller(true)
    scroll.setHasHorizontalScroller(true)

    let clip = scroll.contentView()
    let vertical = scroll.verticalScroller()
    let horizontal = scroll.horizontalScroller()
    let scroller = NSScroller.scrollerWidth()

    check(approxEq(clip.frame().size.width, 220.0 - scroller))
    check(approxEq(clip.frame().size.height, 160.0 - scroller))
    check(approxEq(vertical.frame().origin.x, 220.0 - scroller))
    check(approxEq(vertical.frame().size.width, scroller))
    check(approxEq(vertical.frame().size.height, 160.0 - scroller))
    check(approxEq(horizontal.frame().origin.y, 160.0 - scroller))
    check(approxEq(horizontal.frame().size.height, scroller))
    check(approxEq(horizontal.frame().size.width, 220.0 - scroller))

  test "reflect scrolled clip view updates scroller state":
    var scroll = NSScrollView.new()
    scroll.setFrame(nsRect(0.0, 0.0, 240.0, 180.0))
    scroll.setHasVerticalScroller(true)
    scroll.setHasHorizontalScroller(true)

    var doc = newView(0.0, 0.0, 640.0, 480.0)
    scroll.setDocumentView(doc)
    let clip = scroll.contentView()
    clip.scrollToPoint(nsPoint(80.0, 60.0))
    scroll.reflectScrolledClipView(clip)

    let vertical = scroll.verticalScroller()
    let horizontal = scroll.horizontalScroller()

    check(vertical.isEnabled())
    check(horizontal.isEnabled())
    check(vertical.floatValue() >= 0.0 and vertical.floatValue() <= 1.0)
    check(horizontal.floatValue() >= 0.0 and horizontal.floatValue() <= 1.0)

    scroll.setAutohidesScrollers(true)
    var smallDoc = newView(0.0, 0.0, 30.0, 30.0)
    scroll.setDocumentView(smallDoc)
    scroll.reflectScrolledClipView(scroll.contentView())

    check(not scroll.verticalScroller().isEnabled())
    check(not scroll.horizontalScroller().isEnabled())
    check(scroll.verticalScroller().isHidden())
    check(scroll.horizontalScroller().isHidden())

  test "render loop emits clip and image nodes for scrollview document":
    let image = NSImage.imageNamed(@ns"arrow.png")
    check(not image.isNil)
    check(image.imageId().int != 0)

    var app = NSApp()
    var window = newWindow(0.0, 0.0, 320.0, 220.0, "scroll-image-loop")
    var root = newView(0.0, 0.0, 320.0, 220.0)
    var scroll = NSScrollView.new()
    scroll.setFrame(nsRect(20.0, 20.0, 260.0, 160.0))
    scroll.setHasVerticalScroller(true)
    scroll.setHasHorizontalScroller(true)

    var doc = newView(0.0, 0.0, 520.0, 360.0)
    var imageView = NSImageView.new()
    imageView.setFrame(nsRect(180.0, 120.0, 96.0, 72.0))
    imageView.setImage(image)
    imageView.setImageScaling(NSImageScaleAxesIndependently)
    doc.addSubview(imageView)
    scroll.setDocumentView(doc)

    root.addSubview(scroll)
    window.setContentView(root)
    app.addWindow(window)

    var imageSeenEveryFrame = true
    for i in 0 ..< 3:
      let clip = scroll.contentView()
      clip.scrollToPoint(nsPoint((i * 30).float32, (i * 20).float32))
      scroll.reflectScrolledClipView(clip)

      let renders = debugBuildWindowRenders(window)
      check(not renders.isNil)

      var foundClipNode = false
      var foundImageNode = false
      for _, list in renders.pairs():
        for node in list.nodes:
          if NfClipContent in node.flags:
            foundClipNode = true
          if node.kind == nkImage and node.image.id.int == image.imageId().int:
            foundImageNode = true
      check(foundClipNode)
      imageSeenEveryFrame = imageSeenEveryFrame and foundImageNode

    check(imageSeenEveryFrame)
