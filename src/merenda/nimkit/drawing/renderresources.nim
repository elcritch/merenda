import std/[algorithm, hashes, tables]

when defined(useNativeDynlib):
  {.error: "FigDraw managed resources require the static FigDraw build".}

import pkg/pixie
import figdraw
from figdraw/common/typefaces import getFigFont

import ./images

const
  ImageAtlasPressureThreshold* = 0.88'f32
  ImageAtlasPressureCooldownFrames* = 120

type
  RenderResourceRetention* = enum
    rrrActive
    rrrPreloaded
    rrrPinned

  ManifestImage = object
    image: ImageResource
    retention: set[RenderResourceRetention]

  RenderResourceManifest* = ref object
    fonts: Table[FontId, FontRef]
    images: Table[ImageId, ManifestImage]

  FrozenImageResource* = object
    id*: ImageId
    width*: int
    height*: int
    data*: seq[ColorRGBX]
    contentHash*: Hash
    retention*: set[RenderResourceRetention]

  FrozenRenderResources* = object
    fonts*: seq[FigFont]
    images*: seq[FrozenImageResource]
    signature*: Hash

  ManagedImage = object
    owned: ImageRef
    pixels: Image
    retention: set[RenderResourceRetention]

  RenderResourceSet* = ref object
    fonts: Table[FontId, FontRef]
    images: Table[ImageId, ManagedImage]
    signature: Hash

  RenderResourceMetrics* = object
    retainedFonts*: Natural
    retainedImages*: Natural
    activeImages*: Natural
    preloadedImages*: Natural
    pinnedImages*: Natural
    sourceBytes*: uint64
    uploadCount*: uint64
    uploadsThisGeneration*: uint64
    generationRecoveryCount*: uint64
    pressureRebuildCount*: uint64
    atlasGeneration*: uint64
    atlasRebuildCount*: uint64
    atlasUsedRatio*: float32
    atlasPackedRatio*: float32
    atlasHighWaterRatio*: float32

  RenderResourceManager* = ref object
    resources: RenderResourceSet
    lastSnapshot: FrozenRenderResources
    visible: bool
    pressureThreshold: float32
    pressureCooldownFrames: Natural
    pressureCooldown: int
    metricsValue: RenderResourceMetrics

proc initRenderResourceManifest*(): RenderResourceManifest =
  RenderResourceManifest(
    fonts: initTable[FontId, FontRef](), images: initTable[ImageId, ManifestImage]()
  )

proc ensureManifest(manifest: var RenderResourceManifest) =
  if manifest.isNil:
    manifest = initRenderResourceManifest()

proc addFont*(manifest: var RenderResourceManifest, font: FigFont) =
  manifest.ensureManifest()
  let owned = fontRef(font)
  manifest.fonts[owned.fontId] = owned

proc addFonts*(manifest: var RenderResourceManifest, layout: GlyphArrangement) =
  manifest.ensureManifest()
  for glyphFont in layout.fonts:
    if glyphFont.fontId notin manifest.fonts:
      let owned = fontRef(getFigFont(glyphFont.fontId))
      manifest.fonts[glyphFont.fontId] = owned

proc addImage*(
    manifest: var RenderResourceManifest, image: ImageResource, retention = {rrrActive}
) =
  if image.isNil:
    return
  manifest.ensureManifest()
  let id = image.imageId()
  if id in manifest.images:
    var existing = manifest.images[id]
    existing.retention = existing.retention + retention
    manifest.images[id] = existing
  else:
    manifest.images[id] = ManifestImage(image: image, retention: retention)

proc fontCount*(manifest: RenderResourceManifest): Natural =
  if manifest.isNil: 0 else: manifest.fonts.len.Natural

proc imageCount*(manifest: RenderResourceManifest): Natural =
  if manifest.isNil: 0 else: manifest.images.len.Natural

proc imageContentHash(data: openArray[ColorRGBX]): Hash =
  var value = Hash(0)
  for pixel in data:
    value = value !& hash((pixel.r, pixel.g, pixel.b, pixel.a))
  !$value

proc snapshotImage(
    image: ImageResource, retention: set[RenderResourceRetention]
): FrozenImageResource =
  let pixels = image.pixels()
  result.id = image.imageId()
  result.retention = retention
  if not pixels.isNil:
    result.width = pixels.width
    result.height = pixels.height
    result.data = @(pixels.data)
    result.contentHash = result.data.imageContentHash()

proc freeze*(manifest: RenderResourceManifest): FrozenRenderResources =
  var
    fonts: seq[tuple[id: FontId, font: FigFont]]
    images = initTable[ImageId, ManifestImage]()

  if not manifest.isNil:
    for id, owned in manifest.fonts.pairs:
      fonts.add((id: id, font: owned.font))
    for id, entry in manifest.images.pairs:
      images[id] = entry

  for retained in retainedImageResources():
    var retention: set[RenderResourceRetention]
    if retained.preloaded:
      retention.incl rrrPreloaded
    if retained.pinned:
      retention.incl rrrPinned
    let id = retained.image.imageId()
    if id in images:
      var entry = images[id]
      entry.retention = entry.retention + retention
      images[id] = entry
    else:
      images[id] = ManifestImage(image: retained.image, retention: retention)

  fonts.sort(
    proc(a, b: tuple[id: FontId, font: FigFont]): int =
      cmp(Hash(a.id), Hash(b.id))
  )
  var imageSources: seq[FrozenImageResource]
  for id, entry in images.pairs:
    imageSources.add(entry.image.snapshotImage(entry.retention))
  imageSources.sort(
    proc(a, b: FrozenImageResource): int =
      cmp(Hash(a.id), Hash(b.id))
  )

  var signature = Hash(0)
  for entry in fonts:
    result.fonts.add(entry.font)
    signature = signature !& hash(entry.id)
  for source in imageSources:
    result.images.add(source)
    signature =
      signature !&
      hash(
        (
          Hash(source.id),
          source.width,
          source.height,
          source.contentHash,
          source.retention,
        )
      )
  result.signature = !$signature

proc imageFromSnapshot(source: FrozenImageResource): Image =
  if source.width <= 0 or source.height <= 0 or source.data.len == 0:
    return nil
  result = newImage(source.width, source.height)
  result.data = source.data

proc materialize(snapshot: FrozenRenderResources, visible: bool): RenderResourceSet =
  result = RenderResourceSet(
    fonts: initTable[FontId, FontRef](),
    images: initTable[ImageId, ManagedImage](),
    signature: snapshot.signature,
  )
  if visible:
    for font in snapshot.fonts:
      let owned = fontRef(font)
      result.fonts[owned.fontId] = owned
  for source in snapshot.images:
    if not visible and source.retention == {rrrActive}:
      continue
    result.images[source.id] = ManagedImage(
      owned: imageRef(source.id),
      pixels: source.imageFromSnapshot(),
      retention: source.retention,
    )

proc refreshMetrics(manager: RenderResourceManager) =
  manager.metricsValue.retainedFonts =
    if manager.resources.isNil: 0 else: manager.resources.fonts.len.Natural
  manager.metricsValue.retainedImages =
    if manager.resources.isNil: 0 else: manager.resources.images.len.Natural
  manager.metricsValue.activeImages = 0
  manager.metricsValue.preloadedImages = 0
  manager.metricsValue.pinnedImages = 0
  manager.metricsValue.sourceBytes = 0
  if not manager.resources.isNil:
    for image in manager.resources.images.values:
      if not image.pixels.isNil:
        manager.metricsValue.sourceBytes +=
          (image.pixels.data.len * sizeof(ColorRGBX)).uint64
      if rrrActive in image.retention:
        inc manager.metricsValue.activeImages
      if rrrPreloaded in image.retention:
        inc manager.metricsValue.preloadedImages
      if rrrPinned in image.retention:
        inc manager.metricsValue.pinnedImages

proc newRenderResourceManager*(
    pressureThreshold = ImageAtlasPressureThreshold,
    pressureCooldownFrames = ImageAtlasPressureCooldownFrames,
): RenderResourceManager =
  RenderResourceManager(
    visible: true,
    pressureThreshold: clamp(pressureThreshold, 0.0'f32, 1.0'f32),
    pressureCooldownFrames: max(pressureCooldownFrames, 0).Natural,
  )

proc commit*(manager: RenderResourceManager, snapshot: sink FrozenRenderResources) =
  if manager.isNil:
    return
  if not manager.resources.isNil and manager.lastSnapshot.signature == snapshot.signature:
    manager.lastSnapshot = move snapshot
    return

  # Materialize the replacement first so there is no zero-owner interval.
  let replacement = snapshot.materialize(manager.visible)
  manager.lastSnapshot = snapshot
  manager.resources = replacement
  manager.refreshMetrics()

proc setVisible*(manager: RenderResourceManager, visible: bool) =
  if manager.isNil or manager.visible == visible:
    return
  let replacement = manager.lastSnapshot.materialize(visible)
  manager.visible = visible
  manager.resources = replacement
  manager.refreshMetrics()

proc metrics*(manager: RenderResourceManager): RenderResourceMetrics =
  if not manager.isNil:
    result = manager.metricsValue

proc uploadWorkingSet[BackendState](
    manager: RenderResourceManager, renderer: FigRenderer[BackendState]
) =
  var attempts = 0
  while attempts < 8:
    let generation = renderer.atlasGeneration()
    for id, image in manager.resources.images.pairs:
      if renderer.ensureImage(id, image.pixels):
        inc manager.metricsValue.uploadCount
        inc manager.metricsValue.uploadsThisGeneration
    if renderer.atlasGeneration() == generation:
      break
    manager.metricsValue.uploadsThisGeneration = 0
    inc attempts
    inc manager.metricsValue.generationRecoveryCount

proc prepare*[BackendState](
    manager: RenderResourceManager, renderer: FigRenderer[BackendState]
) =
  if manager.isNil or renderer.isNil:
    return
  renderer.processImageMessages()
  if manager.resources.isNil:
    return

  let generationBefore = renderer.atlasGeneration()
  if manager.metricsValue.atlasGeneration != 0'u64 and
      manager.metricsValue.atlasGeneration != generationBefore:
    inc manager.metricsValue.generationRecoveryCount
  if manager.metricsValue.atlasGeneration != generationBefore:
    manager.metricsValue.uploadsThisGeneration = 0

  manager.uploadWorkingSet(renderer)

  var usage = renderer.atlasUsage()
  let pressure = max(usage.usedRatio(), usage.packedRatio())
  manager.metricsValue.atlasUsedRatio = usage.usedRatio()
  manager.metricsValue.atlasPackedRatio = usage.packedRatio()
  manager.metricsValue.atlasHighWaterRatio =
    max(manager.metricsValue.atlasHighWaterRatio, pressure)
  if manager.pressureCooldown > 0:
    dec manager.pressureCooldown
  elif pressure >= manager.pressureThreshold:
    let minimumSize =
      if usage.usedRatio() >= manager.pressureThreshold:
        usage.atlasSize * 2
      else:
        usage.atlasSize
    renderer.rebuildImageAtlas(minimumSize)
    manager.metricsValue.uploadsThisGeneration = 0
    inc manager.metricsValue.pressureRebuildCount
    manager.pressureCooldown = manager.pressureCooldownFrames.int
    manager.uploadWorkingSet(renderer)
    usage = renderer.atlasUsage()

  manager.metricsValue.atlasUsedRatio = usage.usedRatio()
  manager.metricsValue.atlasPackedRatio = usage.packedRatio()
  manager.metricsValue.atlasGeneration = usage.generation
  manager.metricsValue.atlasRebuildCount = usage.rebuildCount

proc clear*(manager: RenderResourceManager) =
  if manager.isNil:
    return
  manager.lastSnapshot = default(FrozenRenderResources)
  manager.resources = nil
  manager.refreshMetrics()
