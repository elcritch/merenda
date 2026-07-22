import std/math

import ../foundation/types

type
  WindowEffectCapability* = enum
    ## Native visual effects reported by a realized window's backend.
    wecBackdropBlur
    wecBackdropBlurRegions
    wecBackdropMaterial

  WindowBackdropEffectKind* = enum
    ## The effect applied behind a transparent window's rendered content.
    wbekNone
    wbekBlur
    wbekMaterial

  BackdropMaterial* = enum
    ## Backend-neutral semantic materials. Backends choose their native rendering.
    bmDefault
    bmLight
    bmDark
    bmTitlebar
    bmSidebar
    bmHud
    bmPopover

  WindowBackdropEffect* = object
    ## A value-only backdrop request using logical NimKit window coordinates.
    ## An empty region list applies the effect to the whole content area.
    regions*: seq[Rect]
    case kind*: WindowBackdropEffectKind
    of wbekMaterial:
      material*: BackdropMaterial
    of wbekNone, wbekBlur:
      discard

  WindowEffectError* = object of CatchableError
    ## Raised by strict window-effect setters when a request cannot be applied.

func initWindowBackdropEffect*(regions: openArray[Rect] = []): WindowBackdropEffect =
  ## Creates a blur request. Empty regions select the entire content area.
  WindowBackdropEffect(kind: wbekBlur, regions: @regions)

func initWindowBackdropEffect*(
    material: BackdropMaterial, regions: openArray[Rect] = []
): WindowBackdropEffect =
  ## Creates a semantic material request for all or selected content regions.
  WindowBackdropEffect(kind: wbekMaterial, material: material, regions: @regions)

func noWindowBackdropEffect*(): WindowBackdropEffect =
  ## Creates a request that removes the current backdrop.
  WindowBackdropEffect(kind: wbekNone)

func `==`*(left, right: WindowBackdropEffect): bool =
  if left.kind != right.kind or left.regions != right.regions:
    return false
  case left.kind
  of wbekMaterial:
    left.material == right.material
  of wbekNone, wbekBlur:
    true

func finite(value: float32): bool =
  value.classify() in {fcNormal, fcSubnormal, fcZero}

func isValid*(effect: WindowBackdropEffect): bool =
  ## Returns whether every requested region is finite and has a positive size.
  for region in effect.regions:
    if not region.origin.x.finite() or not region.origin.y.finite() or
        not region.size.width.finite() or not region.size.height.finite() or
        region.size.width <= 0.0'f32 or region.size.height <= 0.0'f32:
      return false
  true
