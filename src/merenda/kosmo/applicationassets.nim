## Embedded Kosmo assets, version metadata, and application font setup.

import std/[options, os, strutils]

from figdraw/extras/systemfonttypes import SystemTypeface, initSystemTypeface

import ../nimkit as nimkit
import ../services/assetcache
import ./config

func nimblePackageVersion(manifest: string): string =
  for line in manifest.splitLines():
    let fields = line.split('=', maxsplit = 1)
    if fields.len == 2 and fields[0].strip() == "version":
      let value = fields[1].strip()
      if value.len >= 2 and value[0] == '"' and value[^1] == '"':
        return value[1 ..^ 2]
  raise newException(ValueError, "merenda.nimble does not declare a package version")

const
  MerendaNimbleManifest =
    staticRead(currentSourcePath().parentDir / "../../../merenda.nimble")
  KosmoIconPng =
    staticRead(currentSourcePath().parentDir / "../../../data/kosmo-icon.png")
  KosmoInterfaceFontZip = staticRead(
    currentSourcePath().parentDir / "../../../data/IBMPlexSans-Regular.ttf.zip"
  )
  KosmoInterfaceItalicFontZip = staticRead(
    currentSourcePath().parentDir / "../../../data/IBMPlexSans-Italic.ttf.zip"
  )
  KosmoInterfaceBoldFontZip =
    staticRead(currentSourcePath().parentDir / "../../../data/IBMPlexSans-Bold.ttf.zip")
  KosmoMonospaceFontZip = staticRead(
    currentSourcePath().parentDir /
      "../../../data/JetBrainsMonoNerdFontMono-Regular.ttf.zip"
  )
  KosmoVersion* {.strdefine.} = nimblePackageVersion(MerendaNimbleManifest)
  KosmoGitHashOverride* {.strdefine.} = ""
  KosmoGitHash* =
    when KosmoGitHashOverride.len > 0:
      KosmoGitHashOverride
    else:
      block:
        const repositoryRoot = currentSourcePath().parentDir / "../../.."
        const revision =
          gorgeEx("git -C " & quoteShell(repositoryRoot) & " rev-parse --short=12 HEAD")
        if revision.exitCode == 0:
          revision.output.strip()
        else:
          "unknown"
  KosmoMoeUrl* = "https://github.com/fox0430/moe"
  KosmoApplicationIdentifier* = "kosmo"
  KosmoInterfaceFontFileName* = "IBMPlexSans-Regular.ttf"
  KosmoInterfaceItalicFontFileName* = "IBMPlexSans-Italic.ttf"
  KosmoInterfaceBoldFontFileName* = "IBMPlexSans-Bold.ttf"
  KosmoInterfaceFontName* = "IBM Plex Sans"
  KosmoInterfaceFontSha256* =
    "f1090ad34ee3187c3360cc2a5dfb0fa21441adb1c1a80408b161d290451aa891"
  KosmoInterfaceItalicFontSha256* =
    "a9c6ef9942c49e49d11e11a6dacc0b3a087978757e9b22a06b8ac22a6400fb15"
  KosmoInterfaceBoldFontSha256* =
    "9e6c74a889a700d707613d24548fe4ffa6bc59559a0689d2cf9e133bdcdafb2f"
  KosmoMonospaceFontFileName* = "JetBrainsMonoNerdFontMono-Regular.ttf"
  KosmoMonospaceFontName* = "JetBrainsMono Nerd Font Mono"
  KosmoMonospaceFontSha256* =
    "f2a5ea6cfab397445ffab00c0370927b66d61e560a05db5db271b42006381c1a"
  KosmoAboutCredits =
    """
Powered by Moe, the Vim-like text editor.
$1

Licensed under the GNU General Public License v3.0 (GPL-3.0).""" %
    [KosmoMoeUrl]
  KosmoConfigTextStyleRoles = [
    nimkit.srBox, nimkit.srButton, nimkit.srCheckBox, nimkit.srRadioButton,
    nimkit.srTextField, nimkit.srTextView, nimkit.srComboBox, nimkit.srComboBoxItem,
    nimkit.srTab, nimkit.srTableHeaderCell, nimkit.srRowItem, nimkit.srCascadingRowItem,
    nimkit.srTooltip, nimkit.srMonoTextView,
  ]

type KosmoBundledFontInstall* = object
  ## Cache installation results for Kosmo's bundled default fonts.
  interfaceFont*: EmbeddedAssetInstallResult
  interfaceItalicFont*: EmbeddedAssetInstallResult
  interfaceBoldFont*: EmbeddedAssetInstallResult
  monospaceFont*: EmbeddedAssetInstallResult

proc installKosmoBundledFonts*(
    cacheDirectory = "", roles = {nimkit.frUI, nimkit.frMonospace}
): KosmoBundledFontInstall =
  ## Install Kosmo's statically embedded fonts in NimKit's application cache.
  if nimkit.frUI in roles:
    result.interfaceFont = installEmbeddedZipAsset(
      initEmbeddedZipAsset(
        KosmoInterfaceFontFileName, KosmoInterfaceFontZip, KosmoInterfaceFontSha256
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )
    result.interfaceItalicFont = installEmbeddedZipAsset(
      initEmbeddedZipAsset(
        KosmoInterfaceItalicFontFileName, KosmoInterfaceItalicFontZip,
        KosmoInterfaceItalicFontSha256,
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )
    result.interfaceBoldFont = installEmbeddedZipAsset(
      initEmbeddedZipAsset(
        KosmoInterfaceBoldFontFileName, KosmoInterfaceBoldFontZip,
        KosmoInterfaceBoldFontSha256,
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )
  if nimkit.frMonospace in roles:
    result.monospaceFont = installEmbeddedZipAsset(
      initEmbeddedZipAsset(
        KosmoMonospaceFontFileName, KosmoMonospaceFontZip, KosmoMonospaceFontSha256
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )

func installedTypeface(installResult: EmbeddedAssetInstallResult): SystemTypeface =
  if installResult.succeeded():
    result = initSystemTypeface(installResult.path)

func installedInterfaceFaces(fonts: KosmoBundledFontInstall): nimkit.FontFaceSet =
  nimkit.FontFaceSet(
    regular: fonts.interfaceFont.installedTypeface(),
    italic: fonts.interfaceItalicFont.installedTypeface(),
    bold: fonts.interfaceBoldFont.installedTypeface(),
  )

proc kosmoBundledFontCatalog(
    fonts: KosmoBundledFontInstall
): seq[nimkit.FontCatalogEntry] =
  var paths: seq[string]
  for installed in [
    fonts.interfaceFont, fonts.interfaceItalicFont, fonts.interfaceBoldFont,
    fonts.monospaceFont,
  ]:
    if installed.succeeded():
      paths.add installed.path
  for entry in nimkit.buildFontCatalog(paths):
    var faces = entry.faces
    for faceIndex in 0 ..< faces.len:
      faces[faceIndex].identifier =
        "kosmo-bundled-font-face:" & faces[faceIndex].path.extractFilename()
      faces[faceIndex].fontName = entry.family
    result.add nimkit.initFontCatalogEntry(
      entry.family,
      entry.path,
      identifier = "kosmo-bundled-font:" & entry.family,
      searchText = entry.searchText & " bundled Kosmo",
      faces = faces,
    )

proc applyKosmoBundledFontDefaults(
    app: nimkit.Application, fonts: KosmoBundledFontInstall
) =
  if app.isNil:
    return
  var
    appearance = app.effectiveAppearance()
    builder = nimkit.initThemeBuilder(appearance.theme)
  for role in nimkit.FontRole:
    let
      installed =
        case role
        of nimkit.frUI: fonts.interfaceFont
        of nimkit.frMonospace: fonts.monospaceFont
      bundledFontName =
        case role
        of nimkit.frUI: KosmoInterfaceFontName
        of nimkit.frMonospace: KosmoMonospaceFontName
    if nimkit.fontOverrideFromEnv(role).isSome:
      builder.setFontName(role, nimkit.defaultFontName(role))
      builder.setFontFaces(role, nimkit.FontFaceSet())
    elif installed.succeeded():
      builder.setFontName(role, bundledFontName)
      let bundledFaces =
        case role
        of nimkit.frUI:
          fonts.installedInterfaceFaces()
        of nimkit.frMonospace:
          nimkit.FontFaceSet(regular: fonts.monospaceFont.installedTypeface())
      builder.setFontFaces(role, bundledFaces)
    else:
      builder.setFontName(role, nimkit.platformDefaultFontName(role))
      builder.setFontFaces(role, nimkit.FontFaceSet())
  appearance.theme = builder.finish()
  app.setAppearance(appearance)

func isAdaptiveMerendaTheme*(identifier: string): bool =
  ## Whether a merenda theme identifier selects the palette-following theme.
  case identifier.strip().toLowerAscii()
  of "macos-adaptive", "macosadaptive", "mac-os-adaptive", "adaptive", "adaptive-macos":
    true
  else:
    false

type KosmoInterfaceStyle* = object
  ## A Merenda theme and fonts layered over an inherited appearance.
  theme*: string ## Theme identifier; empty keeps the inherited theme.
  fontNames*: array[nimkit.FontRole, string] ## Empty names keep inherited fonts.
  fontFaces*: array[nimkit.FontRole, nimkit.FontFaceSet]
    ## Exact faces chosen this session; empty faces resolve `fontNames` by name.
  fontSize*: float32 ## Control text size; zero keeps the inherited size.

func isEmpty*(style: KosmoInterfaceStyle): bool =
  ## Whether the style leaves the inherited appearance unchanged.
  style.theme.len == 0 and style.fontSize <= 0.0'f32 and
    style.fontNames[nimkit.frUI].len == 0 and
    style.fontNames[nimkit.frMonospace].len == 0

func merendaInterfaceStyle(config: KosmoConfig): KosmoInterfaceStyle =
  result.theme = config.merendaTheme
  result.fontNames[nimkit.frUI] = config.merendaFont
  result.fontNames[nimkit.frMonospace] = config.merendaMonoFont
  result.fontSize = config.merendaFontSize

func kosmoInterfaceStyle*(config: KosmoConfig): KosmoInterfaceStyle =
  ## Return the persisted theme and fonts that apply only to Kosmo windows.
  result.theme = config.kosmoTheme
  result.fontNames[nimkit.frUI] = config.kosmoFont
  result.fontNames[nimkit.frMonospace] = config.kosmoMonoFont
  result.fontSize = config.kosmoFontSize

proc storeKosmoInterfaceStyle*(config: var KosmoConfig, style: KosmoInterfaceStyle) =
  ## Persist the Kosmo-only theme and font names; exact faces are session-only.
  config.kosmoTheme = style.theme
  config.kosmoFont = style.fontNames[nimkit.frUI]
  config.kosmoMonoFont = style.fontNames[nimkit.frMonospace]
  config.kosmoFontSize = style.fontSize

proc controlFontSize(appearance: nimkit.Appearance): float32 =
  appearance.resolveLength(
    nimkit.controlStyle(nimkit.srTextView),
    nimkit.StyleFontSize,
    nimkit.defaultFontSize(),
  )

proc interfaceStyle*(
    settings: nimkit.MerendaSettings, inherited: nimkit.Appearance
): KosmoInterfaceStyle =
  ## Return the parts of committed settings that differ from `inherited`.
  result.theme = settings.theme
  for role in nimkit.FontRole:
    let name = settings.appearance.fontName(role)
    if name != inherited.fontName(role):
      result.fontNames[role] = name
      result.fontFaces[role] = settings.appearance.fontFaces(role)
  let size = settings.appearance.controlFontSize()
  if size != inherited.controlFontSize():
    result.fontSize = size

proc composeAppearance*(
    inherited: nimkit.Appearance, style: KosmoInterfaceStyle, inheritsFontSize = false
): nimkit.Appearance =
  ## Layer `style` over `inherited`. A replacement theme keeps the inherited fonts,
  ## and keeps the inherited text size when `inheritsFontSize` is set.
  result =
    if style.theme.len > 0:
      nimkit.initAppearance(nimkit.initThemeByName(style.theme))
    else:
      inherited
  var builder = nimkit.initThemeBuilder(result.theme)
  if style.theme.len > 0:
    for role in nimkit.FontRole:
      builder.setFontName(role, inherited.fontName(role))
      builder.setFontFaces(role, inherited.fontFaces(role))
  for role in nimkit.FontRole:
    if style.fontNames[role].len == 0:
      continue
    builder.setFontName(role, style.fontNames[role])
    if style.fontFaces[role].regular.file.path.len > 0:
      builder.setFontFaces(role, style.fontFaces[role])
    else:
      builder.setFontFace(role, SystemTypeface())
  let fontSize =
    if style.fontSize > 0.0'f32:
      style.fontSize
    elif inheritsFontSize and style.theme.len > 0:
      inherited.controlFontSize()
    else:
      0.0'f32
  if fontSize > 0.0'f32:
    for role in KosmoConfigTextStyleRoles:
      builder[role, nimkit.StyleFontSize] = fontSize
  result.theme = builder.finish()

proc applyKosmoAppearance(app: nimkit.Application, config: KosmoConfig) =
  if app.isNil:
    return
  let style = config.merendaInterfaceStyle()
  if not style.isEmpty:
    app.setAppearance(app.effectiveAppearance().composeAppearance(style))
  app.invertScrolling = config.merendaInvertScrolling
  if config.merendaUiScale > 0.0'f32:
    app.uiScale = config.merendaUiScale
  app.merendaSettingsAutoSaveDefaults = config.merendaAutoSaveDefaults

proc configureKosmoApplicationAssets*(
    app: nimkit.Application, config: KosmoConfig, assetCacheDirectory: string
) =
  if app.isNil:
    return
  var roles: set[nimkit.FontRole]
  if config.merendaFont.len == 0 and nimkit.fontOverrideFromEnv(nimkit.frUI).isNone:
    roles.incl nimkit.frUI
  if config.merendaMonoFont.len == 0 and
      nimkit.fontOverrideFromEnv(nimkit.frMonospace).isNone:
    roles.incl nimkit.frMonospace
  let bundledFonts = installKosmoBundledFonts(assetCacheDirectory, roles)
  app.applyKosmoBundledFontDefaults(bundledFonts)
  app.applyKosmoAppearance(config)
  let configuredTheme =
    if config.merendaTheme.len > 0:
      config.merendaTheme
    else:
      nimkit.themeNameFromEnv()
  let normalizedTheme =
    case configuredTheme.strip().toLowerAscii()
    of "aqua":
      "aqua"
    of "macos", "mac-os", "mac", "modern-macos":
      "macos"
    of "macos-dark", "macosdark", "mac-os-dark", "dark-macos", "modern-macos-dark":
      "macos-dark"
    of "macos-adaptive", "macosadaptive", "mac-os-adaptive", "adaptive",
        "adaptive-macos":
      "macos-adaptive"
    of "nebula", "nebula-glass":
      "nebula"
    of "punch":
      "punch"
    of "peachy", "peach", "peachy83":
      "peachy"
    of "synthwave83", "synthwave-83", "synthwave":
      "synthwave83"
    else:
      "darkbsd"
  app.merendaSettingsThemeIdentifier = normalizedTheme
  app.merendaSettingsDefaults = nimkit.MerendaSettings(
    theme: normalizedTheme,
    appearance: app.effectiveAppearance(),
    invertScrolling: app.invertScrolling(),
    uiScale: app.uiScale(),
    autoSaveDefaults: config.merendaAutoSaveDefaults,
  )
  app.supplementalFontCatalogProvider = proc(): seq[nimkit.FontCatalogEntry] =
    installKosmoBundledFonts(assetCacheDirectory).kosmoBundledFontCatalog()
  app.icon = nimkit.newImageResourceFromData(KosmoIconPng, name = "kosmo-icon")
  app.aboutInfo = nimkit.ApplicationAboutInfo(
    version: KosmoVersion,
    buildVersion: KosmoGitHash,
    credits: KosmoAboutCredits,
    creditLinks: @[nimkit.ApplicationAboutLink(text: KosmoMoeUrl, url: KosmoMoeUrl)],
  )
