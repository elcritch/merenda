import std/[hashes, os, tables, unittest]

import pkg/pixie
import pkg/pixie/fileformats/png

when defined(useNativeDynlib):
  import figdraw/dynlib except Image, fill, newImage, writeFile
else:
  import figdraw

import merenda/nimkit

proc testImage(width, height: int): Image =
  result = newImage(width, height)
  result.fill(rgba(64, 128, 192, 255))

when not defined(useNativeDynlib):
  type RecoveryContext = ref object of BackendContext
    entries: Table[Hash, figdraw.Rect]
    entryMetadata: Table[Hash, AtlasEntryMeta]
    packedArea: int
    uploadCount: int
    resetOnSecondUpload: bool

  method entriesPtr*(context: RecoveryContext): ptr Table[Hash, figdraw.Rect] =
    context.entries.addr

  method atlasEntryMetaPtr*(context: RecoveryContext): var Table[Hash, AtlasEntryMeta] =
    context.entryMetadata

  method atlasSize*(context: RecoveryContext): int =
    16

  method atlasPackedArea*(context: RecoveryContext): int =
    context.packedArea

  method hasImage*(context: RecoveryContext, key: Hash): bool =
    key in context.entries

  method putImage*(context: RecoveryContext, image: ImgObj) =
    inc context.uploadCount
    if context.resetOnSecondUpload and context.uploadCount == 2:
      context.resetOnSecondUpload = false
      context.resetImageAtlas(16)
    context.entries[image.id.Hash] =
      figdraw.rect(0, 0, 1.0'f32 / 16.0'f32, 1.0'f32 / 16.0'f32)

  method resetImageAtlas*(context: RecoveryContext, minimumSize: int) =
    discard minimumSize
    context.entries.clear()
    context.entryMetadata.clear()
    context.packedArea = 0
    context.noteAtlasRebuilt()

  proc newRecoveryRenderer(): tuple[
    context: RecoveryContext, renderer: FigRenderer[NoRendererBackendState]
  ] =
    result.context = RecoveryContext(
      entries: initTable[Hash, figdraw.Rect](),
      entryMetadata: initTable[Hash, AtlasEntryMeta](),
      packedArea: 255,
      resetOnSecondUpload: true,
    )
    result.renderer = newFigRenderer(result.context)

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

    when defined(useNativeDynlib):
      check direct.pixels().encodePng().len > 8

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

  test "image sources stay lazy and copies have independent identities":
    let
      source = testImage(7, 5)
      image = newImageResource(source)
      copied = image.copyImageResource()

    check not hasImage(image.imageId())
    check image.imageId() != copied.imageId()
    check copied.size == image.size
    check copied.pixels().data == image.pixels().data

  test "automatic preload explicit preload and named pins are independent":
    let image = newImageResource(testImage(8, 8), cachePolicy = icpAlways)

    check image.isImagePreloaded()
    image.preloadImage()
    image.cachePolicy = icpNever
    check image.isImagePreloaded()
    image.unpreloadImage()
    check not image.isImagePreloaded()

    image.pinImage()
    registerImage("retained-image", image)
    check image.isImagePinned()
    check removeImageNamed("retained-image")
    check image.isImagePinned()
    image.unpinImage()
    check not image.isImagePinned()

  test "preload admission is bounded and supports readmission":
    var images: seq[ImageResource]
    for _ in 0 .. MaximumPreloadedImages:
      let image = newImageResource(testImage(1, 1))
      image.preloadImage()
      images.add(image)

    check not images[0].isImagePreloaded()
    check images[^1].isImagePreloaded()
    images[^1].unpreloadImage()
    check not images[^1].isImagePreloaded()
    images[^1].preloadImage()
    check images[^1].isImagePreloaded()

    for image in images:
      image.unpreloadImage()

  test "frozen signatures distinguish replacement pixels under one image ID":
    let
      first = newImageResource(testImage(4, 4), name = "replacement-signature")
      secondPixels = testImage(4, 4)
    secondPixels[0, 0] = rgba(220, 40, 10, 255).rgbx()
    let second = newImageResource(secondPixels, name = "replacement-signature")
    var
      firstManifest = initRenderResourceManifest()
      secondManifest = initRenderResourceManifest()
    firstManifest.addImage(first)
    secondManifest.addImage(second)

    let
      firstSnapshot = firstManifest.freeze()
      secondSnapshot = secondManifest.freeze()
    check firstSnapshot.images[0].id == secondSnapshot.images[0].id
    check firstSnapshot.images[0].contentHash != secondSnapshot.images[0].contentHash
    check firstSnapshot.signature != secondSnapshot.signature

  test "draw manifests include visible images and omit hidden images":
    let
      image = newImageResource(testImage(10, 4))
      root = newView(frame = rect(0, 0, 80, 40))
      imageView = newImageView(image, frame = rect(2, 3, 10, 4))
    root.addSubview(imageView)

    discard buildRenders(root)
    check root.renderResources().imageCount == 1
    let visible = root.renderResources().freeze()
    check visible.images.len == 1
    check visible.images[0].id == image.imageId()
    check visible.images[0].retention == {rrrActive}

    imageView.hidden = true
    discard buildRenders(root)
    check root.renderResources().imageCount == 0
    check root.renderResources().freeze().images.len == 0

  test "host resource sets release active images while hidden but retain pins":
    let
      image = newImageResource(testImage(6, 6))
      manager = newRenderResourceManager()
    var manifest = initRenderResourceManifest()
    manifest.addImage(image)
    manager.commit(manifest.freeze())
    check manager.metrics.retainedImages == 1
    check manager.metrics.activeImages == 1

    manager.setVisible(false)
    check manager.metrics.retainedImages == 0

    image.pinImage()
    manager.commit(manifest.freeze())
    check manager.metrics.retainedImages == 1
    check manager.metrics.pinnedImages == 1
    image.unpinImage()
    manager.clear()

  when not defined(useNativeDynlib):
    test "host resource sets recover renderer generations and pressure rebuilds":
      clearImageCache()
      let
        first = newImageResource(testImage(2, 2))
        second = newImageResource(testImage(3, 3))
        manager = newRenderResourceManager()
        recovery = newRecoveryRenderer()
      var manifest = initRenderResourceManifest()
      manifest.addImage(first)
      manifest.addImage(second)
      manager.commit(manifest.freeze())

      manager.prepare(recovery.renderer)
      check first.imageId().Hash in recovery.context.entries
      check second.imageId().Hash in recovery.context.entries
      check manager.metrics.generationRecoveryCount > 0

      recovery.context.packedArea = 255
      manager.prepare(recovery.renderer)
      check manager.metrics.pressureRebuildCount == 1
      check manager.metrics.atlasRebuildCount >= 2
      check manager.metrics.atlasPackedRatio < ImageAtlasPressureThreshold
      check recovery.context.uploadCount >= 5

      manager.clear()
      recovery.renderer.processImageMessages()
