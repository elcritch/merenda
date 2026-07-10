import std/[hashes, os, tables]

import pkg/pixie

import figdraw/common/imgutils

import ../foundation/types

export imgutils except loadImage

type
  ImageCachePolicy* = enum
    icpDefault
    icpAlways
    icpNever
    icpBySize

  ImageResource* = ref object
    xName: string
    xFilePath: string
    xSize: Size
    xImageId: ImageId
    xCachePolicy: ImageCachePolicy
    xPixels: Image

var
  namedImages: Table[string, ImageResource]
  namedImagesReady: bool
  anonymousImageIndex: int

proc ensureNamedImages() =
  if not namedImagesReady:
    namedImages = initTable[string, ImageResource]()
    namedImagesReady = true

proc imageIdForName(name: string): ImageId =
  imgId("nimkit.image:" & name)

proc imageIdForData(name: string, data: string): ImageId =
  let key =
    if name.len > 0:
      "nimkit.image:" & name
    else:
      "nimkit.image.data:" & $hash(data)
  imgId(key)

proc uploadImage(image: ImageResource) =
  if image.xPixels.isNil or image.xCachePolicy == icpNever:
    return
  loadImage(image.xImageId, image.xPixels)

proc newImageResource*(
    image: Image, name = "", cachePolicy = icpDefault
): ImageResource =
  result = ImageResource(
    xName: name,
    xCachePolicy: cachePolicy,
    xPixels:
      if image.isNil:
        nil
      else:
        image.copy(),
  )
  if not result.xPixels.isNil:
    result.xSize = initSize(result.xPixels.width.float32, result.xPixels.height.float32)
  if name.len > 0:
    result.xImageId = imageIdForName(name)
  else:
    inc anonymousImageIndex
    result.xImageId = imageIdForName("anonymous:" & $anonymousImageIndex)
  result.uploadImage()

proc newImageResourceFromData*(
    data: string, name = "", cachePolicy = icpDefault
): ImageResource =
  let pixels = decodeImage(data)
  result = ImageResource(
    xName: name,
    xSize: initSize(pixels.width.float32, pixels.height.float32),
    xImageId: imageIdForData(name, data),
    xCachePolicy: cachePolicy,
    xPixels: pixels,
  )
  result.uploadImage()

proc newImageResourceFromFile*(
    filePath: string, name = "", cachePolicy = icpDefault
): ImageResource =
  let
    pixels = pixie.readImage(filePath)
    resolvedName =
      if name.len > 0:
        name
      else:
        splitFile(filePath).name
  result = ImageResource(
    xName: resolvedName,
    xFilePath: filePath,
    xSize: initSize(pixels.width.float32, pixels.height.float32),
    xImageId: imageIdForName(if resolvedName.len > 0: resolvedName else: filePath),
    xCachePolicy: cachePolicy,
    xPixels: pixels,
  )
  result.uploadImage()

proc copyImageResource*(image: ImageResource): ImageResource =
  result = ImageResource(
    xName: image.xName,
    xFilePath: image.xFilePath,
    xSize: image.xSize,
    xImageId: image.xImageId,
    xCachePolicy: image.xCachePolicy,
    xPixels:
      if image.xPixels.isNil:
        nil
      else:
        image.xPixels.copy(),
  )
  result.uploadImage()

proc name*(image: ImageResource): string =
  image.xName

proc filePath*(image: ImageResource): string =
  image.xFilePath

proc size*(image: ImageResource): Size =
  image.xSize

proc imageId*(image: ImageResource): ImageId =
  image.xImageId

proc cachePolicy*(image: ImageResource): ImageCachePolicy =
  image.xCachePolicy

proc `cachePolicy=`*(image: ImageResource, policy: ImageCachePolicy) =
  if image.xCachePolicy == policy:
    return
  image.xCachePolicy = policy
  image.uploadImage()

proc pixels*(image: ImageResource): Image =
  if image.xPixels.isNil:
    return nil
  image.xPixels.copy()

proc registerImage*(name: string, image: ImageResource) =
  if name.len == 0 or image.isNil:
    return
  ensureNamedImages()
  image.xName = name
  image.xImageId = imageIdForName(name)
  image.uploadImage()
  namedImages[name] = image

proc imageNamed*(name: string): ImageResource =
  ensureNamedImages()
  if name in namedImages:
    return namedImages[name]

proc removeImageNamed*(name: string): bool =
  ensureNamedImages()
  if name notin namedImages:
    return false
  namedImages.del(name)
  true
