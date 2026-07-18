import std/[options, os, unittest]

import figdraw

import merenda/nimkit/drawing
import merenda/nimkit/foundation/types
import merenda/nimkit/themes
import merenda/nimkit/text/texttypes

type EnvSnapshot = object
  name: string
  existed: bool
  value: string

proc withCleanFontEnv(body: proc() {.closure.}) =
  var snapshot: seq[EnvSnapshot]
  for name in FontEnvVars:
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

proc withCleanFontSizeEnv(body: proc() {.closure.}) =
  var snapshot: seq[EnvSnapshot]
  for name in FontSizeEnvVars:
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

proc withCleanMonospaceFontEnv(body: proc() {.closure.}) =
  var snapshot: seq[EnvSnapshot]
  for name in MonospaceFontEnvVars:
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

proc selectionBounds(layout: GlyphArrangement): tuple[x, y, w, h: float32] =
  if layout.selectionRects.len == 0:
    return

  var
    minX = float32.high
    minY = float32.high
    maxX = -float32.high
    maxY = -float32.high
  for rect in layout.selectionRects:
    minX = min(minX, rect.x)
    minY = min(minY, rect.y)
    maxX = max(maxX, rect.x + rect.w)
    maxY = max(maxY, rect.y + rect.h)

  (minX, minY, maxX - minX, maxY - minY)

suite "nimkit font layout":
  test "theme text style uses font env override precedence":
    withCleanFontEnv(
      proc() =
        putEnv(MerendaFontEnv, "Ubuntu.ttf")
        putEnv(NimKitFontEnv, "  HackNerdFont-Regular.ttf  ")

        let style = initAppearance().resolveTextStyle(
            controlStyle(srTextField), color(0.0, 0.0, 0.0), insets(0.0)
          )
        when defined(nimkitIgnoreEnvOverrides):
          check style.fontName == "Ubuntu.ttf"
        else:
          check style.fontName == "HackNerdFont-Regular.ttf"
    )

  test "font env override ignores empty values":
    withCleanFontEnv(
      proc() =
        putEnv(NimKitFontEnv, " ")
        putEnv(MerendaFontEnv, "Ubuntu.ttf")

        let override = fontOverrideFromEnv()
        check override.isSome
        check override.get().envName == MerendaFontEnv
        check override.get().name == "Ubuntu.ttf"

        let style = initAppearance().resolveTextStyle(
            controlStyle(srTextField), color(0.0, 0.0, 0.0), insets(0.0)
          )
        check style.fontName == "Ubuntu.ttf"
    )

  test "theme keeps interface and monospace font roles independent":
    var theme = initTheme()
    theme.setFontName(frUI, "Ubuntu.ttf")
    theme.setFontName(frMonospace, "HackNerdFont-Regular.ttf")
    let appearance = initAppearance(theme)

    check appearance.fontName(frUI) == "Ubuntu.ttf"
    check appearance.fontName(frMonospace) == "HackNerdFont-Regular.ttf"
    check appearance.resolveTextStyle(
      controlStyle(srTextField), color(0.0, 0.0, 0.0), insets(0.0)
    ).fontName == "Ubuntu.ttf"
    check appearance.resolveTextStyle(
      controlStyle(srMonoTextView), color(0.0, 0.0, 0.0), insets(0.0)
    ).fontName == "HackNerdFont-Regular.ttf"

  test "monospace font environment override is independent":
    withCleanMonospaceFontEnv(
      proc() =
        putEnv(MerendaMonospaceFontEnv, "Ubuntu.ttf")
        putEnv(NimKitMonospaceFontEnv, "  HackNerdFont-Regular.ttf  ")

        when defined(nimkitIgnoreEnvOverrides):
          check defaultFontName(frMonospace) == "Ubuntu.ttf"
        else:
          check defaultFontName(frMonospace) == "HackNerdFont-Regular.ttf"
    )

  test "text fonts carry automatic fallbacks and BCP 47 language":
    var style = initAppearance().resolveTextStyle(
        controlStyle(srTextField), color(0.0, 0.0, 0.0), insets(0.0)
      )
    style.language = initLanguageTag("ja_JP.UTF-8")
    let font = style.textFont()

    check $style.language == "ja-JP"
    when not defined(useNativeDynlib):
      check font.font.language == "ja-JP"
      check font.font.fallbackTypefaceIds.len > 0

  test "default font size uses env override precedence":
    withCleanFontSizeEnv(
      proc() =
        putEnv(MerendaFontSizeEnv, "15.5")
        putEnv(NimKitFontSizeEnv, " 18 ")

        let override = fontSizeOverrideFromEnv()
        check override.isSome
        when defined(nimkitIgnoreEnvOverrides):
          check override.get().envName == MerendaFontSizeEnv
          check abs(defaultFontSize() - 15.5'f32) < 0.0001'f32
        else:
          check override.get().envName == NimKitFontSizeEnv
          check abs(defaultFontSize() - 18.0'f32) < 0.0001'f32
    )

  test "default font size ignores empty values and rejects non-positive values":
    withCleanFontSizeEnv(
      proc() =
        putEnv(NimKitFontSizeEnv, " ")
        putEnv(MerendaFontSizeEnv, "15.5")

        let override = fontSizeOverrideFromEnv()
        check override.isSome
        check override.get().envName == MerendaFontSizeEnv
        check abs(defaultFontSize() - 15.5'f32) < 0.0001'f32

        putEnv(NimKitFontSizeEnv, "0")
        when defined(nimkitIgnoreEnvOverrides):
          check abs(defaultFontSize() - 15.5'f32) < 0.0001'f32
        else:
          expect ValueError:
            discard defaultFontSize()
    )

  test "default font size feeds text attributes and em layout lengths":
    withCleanFontSizeEnv(
      proc() =
        putEnv(NimKitFontSizeEnv, "24")
        putEnv(MerendaFontSizeEnv, "18")

        check defaultTextAttributes().fontSize == 18.0'f32
        check defaultTextAttributes(fontSize = 15.0'f32).fontSize == 15.0'f32
        check em(2.0'f32).resolveLayoutLength() == 36.0'f32
    )

  test "theme text style exposes font size to layout":
    withCleanFontSizeEnv(
      proc() =
        putEnv(NimKitFontSizeEnv, "24")
        putEnv(MerendaFontSizeEnv, "18")

        let style = initAppearance().resolveTextStyle(
            controlStyle(srTextField), color(0.0, 0.0, 0.0), insets(0.0)
          )
        check style.fontSize == 18.0'f32
        check textNaturalSize("wide", style).height >= 18.0'f32
    )

  test "centered label layout reports content bounds as local dimensions":
    let
      textRect = rect(12.0, 0.0, 640.0, 28.0)
      layout = textLayout(
        textRect, "Hello from KNutella/nimkit", color(0.09, 0.14, 0.26), taCenter
      )
      content = layout.selectionBounds()

    check content.x > 0.0
    check abs(layout.bounding.x - content.x) <= 0.01
    check abs(layout.bounding.y - content.y) <= 0.01
    check abs(layout.bounding.w - content.w) <= 0.01
    check abs(layout.bounding.h - content.h) <= defaultFontSize()
    check layout.bounding.x + layout.bounding.w <= textRect.size.width + 0.01
