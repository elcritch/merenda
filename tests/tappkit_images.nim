import std/unittest

import figdraw/fignodes

import merenda/appkit

proc approxEq(a, b: float32, epsilon = 0.01'f32): bool =
  abs(a - b) <= epsilon

suite "appkit nsimage, nsimagecell, nsimageview":
  test "NSImage loads pixie-backed image from resource path":
    let image = NSImage.imageNamed(@ns"arrow.png")
    check(not image.isNil)
    check(image.isValid())
    check(image.size().width > 0.0)
    check(image.size().height > 0.0)
    check(image.pixelSize().width > 0.0)
    check(image.pixelSize().height > 0.0)
    check(image.imageId().int != 0)

  test "NSImageCell computes scaled and aligned image frame":
    let image = NSImage.imageNamed(@ns"arrow.png")
    check(not image.isNil)

    var cell = NSImageCell.new()
    cell.setImage(image)
    cell.setImageScaling(NSImageScaleNone)
    cell.setImageAlignment(NSImageAlignCenter)

    let frame = nsRect(10.0, 20.0, 120.0, 80.0)
    let imageRect = cell.imageRectForBounds(frame)
    let imageSize = image.size()

    check(approxEq(imageRect.size.width, imageSize.width))
    check(approxEq(imageRect.size.height, imageSize.height))
    check(approxEq(imageRect.origin.x, 10.0 + (120.0 - imageSize.width) * 0.5))
    check(approxEq(imageRect.origin.y, 20.0 + (80.0 - imageSize.height) * 0.5))

    cell.setImageScaling(NSImageScaleAxesIndependently)
    cell.setImageAlignment(NSImageAlignTopRight)
    let fitRect = cell.imageRectForBounds(frame)
    check(approxEq(fitRect.origin.x, frame.origin.x))
    check(approxEq(fitRect.origin.y, frame.origin.y))
    check(approxEq(fitRect.size.width, frame.size.width))
    check(approxEq(fitRect.size.height, frame.size.height))

  test "NSImageView delegates image configuration through NSImageCell":
    let image = NSImage.imageNamed(@ns"arrow.png")
    check(not image.isNil)

    var view = NSImageView.new()
    view.setFrame(nsRect(4.0, 8.0, 96.0, 64.0))
    view.setImage(image)
    view.setImageScaling(NSImageScaleProportionallyUpOrDown)
    view.setImageAlignment(NSImageAlignTopLeft)
    view.setImageFrameStyle(NSImageFramePhoto)
    view.setEditable(true)

    check(view.image().value == image.value)
    check(view.imageScaling() == NSImageScaleProportionallyUpOrDown)
    check(view.imageAlignment() == NSImageAlignTopLeft)
    check(view.imageFrameStyle() == NSImageFramePhoto)
    check(view.isEditable())
    check(view.refusesFirstResponder())
    check(view.cell().isKindOfClass(NSImageCell))

  test "render tree includes nkImage node for NSImageView":
    let image = NSImage.imageNamed(@ns"arrow.png")
    check(not image.isNil)

    var window = newWindow(0.0, 0.0, 220.0, 160.0, "image-render")
    var root = newView(0.0, 0.0, 220.0, 160.0)
    var imageView = NSImageView.new()
    imageView.setFrame(nsRect(20.0, 30.0, 80.0, 60.0))
    imageView.setImage(image)
    imageView.setImageScaling(NSImageScaleAxesIndependently)
    imageView.setImageAlignment(NSImageAlignCenter)
    root.addSubview(imageView)
    window.setContentView(root)

    let renders = debugBuildWindowRenders(window)
    check(not renders.isNil)

    var found = false
    for _, list in renders.pairs():
      for node in list.nodes:
        if node.kind == nkImage:
          found = true
          check(node.image.id.int == image.imageId().int)
          check(node.screenBox.w > 0.0)
          check(node.screenBox.h > 0.0)
    check(found)
