import std/os

import pkg/pixie

import figdraw/commons

import ./runtime
import ./graphicscontexts

type PixieImage = pixie.Image

proc resolveImagePath(path: string): string =
  if path.len == 0:
    return ""
  if fileExists(path):
    return path
  let dataPath = figDataDir() / path
  if fileExists(dataPath):
    return dataPath
  path

proc scaledImageSizeInRect(imageSize: NSSize, frameSize: NSSize, scaling: int): NSSize =
  if imageSize.width <= 0 or imageSize.height <= 0:
    return nsSize(0, 0)
  case scaling
  of NSImageScaleProportionallyDown:
    let xscale = frameSize.width / imageSize.width
    let yscale = frameSize.height / imageSize.height
    let scale = min(1.0'f32, min(xscale, yscale))
    nsSize(imageSize.width * scale, imageSize.height * scale)
  of NSImageScaleAxesIndependently:
    frameSize
  of NSImageScaleProportionallyUpOrDown:
    let xscale = frameSize.width / imageSize.width
    let yscale = frameSize.height / imageSize.height
    let scale = min(xscale, yscale)
    nsSize(imageSize.width * scale, imageSize.height * scale)
  else:
    imageSize

objcImpl:
  type NSImage* = object of NSObject
    xName {.set: setName, get: name.}: NSString
    xSize {.get: size.}: NSSize
    xBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    xPixieImage {.set: setPixieImage, get: pixieImage.}: PixieImage
    xImageId {.set: setImageId, get: imageId.}: ImageId
    xTemplate {.set: setTemplate, get: isTemplate.}: bool
    xFlipped {.set: setFlipped, get: isFlipped.}: bool
    xScalesWhenResized {.set: setScalesWhenResized, get: scalesWhenResized.}: bool
    xSourcePath {.set: setSourcePath, get: sourcePath.}: NSString

  method init*(self: var NSImage): NSImage =
    result = asTypeRaw[NSImage](callSuperIdFrom(NSImage, self, getSelector("init")))

  method initWithSize*(
      self: var NSImage, width: float32, height {.kw("height").}: float32
  ): NSImage =
    result = self.init()
    if result.isNil:
      return
    result.xSize = nsSize(max(width, 0.0), max(height, 0.0))

  method initWithContentsOfFile*(self: var NSImage, path: NSString): NSImage =
    let resolved = resolveImagePath($path)
    if resolved.len == 0 or not fileExists(resolved):
      return NSImage(value: nil)

    var pixels: PixieImage = nil
    try:
      pixels = pixie.readImage(resolved)
    except PixieError:
      return NSImage(value: nil)

    result = self.initWithSize(pixels.width.float32, pixels.height.float32)
    if result.isNil:
      return
    result.xSourcePath = ns(resolved)
    result.xPixieImage = pixels
    result.xImageId = imgId(resolved)
    loadImage(result.xImageId, pixels)

  method initWithContentsOfURL*(self: var NSImage, url: NSString): NSImage =
    self.initWithContentsOfFile(url)

  method initByReferencingFile*(self: var NSImage, path: NSString): NSImage =
    self.initWithContentsOfFile(path)

  method initByReferencingURL*(self: var NSImage, url: NSString): NSImage =
    self.initWithContentsOfURL(url)

  method isValid*(self: NSImage): bool =
    not self.xPixieImage.isNil

  method setSize*(self: NSImage, width: float32, height {.kw("height").}: float32) =
    self.xSize = nsSize(max(width, 0.0), max(height, 0.0))
    if self.xScalesWhenResized and (not self.xPixieImage.isNil):
      let scaled = scaledImageSizeInRect(
        nsSize(self.xPixieImage.width.float32, self.xPixieImage.height.float32),
        self.xSize,
        NSImageScaleAxesIndependently,
      )
      if scaled.width > 0 and scaled.height > 0:
        let resized =
          self.xPixieImage.resize(max(1, scaled.width.int), max(1, scaled.height.int))
        self.xPixieImage = resized
        let key =
          "nximage.resize#" & $cast[uint](self.value) & ":" & $scaled.width.int & "x" &
          $scaled.height.int
        let imageId = imgId(key)
        self.xImageId = imageId
        loadImage(imageId, resized)

  method drawAtPoint*(
      self: NSImage,
      point: NSPoint,
      source {.kw("fromRect").}: NSRect,
      operation {.kw("operation").}: int,
      fraction {.kw("fraction").}: float32,
  ) =
    if self.isNil:
      return
    let drawSize = self.size()
    if drawSize.width <= 0.0 or drawSize.height <= 0.0:
      return
    self.drawInRect(
      nsRect(point.x, point.y, drawSize.width, drawSize.height),
      source,
      operation,
      fraction,
    )

  method drawInRect*(
      self: NSImage,
      rect: NSRect,
      source {.kw("fromRect").}: NSRect,
      operation {.kw("operation").}: int,
      fraction {.kw("fraction").}: float32,
  ) =
    discard source
    if self.isNil or not self.isValid():
      return
    if rect.size.width <= 0.0 or rect.size.height <= 0.0:
      return
    if self.imageId().int == 0:
      return
    discard addImageToCurrentRenderContext(
      rect,
      self.imageId(),
      fraction = fraction,
      operation = NSCompositingOperation(operation),
    )

  method dealloc(self: NSImage) {.used.} =
    self.xName = NSString(value: nil)
    self.xSourcePath = NSString(value: nil)
    self.xPixieImage = nil
    destroyIvarFields(self)
    discard callSuperIdFrom(NSImage, self, getSelector("dealloc"))

proc imageUnfilteredFileTypes*(t: typedesc[NSImage]): NSArray[NSString] =
  nsArray[NSString](
    [@ns"png", @ns"jpg", @ns"jpeg", @ns"bmp", @ns"gif", @ns"qoi", @ns"ppm"]
  )

proc imageFileTypes*(t: typedesc[NSImage]): NSArray[NSString] =
  NSImage.imageUnfilteredFileTypes()

proc imageUnfilteredPasteboardTypes*(t: typedesc[NSImage]): NSArray[NSString] =
  nsArray[NSString]([@ns"NSPasteboardTypePNG", @ns"NSPasteboardTypeTIFF"])

proc imagePasteboardTypes*(t: typedesc[NSImage]): NSArray[NSString] =
  NSImage.imageUnfilteredPasteboardTypes()

proc imageNamed*(t: typedesc[NSImage], name: NSString): NSImage =
  let raw = $name
  if raw.len == 0:
    return NSImage(value: nil)

  var candidates = @[raw]
  if splitFile(raw).ext.len == 0:
    candidates.add(raw & ".png")
    candidates.add(raw & ".jpg")
    candidates.add(raw & ".jpeg")

  for candidate in candidates:
    let resolved = resolveImagePath(candidate)
    if resolved.len == 0 or not fileExists(resolved):
      continue
    var allocated = NSImage.alloc()
    result = allocated.initWithContentsOfFile(ns(resolved))
    allocated.value = nil
    if not result.isNil:
      result.setName(name)
      return
  result = NSImage(value: nil)

proc new*(t: typedesc[NSImage]): NSImage =
  var allocated = NSImage.alloc()
  result = initOwned(move(allocated))

proc initWithSize*(self: var NSImage, size: NSSize): NSImage =
  self.initWithSize(size.width, size.height)

proc setSize*(self: NSImage, size: NSSize) =
  self.setSize(size.width, size.height)

proc pixelSize*(self: NSImage): NSSize =
  let image = self.pixieImage()
  if image.isNil:
    return nsSize(0, 0)
  nsSize(image.width.float32, image.height.float32)
