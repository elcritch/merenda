import std/tables

when defined(useNativeDynlib):
  {.error: "FigDraw managed resources require the static FigDraw build".}

import figdraw
from figdraw/common/typefaces import getFigFont

import ./images

const
  ImageAtlasPressureThreshold* = 0.88'f32
  ImageAtlasPressureCooldownFrames* = 120
  ImageAtlasShrinkWorkingSetDivisor* = 4

type
  RenderImageResource = object
    ## Retains both renderer ownership and the pixels needed after atlas loss.
    source: ImageResource
    owned: ImageRef

  RenderResourceManifest* = ref object
    ## Fonts and images referenced by one live render contribution or scene.
    fonts: Table[FontId, FontRef]
    images: Table[ImageId, RenderImageResource]

  RenderResourceMetrics* = object
    replayCount*: uint64
    generationRecoveryCount*: uint64
    pressureRebuildCount*: uint64
    atlasShrinkRebuildCount*: uint64
    automaticPreloadEvictionCount*: uint64
    atlasGeneration*: uint64
    atlasRebuildCount*: uint64
    atlasUsedRatio*: float32
    atlasPackedRatio*: float32
    atlasHighWaterRatio*: float32

  RenderResourceManager* = ref object
    pressureThreshold: float32
    pressureCooldownFrames: Natural
    pressureCooldown: int
    initialAtlasSize: int
    atlasHighWaterUsedArea: int
    atlasGeneration: uint64
    metricsValue: RenderResourceMetrics

proc initRenderResourceManifest*(): RenderResourceManifest =
  RenderResourceManifest(
    fonts: initTable[FontId, FontRef](),
    images: initTable[ImageId, RenderImageResource](),
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

proc addImage*(manifest: var RenderResourceManifest, image: ImageResource) =
  if image.isNil:
    return
  manifest.ensureManifest()
  let owned = image.renderingRef()
  manifest.images[owned.id] = RenderImageResource(source: image, owned: owned)

proc addResources*(
    manifest: var RenderResourceManifest, resources: RenderResourceManifest
) =
  ## Merges retained font and image resources into `manifest` by identity.
  if resources.isNil:
    return
  manifest.ensureManifest()
  for id, font in resources.fonts:
    manifest.fonts[id] = font
  for id, image in resources.images:
    manifest.images[id] = image

proc mergeRenderResources*(
    manifests: openArray[RenderResourceManifest]
): RenderResourceManifest =
  result = initRenderResourceManifest()
  for manifest in manifests:
    result.addResources(manifest)

proc fontCount*(manifest: RenderResourceManifest): Natural =
  if manifest.isNil: 0 else: manifest.fonts.len.Natural

proc imageCount*(manifest: RenderResourceManifest): Natural =
  if manifest.isNil: 0 else: manifest.images.len.Natural

proc containsFont*(manifest: RenderResourceManifest, id: FontId): bool =
  ## Reports whether `manifest` retains `id` for rendering.
  not manifest.isNil and id in manifest.fonts

proc containsImage*(manifest: RenderResourceManifest, id: ImageId): bool =
  ## Reports whether `manifest` retains `id` and its recovery source.
  not manifest.isNil and id in manifest.images

proc newRenderResourceManager*(
    pressureThreshold = ImageAtlasPressureThreshold,
    pressureCooldownFrames = ImageAtlasPressureCooldownFrames,
): RenderResourceManager =
  RenderResourceManager(
    pressureThreshold: clamp(pressureThreshold, 0.0'f32, 1.0'f32),
    pressureCooldownFrames: max(pressureCooldownFrames, 0).Natural,
  )

proc metrics*(manager: RenderResourceManager): RenderResourceMetrics =
  if not manager.isNil:
    result = manager.metricsValue

proc removeResourcesOutsideManifest[BackendState](
    renderer: FigRenderer[BackendState], resources: RenderResourceManifest
) =
  if resources.isNil:
    return

  var removed: seq[Hash]
  for key, metadata in renderer.ctx.atlasEntryMetaPtr().pairs:
    let retained =
      case metadata.kind
      of aekImage:
        resources.containsImage(metadata.imageId)
      of aekGlyph:
        resources.containsFont(metadata.fontId)
      of aekGenerated:
        ImageId(key) in resources.images
    if not retained:
      removed.add key
  for key in removed:
    renderer.ctx.removeAtlasEntry(key)

proc restoreManifestImages[BackendState](
    renderer: FigRenderer[BackendState], resources: RenderResourceManifest
) =
  if resources.isNil:
    return
  for id, resource in resources.images:
    let pixels = resource.source.pixels()
    discard renderer.ensureImage(id, pixels)

proc replayWorkingSet[BackendState](
    manager: RenderResourceManager,
    renderer: FigRenderer[BackendState],
    resources: RenderResourceManifest,
) =
  var attempts = 0
  while attempts < 8:
    let generation = renderer.atlasGeneration()
    renderer.ctx.ensureImageMessageSubscription()
    replayImageMessages(renderer.ctx.imageMessages)
    renderer.processImageMessages()
    renderer.removeResourcesOutsideManifest(resources)
    renderer.restoreManifestImages(resources)
    inc manager.metricsValue.replayCount
    if renderer.atlasGeneration() == generation:
      break
    inc manager.metricsValue.generationRecoveryCount
    inc attempts

proc prepare*[BackendState](
    manager: RenderResourceManager,
    renderer: FigRenderer[BackendState],
    resources: RenderResourceManifest = nil,
) =
  ## Applies pending resource messages and repairs atlas loss or pressure.
  ##
  ## When `resources` is present, recovery restores only that live manifest.
  ## Passing `nil` retains the global replay behavior used by transferred
  ## monolithic snapshots on the dedicated renderer.
  if manager.isNil or renderer.isNil:
    return

  if manager.initialAtlasSize <= 0:
    manager.initialAtlasSize = renderer.atlasUsage().atlasSize

  let
    generationBefore = renderer.atlasGeneration()
    generationChanged =
      manager.atlasGeneration != 0 and manager.atlasGeneration != generationBefore
  renderer.processImageMessages()
  if generationChanged or renderer.atlasGeneration() != generationBefore:
    inc manager.metricsValue.generationRecoveryCount
    manager.replayWorkingSet(renderer, resources)

  var usage = renderer.atlasUsage()
  manager.atlasHighWaterUsedArea = max(manager.atlasHighWaterUsedArea, usage.usedArea)
  let pressure = max(usage.usedRatio(), usage.packedRatio())
  manager.metricsValue.atlasUsedRatio = usage.usedRatio()
  manager.metricsValue.atlasPackedRatio = usage.packedRatio()
  manager.metricsValue.atlasHighWaterRatio =
    max(manager.metricsValue.atlasHighWaterRatio, pressure)
  let shouldShrink =
    manager.initialAtlasSize > 0 and usage.atlasSize > manager.initialAtlasSize and
    manager.atlasHighWaterUsedArea > 0 and
    usage.usedArea.int64 * ImageAtlasShrinkWorkingSetDivisor.int64 <=
    manager.atlasHighWaterUsedArea.int64
  if shouldShrink:
    let previousAtlasSize = usage.atlasSize
    renderer.rebuildImageAtlas(manager.initialAtlasSize)
    manager.replayWorkingSet(renderer, resources)
    usage = renderer.atlasUsage()
    if usage.atlasSize < previousAtlasSize:
      inc manager.metricsValue.atlasShrinkRebuildCount
    manager.atlasHighWaterUsedArea = usage.usedArea
    manager.pressureCooldown = manager.pressureCooldownFrames.int
  elif manager.pressureCooldown > 0:
    dec manager.pressureCooldown
  elif pressure >= manager.pressureThreshold:
    manager.metricsValue.automaticPreloadEvictionCount +=
      purgeAutomaticImagePreloads().uint64
    renderer.processImageMessages()
    usage = renderer.atlasUsage()
    if max(usage.usedRatio(), usage.packedRatio()) >= manager.pressureThreshold:
      let minimumSize =
        if usage.usedRatio() >= manager.pressureThreshold:
          usage.atlasSize * 2
        else:
          usage.atlasSize
      renderer.rebuildImageAtlas(minimumSize)
      inc manager.metricsValue.pressureRebuildCount
      manager.pressureCooldown = manager.pressureCooldownFrames.int
      manager.replayWorkingSet(renderer, resources)
      usage = renderer.atlasUsage()
      manager.atlasHighWaterUsedArea =
        max(manager.atlasHighWaterUsedArea, usage.usedArea)

  manager.metricsValue.atlasUsedRatio = usage.usedRatio()
  manager.metricsValue.atlasPackedRatio = usage.packedRatio()
  manager.metricsValue.atlasGeneration = usage.generation
  manager.metricsValue.atlasRebuildCount = usage.rebuildCount
  manager.atlasGeneration = usage.generation

proc clear*(manager: RenderResourceManager) =
  if not manager.isNil:
    manager.atlasGeneration = 0
    manager.metricsValue = default(RenderResourceMetrics)
