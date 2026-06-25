import std/[options, os, unittest]

import merenda/nimkit/app/backend as nimkitBackend

type EnvSnapshot = object
  name: string
  existed: bool
  value: string

proc withCleanUiScaleEnv(body: proc() {.closure.}) =
  var snapshot: seq[EnvSnapshot]
  for name in nimkitBackend.UiScaleEnvVars:
    snapshot.add EnvSnapshot(name: name, existed: existsEnv(name), value: getEnv(name))
    delEnv(name)

  try:
    body()
  finally:
    for item in snapshot:
      if item.existed:
        putEnv(item.name, item.value)
      else:
        delEnv(item.name)

suite "nimkit backend":
  test "ui scale override prefers NimKit env over aliases":
    withCleanUiScaleEnv(
      proc() =
        putEnv(nimkitBackend.NimKitUiScaleEnv, "1.25")
        putEnv(nimkitBackend.MerendaUiScaleEnv, "1.5")
        putEnv(nimkitBackend.FigDrawLegacyUiScaleEnv, "2.0")

        let override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.NimKitUiScaleEnv
        check abs(override.get().scale - 1.25'f32) < 0.0001'f32
    )

  test "ui scale override falls back through Merenda and legacy env vars":
    withCleanUiScaleEnv(
      proc() =
        putEnv(nimkitBackend.MerendaUiScaleEnv, "1.5")
        putEnv(nimkitBackend.FigDrawLegacyUiScaleEnv, "2.0")

        var override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.MerendaUiScaleEnv
        check abs(override.get().scale - 1.5'f32) < 0.0001'f32

        delEnv(nimkitBackend.MerendaUiScaleEnv)
        override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.FigDrawLegacyUiScaleEnv
        check abs(override.get().scale - 2.0'f32) < 0.0001'f32
    )

  test "ui scale override ignores empty values and rejects non-positive values":
    withCleanUiScaleEnv(
      proc() =
        putEnv(nimkitBackend.NimKitUiScaleEnv, " ")
        putEnv(nimkitBackend.MerendaUiScaleEnv, "1.75")

        var override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.MerendaUiScaleEnv
        check abs(override.get().scale - 1.75'f32) < 0.0001'f32

        putEnv(nimkitBackend.NimKitUiScaleEnv, "0")
        expect ValueError:
          discard nimkitBackend.uiScaleOverrideFromEnv()
    )
