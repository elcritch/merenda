import std/[os, unittest]

import pkg/pixie
import pkg/pixie/fileformats/png

import figdraw/fignodes

import merenda/nimkit

proc testImage(width, height: int): Image =
  result = newImage(width, height)
  result.fill(rgba(64, 128, 192, 255))

suite "nimkit image resources":
  test "image resources can be created from pixels data files and names":
    let
      source = testImage(4, 3)
      direct = newImageResource(source, name = "direct")
      data = source.encodePng()
      fromData = newImageResourceFromData(data, name = "from-data")
      filePath = getTempDir() / "nimkit-image-resource.png"

    source.writeFile(filePath)
    let fromFile = newImageResourceFromFile(filePath)
    removeFile(filePath)

    check direct.name == "direct"
    check direct.size == initSize(4, 3)
    check fromData.name == "from-data"
    check fromData.size == initSize(4, 3)
    check fromFile.name == "nimkit-image-resource"
    check fromFile.filePath == filePath
    check fromFile.size == initSize(4, 3)

    registerImage("registered", direct)
    check imageNamed("registered") == direct
    check removeImageNamed("registered")
    check imageNamed("registered").isNil

  test "pasteboards store image resources by type":
    let
      pasteboard = newPasteboard("images")
      image = newImageResource(testImage(5, 2), name = "pasteboard-image")

    check pasteboard.setImage(PasteboardTypeImage, image)
    check pasteboard.availableTypeFromArray([PasteboardTypeImage]) == PasteboardTypeImage

    let copied = pasteboard.imageForType(PasteboardTypeImage)
    check not copied.isNil
    check copied != image
    check copied.name == "pasteboard-image"
    check copied.size == initSize(5, 2)

  test "image views expose intrinsic size accessibility and render image nodes":
    let
      image = newImageResource(testImage(12, 6), name = "logo")
      root = newView(frame = rect(0, 0, 80, 40))
      imageView = newImageView(image, frame = rect(10, 8, 40, 20))

    root.addSubview(imageView)

    check imageView.intrinsicContentSize == initIntrinsicSize(12, 6)
    check imageView.accessibilityRole() == arImage
    check atImage in imageView.accessibilityTraits()
    check imageView.accessibilityLabel() == "logo"

    let list = buildRenders(root)[DefaultDrawLevel]
    var foundImage = false
    for node in list.nodes:
      if node.kind == nkImage:
        foundImage = true
        check node.image.id == image.imageId()
        check node.screenBox.w == 12.0
        check node.screenBox.h == 6.0
    check foundImage
