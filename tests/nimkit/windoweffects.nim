import std/[math, unittest]

import merenda/nimkit/app/windoweffects
import merenda/nimkit/app/windows
import merenda/nimkit/foundation/types

suite "nimkit window effects":
  test "backdrop constructors retain independent logical regions":
    var regions = @[rect(12, 18, 160, 90)]
    let
      blur = initWindowBackdropEffect(regions)
      material = initWindowBackdropEffect(bmSidebar, regions)

    regions[0] = rect(0, 0, 1, 1)
    check blur.kind == wbekBlur
    check blur.regions == @[rect(12, 18, 160, 90)]
    check material.kind == wbekMaterial
    check material.material == bmSidebar
    check material.regions == blur.regions
    check noWindowBackdropEffect().kind == wbekNone

  test "backdrop regions require finite positive sizes":
    check initWindowBackdropEffect().isValid()
    check initWindowBackdropEffect([rect(-20, -10, 80, 60)]).isValid()
    check not initWindowBackdropEffect([rect(0, 0, 0, 60)]).isValid()
    check not initWindowBackdropEffect([rect(0, 0, 80, -1)]).isValid()
    check not initWindowBackdropEffect([rect(NaN.float32, 0, 80, 60)]).isValid()

  test "transparent windows stage effects before native realization":
    let window = newWindow("Effects", transparent = true)
    let effect = initWindowBackdropEffect(bmHud, [rect(8, 8, 180, 72)])

    check window.transparent
    check window.trySetBackdrop(effect)
    check window.backdrop == effect
    check not window.backdropActive
    check window.visualCapabilities() == {}

    window.clearBackdrop()
    check window.backdrop.kind == wbekNone
    check not window.backdropActive

  test "opaque windows reject nonempty backdrop effects":
    let window = newWindow("Opaque")
    let effect = initWindowBackdropEffect()

    check not window.transparent
    check not window.trySetBackdrop(effect)
    check window.backdrop.kind == wbekNone
    expect WindowEffectError:
      window.setBackdrop(effect)

  test "transparency can be configured before native realization":
    let window = newWindow("Deferred transparency")

    check window.setTransparent(true)
    check window.transparent
    window.transparent = false
    check not window.transparent

  test "transparency cannot be disabled while a backdrop is staged":
    let window = newWindow("Staged backdrop", transparent = true)

    check window.trySetBackdrop(initWindowBackdropEffect())
    check not window.setTransparent(false)
    check window.transparent
    window.clearBackdrop()
    check window.setTransparent(false)
