## Built-in themes are embedded CSS; font resources and chrome delegates stay native.

import std/[os, strutils, tables]
import ./themecore
import ./private/bundledthemes
import ../foundation/types

proc clearBackgroundPinstripes*(theme: var ThemeBuilder, selector: StyleSelector) =
  theme[selector, StyleBackgroundPinstripeHighlightColor] = color(0.0, 0.0, 0.0, 0.0)
  theme[selector, StyleBackgroundPinstripeColor] = color(0.0, 0.0, 0.0, 0.0)
  theme[selector, StyleBackgroundPinstripePeriod] = 0.0
  theme[selector, StyleBackgroundPinstripeHeight] = 0.0

proc clearBackgroundPinstripes*(theme: var ThemeBuilder) =
  theme.clearBackgroundPinstripes(initStyleSelector(srView))

const
  BaseCss = staticRead("stylesheets/base.css")
  AquaCss = staticRead("stylesheets/aqua.css")
  BannerCss = staticRead("stylesheets/banner.css")

type AquaThemeCache = object
  theme: Theme
  fontNames: array[FontRole, string]
  fontSize: float32
  extensionsGeneration: Natural

var
  aquaCache {.threadvar.}: AquaThemeCache
  bannerCache {.threadvar.}: BundledThemeCache

proc initAquaTheme*(): Theme =
  var fontNames: array[FontRole, string]
  for role in FontRole:
    fontNames[role] = defaultFontName(role)
  let fontSize = defaultFontSize()
  let extensionsGeneration = themeExtensionsGeneration()
  if aquaCache.theme.isInitialized and aquaCache.fontNames == fontNames and
      aquaCache.fontSize == fontSize and
      aquaCache.extensionsGeneration == extensionsGeneration:
    return aquaCache.theme
  var resources = initThemeBuilder()
  for role in FontRole:
    resources.setFontName(role, fontNames[role])
    resources.setFontFaces(role, FontFaceSet())
  resources["font.size"] = fontSize
  result = bundledTheme(BaseCss & AquaCss, resources.finish())
  var extended = initThemeBuilder(result, sroTheme)
  extended.installThemeExtensions()
  result = extended.finish()
  aquaCache = AquaThemeCache(
    theme: result,
    fontNames: fontNames,
    fontSize: fontSize,
    extensionsGeneration: extensionsGeneration,
  )

proc initBannerTheme*(): Theme =
  bundledTheme(BannerCss, initAquaTheme(), bannerCache)

type ThemeFactory* = proc(): Theme

var
  themeFactories: Table[string, ThemeFactory]
  themeFactoriesInitialized: bool
  defaultThemeFactory: ThemeFactory

proc normalizedThemeName(name: string): string =
  name.strip().toLowerAscii()

proc ensureThemeFactories() =
  if themeFactoriesInitialized:
    return
  themeFactories = initTable[string, ThemeFactory]()
  themeFactoriesInitialized = true

proc registerThemeFactory*(name: string, factory: ThemeFactory) =
  let key = name.normalizedThemeName()
  if key.len == 0:
    return
  ensureThemeFactories()
  themeFactories[key] = factory

proc registerDefaultThemeFactory*(factory: ThemeFactory) =
  defaultThemeFactory = factory

proc initTheme*(): Theme =
  if defaultThemeFactory.isNil:
    initAquaTheme()
  else:
    defaultThemeFactory()

proc initThemeByName*(name: string): Theme =
  let key = name.normalizedThemeName()
  if key.len == 0 or key in ["default", "system"]:
    return initTheme()
  if key == "aqua":
    return initAquaTheme()
  if key == "banner":
    return initBannerTheme()
  ensureThemeFactories()
  if key in themeFactories:
    return themeFactories[key]()
  initTheme()

const NimKitThemeEnv* = "NIMKIT_THEME"

proc themeNameFromEnv*(): string =
  if not envOverrideAllowed(NimKitThemeEnv):
    return ""
  getEnv(NimKitThemeEnv)

proc initThemeFromEnv*(): Theme =
  initThemeByName(themeNameFromEnv())

proc initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme)

proc initAppearance*(): Appearance =
  initAppearance(initThemeFromEnv())
