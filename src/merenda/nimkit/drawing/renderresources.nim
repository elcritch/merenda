import std/tables

when defined(useNativeDynlib):
  {.error: "FigDraw managed resources require the static FigDraw build".}

import figdraw
from figdraw/common/typefaces import getFigFont

import ./images

const
  ImageAtlasPressureThreshold* = 0.88'f32
  ImageAtlasPressureCooldownFrames* = 120

type
  RenderResourceManifest* = ref object
    fonts: Table[FontId, FontRef]
    images: Table[ImageId, ImageRef]

  RenderResourceMetrics* = object
    replayCount*: uint64
    generationRecoveryCount*: uint64
    pressureRebuildCount*: uint64
    atlasGeneration*: uint64
    atlasRebuildCount*: uint64
    atlasUsedRatio*: float32
    atlasPackedRatio*: float32
    atlasHighWaterRatio*: float32

  RenderResourceManager* = ref object
    pressureThreshold: float32
    pressureCooldownFrames: Natural
    pressureCooldown: int
    metricsValue: RenderResourceMetrics

proc initRenderResourceManifest*(): RenderResourceManifest =
  RenderResourceManifest(
    fonts: initTable[FontId, FontRef](), images: initTable[ImageId, ImageRef]()
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
  manifest.images[owned.id] = owned

proc fontCount*(manifest: RenderResourceManifest): Natural =
  if manifest.isNil: 0 else: manifest.fonts.len.Natural

proc imageCount*(manifest: RenderResourceManifest): Natural =
  if manifest.isNil: 0 else: manifest.images.len.Natural

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

proc replayWorkingSet[BackendState](
    manager: RenderResourceManager, renderer: FigRenderer[BackendState]
) =
  var attempts = 0
  while attempts < 8:
    let generation = renderer.atlasGeneration()
    renderer.ctx.imageMessages = newImageMessageSubscription()
    renderer.processImageMessages()
    inc manager.metricsValue.replayCount
    if renderer.atlasGeneration() == generation:
      break
    inc manager.metricsValue.generationRecoveryCount
    inc attempts

proc prepare*[BackendState](
    manager: RenderResourceManager, renderer: FigRenderer[BackendState]
) =
  if manager.isNil or renderer.isNil:
    return

  let generationBefore = renderer.atlasGeneration()
  renderer.processImageMessages()
  if renderer.atlasGeneration() != generationBefore:
    inc manager.metricsValue.generationRecoveryCount
    manager.replayWorkingSet(renderer)

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
    inc manager.metricsValue.pressureRebuildCount
    manager.pressureCooldown = manager.pressureCooldownFrames.int
    manager.replayWorkingSet(renderer)
    usage = renderer.atlasUsage()

  manager.metricsValue.atlasUsedRatio = usage.usedRatio()
  manager.metricsValue.atlasPackedRatio = usage.packedRatio()
  manager.metricsValue.atlasGeneration = usage.generation
  manager.metricsValue.atlasRebuildCount = usage.rebuildCount

proc clear*(manager: RenderResourceManager) =
  if not manager.isNil:
    manager.metricsValue = default(RenderResourceMetrics)
