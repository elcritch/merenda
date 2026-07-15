import std/[hashes, os, tables]

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import pkg/pixie
  import figdraw

import ../foundation/types

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
    xOwned: ImageRef
    xPublished: bool

const
  AutomaticPreloadMaximumArea* = 256 * 256
  MaximumPreloadedImages* = 256

var
  namedImages: Table[string, ImageResource]
  namedImagesReady: bool
  anonymousImageIndex: int
  preloadedImages: Table[ImageId, ImageResource]
  preloadedImageOrder: seq[ImageId]
  automaticPreloadedImages: Table[ImageId, ImageResource]
  automaticPreloadedImageOrder: seq[ImageId]
  pinnedImages: Table[ImageId, ImageResource]

proc retainForRendering(image: ImageResource)

proc retainsImage(
    resources: Table[ImageId, ImageResource], image: ImageResource
): bool =
  let id = image.xImageId
  id in resources and resources[id] == image

proc releaseUnusedRenderingRef(image: ImageResource) =
  when defined(useNativeDynlib):
    if image.xOwned == default(ImageRef):
      return
  else:
    if image.xOwned.isNil:
      return
  if not preloadedImages.retainsImage(image) and
      not automaticPreloadedImages.retainsImage(image) and
      not pinnedImages.retainsImage(image):
    image.xOwned = nil

proc ensureNamedImages() =
  if not namedImagesReady:
    namedImages = initTable[string, ImageResource]()
    preloadedImages = initTable[ImageId, ImageResource]()
    automaticPreloadedImages = initTable[ImageId, ImageResource]()
    pinnedImages = initTable[ImageId, ImageResource]()
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

proc nextAnonymousImageId(): ImageId =
  inc anonymousImageIndex
  imageIdForName("anonymous:" & $anonymousImageIndex)

proc removePreloadOrder(order: var seq[ImageId], id: ImageId) =
  var index = order.len
  while index > 0:
    dec index
    if order[index] == id:
      order.delete(index)

proc admitPreload(
    resources: var Table[ImageId, ImageResource],
    order: var seq[ImageId],
    image: ImageResource,
) =
  let id = image.xImageId
  let replaced = resources.getOrDefault(id)
  order.removePreloadOrder(id)
  order.add(id)
  resources[id] = image
  if not replaced.isNil and replaced != image:
    replaced.releaseUnusedRenderingRef()
  while resources.len > MaximumPreloadedImages and order.len > 0:
    let oldest = order[0]
    order.delete(0)
    let evicted = resources[oldest]
    resources.del(oldest)
    evicted.releaseUnusedRenderingRef()

proc usesAutomaticPreload(image: ImageResource): bool =
  case image.xCachePolicy
  of icpAlways:
    true
  of icpBySize:
    image.xSize.width * image.xSize.height <= AutomaticPreloadMaximumArea.float32
  of icpDefault, icpNever:
    false

proc updateAutomaticPreload(image: ImageResource) =
  ensureNamedImages()
  if image.usesAutomaticPreload():
    image.retainForRendering()
    automaticPreloadedImages.admitPreload(automaticPreloadedImageOrder, image)
  elif image.xImageId in automaticPreloadedImages and
      automaticPreloadedImages[image.xImageId] == image:
    automaticPreloadedImages.del(image.xImageId)
    automaticPreloadedImageOrder.removePreloadOrder(image.xImageId)
    image.releaseUnusedRenderingRef()

proc newImageResource*(
    image: Image, name = "", cachePolicy = icpDefault
): ImageResource =
  result = ImageResource(
    xName: name,
    xCachePolicy: cachePolicy,
    xPixels:
      if image.isNil:
        default(Image)
      else:
        image.copy(),
  )
  if not result.xPixels.isNil:
    result.xSize = initSize(result.xPixels.width.float32, result.xPixels.height.float32)
  if name.len > 0:
    result.xImageId = imageIdForName(name)
  else:
    result.xImageId = nextAnonymousImageId()
  result.updateAutomaticPreload()

when defined(useNativeDynlib):
  proc newImageResource*[T](
      image: T, name = "", cachePolicy = icpDefault
  ): ImageResource =
    newImageResource(image.toImage(), name, cachePolicy)

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
  result.updateAutomaticPreload()

proc newImageResourceFromFile*(
    filePath: string, name = "", cachePolicy = icpDefault
): ImageResource =
  let
    pixels =
      when defined(useNativeDynlib):
        readImage(filePath)
      else:
        pixie.readImage(filePath)
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
  result.updateAutomaticPreload()

proc copyImageResource*(image: ImageResource): ImageResource =
  if image.isNil:
    return nil
  result = ImageResource(
    xName: image.xName,
    xFilePath: image.xFilePath,
    xSize: image.xSize,
    xImageId: nextAnonymousImageId(),
    xCachePolicy: image.xCachePolicy,
    xPixels:
      if image.xPixels.isNil:
        default(Image)
      else:
        image.xPixels.copy(),
  )
  result.updateAutomaticPreload()

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
  image.updateAutomaticPreload()

proc pixels*(image: ImageResource): Image =
  if image.xPixels.isNil:
    return default(Image)
  image.xPixels.copy()

proc renderingRef*(image: ImageResource): ImageRef =
  if image.isNil:
    return
  when defined(useNativeDynlib):
    if not image.xPublished:
      loadImage(image.xImageId, image.xPixels)
      image.xPublished = true
    image.xImageId
  else:
    if image.xPublished and hasImage(image.xImageId):
      return imageRef(image.xImageId)
    image.xPublished = true
    if image.xPixels.isNil:
      return imageRef(image.xImageId)
    var pixels = image.pixels()
    imageRef(image.xImageId, ensureMove pixels)

proc retainForRendering(image: ImageResource) =
  if image.isNil or image.xPixels.isNil:
    return
  when defined(useNativeDynlib):
    if image.xOwned == image.xImageId:
      return
    image.xOwned = image.renderingRef()
  else:
    if not image.xOwned.isNil and image.xOwned.id == image.xImageId:
      return
    image.xOwned = image.renderingRef()

proc registerImage*(name: string, image: ImageResource) =
  if name.len == 0 or image.isNil:
    return
  ensureNamedImages()
  let oldId = image.xImageId
  let wasPreloaded = oldId in preloadedImages and preloadedImages[oldId] == image
  let wasPinned = oldId in pinnedImages and pinnedImages[oldId] == image
  image.xOwned = default(ImageRef)
  image.xPublished = false
  image.xName = name
  image.xImageId = imageIdForName(name)
  if oldId in preloadedImages and preloadedImages[oldId] == image:
    preloadedImages.del(oldId)
    preloadedImageOrder.removePreloadOrder(oldId)
  if oldId in automaticPreloadedImages and automaticPreloadedImages[oldId] == image:
    automaticPreloadedImages.del(oldId)
    automaticPreloadedImageOrder.removePreloadOrder(oldId)
  if oldId in pinnedImages and pinnedImages[oldId] == image:
    pinnedImages.del(oldId)
  if wasPreloaded:
    preloadedImages.admitPreload(preloadedImageOrder, image)
  if wasPinned:
    let replaced = pinnedImages.getOrDefault(image.xImageId)
    pinnedImages[image.xImageId] = image
    if not replaced.isNil and replaced != image:
      replaced.releaseUnusedRenderingRef()
  image.updateAutomaticPreload()
  if wasPreloaded or wasPinned:
    image.retainForRendering()
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

proc preloadImage*(image: ImageResource) =
  if image.isNil:
    return
  ensureNamedImages()
  image.retainForRendering()
  preloadedImages.admitPreload(preloadedImageOrder, image)

proc unpreloadImage*(image: ImageResource) =
  if image.isNil:
    return
  ensureNamedImages()
  if image.xImageId in preloadedImages and preloadedImages[image.xImageId] == image:
    preloadedImages.del(image.xImageId)
    preloadedImageOrder.removePreloadOrder(image.xImageId)
    image.releaseUnusedRenderingRef()

proc isImagePreloaded*(image: ImageResource): bool =
  if image.isNil:
    return false
  ensureNamedImages()
  (image.xImageId in preloadedImages and preloadedImages[image.xImageId] == image) or (
    image.xImageId in automaticPreloadedImages and
    automaticPreloadedImages[image.xImageId] == image
  )

proc pinImage*(image: ImageResource) =
  if image.isNil:
    return
  ensureNamedImages()
  image.retainForRendering()
  let replaced = pinnedImages.getOrDefault(image.xImageId)
  pinnedImages[image.xImageId] = image
  if not replaced.isNil and replaced != image:
    replaced.releaseUnusedRenderingRef()

proc unpinImage*(image: ImageResource) =
  if image.isNil:
    return
  ensureNamedImages()
  if image.xImageId in pinnedImages and pinnedImages[image.xImageId] == image:
    pinnedImages.del(image.xImageId)
    image.releaseUnusedRenderingRef()

proc isImagePinned*(image: ImageResource): bool =
  if image.isNil:
    return false
  ensureNamedImages()
  if image.xImageId in pinnedImages and pinnedImages[image.xImageId] == image:
    return true
  for namedImage in namedImages.values:
    if namedImage == image:
      return true

proc retainedImageResources*(): seq[
    tuple[image: ImageResource, preloaded, pinned: bool]
] =
  ensureNamedImages()
  var resources = initTable[ImageId, ImageResource]()
  for id, image in preloadedImages.pairs:
    resources[id] = image
  for id, image in automaticPreloadedImages.pairs:
    resources[id] = image
  for id, image in pinnedImages.pairs:
    resources[id] = image
  for image in namedImages.values:
    resources[image.xImageId] = image
  for id, image in resources.pairs:
    var named = false
    for namedImage in namedImages.values:
      if namedImage == image:
        named = true
        break
    result.add(
      (
        image: image,
        preloaded: id in preloadedImages or id in automaticPreloadedImages,
        pinned: id in pinnedImages or named,
      )
    )
