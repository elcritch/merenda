import std/os

import pkg/pixie
import pkg/pixie/fileformats/png

import merenda/nimkit

proc makeSwatch(width, height: int): Image =
  result = newImage(width, height)
  for y in 0 ..< height:
    for x in 0 ..< width:
      let
        fx = x.float / max(width - 1, 1).float
        fy = y.float / max(height - 1, 1).float
        r = uint8(32 + int(190.0 * fx))
        g = uint8(72 + int(140.0 * fy))
        b = uint8(180 - int(90.0 * fx) + int(50.0 * fy))
      result[x, y] = rgba(r, g, b, 255)

proc makeCard(title, detail: string, image: ImageResource, scaling: ImageScaling): StackView =
  let
    card = newStackView(laVertical)
    heading = newHeadingLabel(title)
    imageView = newImageView(image, frame = initRect(0, 0, 168, 112))
    caption = newStatusLabel(detail)

  card.spacing = 8.0
  card.alignment = svaFill
  card.distribution = svdNatural
  card.background = initColor(0.99, 0.985, 0.955)

  imageView.backgroundColor = initColor(0.13, 0.15, 0.18)
  imageView.setImageScaling(scaling)
  imageView.setImageAlignment(iaCenter)
  imageView.setImageTint(initColor(1.0, 1.0, 1.0, 1.0))

  card.addArrangedSubview(heading, imageView, caption)
  card

let
  pixels = makeSwatch(96, 72)
  directImage = newImageResource(pixels, name = "direct pixels")
  dataImage = newImageResourceFromData(pixels.encodePng(), name = "encoded data")
  filePath = getTempDir() / "nimkit-image-demo.png"

pixels.writeFile(filePath)
let fileImage = newImageResourceFromFile(filePath, name = "loaded file")
removeFile(filePath)

registerImage("demo-swatch", directImage)
let namedImage = imageNamed("demo-swatch")

let pasteboard = newPasteboard("nimkit-image-demo")
discard pasteboard.setImage(PasteboardTypeImage, dataImage)
let pastedImage = pasteboard.imageForType(PasteboardTypeImage)

let
  app = sharedApplication()
  window = newWindow("Nimkit Image Resources", frame = initRect(160, 150, 760, 420))
  root = newView()
  layout = newStackView(laVertical)
  gallery = newStackView(laHorizontal)
  title = newTitleLabel("Image Resources")
  subtitle = newStatusLabel(
    "Pixel, encoded-data, file, named-image, and pasteboard-backed resources rendered by ImageView"
  )
  namedCard = makeCard(
    "Named image",
    namedImage.name & " / " & $namedImage.size.width.int & "x" & $namedImage.size.height.int,
    namedImage,
    isScaleNone,
  )
  pasteboardCard = makeCard(
    "Pasteboard copy",
    pastedImage.name & " copied through public.image",
    pastedImage,
    isScaleProportionallyUpOrDown,
  )
  fileCard = makeCard(
    "File resource",
    fileImage.name & " with independent-axis scaling",
    fileImage,
    isScaleAxesIndependently,
  )

root.background = initColor(0.91, 0.93, 0.92)

layout.spacing = 16.0
layout.alignment = svaFill

gallery.spacing = 16.0
gallery.alignment = svaFill
gallery.distribution = svdFillEqually

gallery.addArrangedSubview(namedCard, pasteboardCard, fileCard)
layout.addArrangedSubview(title, subtitle, gallery)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 24.0, 0.0, 24.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
