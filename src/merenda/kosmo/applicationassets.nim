## Embedded Kosmo assets, version metadata, and application font setup.

import std/[options, os, strutils]

from figdraw/extras/systemfonttypes import SystemTypeface, initSystemTypeface

import ../nimkit as nimkit
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
  KosmoVersion* = nimblePackageVersion(MerendaNimbleManifest)
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
  interfaceFont*: nimkit.EmbeddedAssetInstallResult
  interfaceItalicFont*: nimkit.EmbeddedAssetInstallResult
  interfaceBoldFont*: nimkit.EmbeddedAssetInstallResult
  monospaceFont*: nimkit.EmbeddedAssetInstallResult

proc installKosmoBundledFonts*(
    cacheDirectory = "", roles = {nimkit.frUI, nimkit.frMonospace}
): KosmoBundledFontInstall =
  ## Install Kosmo's statically embedded fonts in NimKit's application cache.
  if nimkit.frUI in roles:
    result.interfaceFont = nimkit.installEmbeddedZipAsset(
      nimkit.initEmbeddedZipAsset(
        KosmoInterfaceFontFileName, KosmoInterfaceFontZip, KosmoInterfaceFontSha256
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )
    result.interfaceItalicFont = nimkit.installEmbeddedZipAsset(
      nimkit.initEmbeddedZipAsset(
        KosmoInterfaceItalicFontFileName, KosmoInterfaceItalicFontZip,
        KosmoInterfaceItalicFontSha256,
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )
    result.interfaceBoldFont = nimkit.installEmbeddedZipAsset(
      nimkit.initEmbeddedZipAsset(
        KosmoInterfaceBoldFontFileName, KosmoInterfaceBoldFontZip,
        KosmoInterfaceBoldFontSha256,
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )
  if nimkit.frMonospace in roles:
    result.monospaceFont = nimkit.installEmbeddedZipAsset(
      nimkit.initEmbeddedZipAsset(
        KosmoMonospaceFontFileName, KosmoMonospaceFontZip, KosmoMonospaceFontSha256
      ),
      KosmoApplicationIdentifier,
      cacheDirectory,
    )

func installedTypeface(
    installResult: nimkit.EmbeddedAssetInstallResult
): SystemTypeface =
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

proc applyKosmoAppearance(app: nimkit.Application, config: KosmoConfig) =
  if app.isNil or (
    config.merendaTheme.len == 0 and config.merendaFont.len == 0 and
    config.merendaMonoFont.len == 0 and config.merendaFontSize <= 0.0'f32
  ):
    return
  let inheritedAppearance = app.effectiveAppearance()
  var appearance =
    if config.merendaTheme.len > 0:
      nimkit.initAppearance(nimkit.initThemeByName(config.merendaTheme))
    else:
      inheritedAppearance
  var builder = nimkit.initThemeBuilder(appearance.theme)
  if config.merendaTheme.len > 0:
    for role in nimkit.FontRole:
      builder.setFontName(role, inheritedAppearance.fontName(role))
      builder.setFontFaces(role, inheritedAppearance.fontFaces(role))
  if config.merendaFont.len > 0:
    builder.setFontName(nimkit.frUI, config.merendaFont)
    builder.setFontFace(nimkit.frUI, SystemTypeface())
  if config.merendaMonoFont.len > 0:
    builder.setFontName(nimkit.frMonospace, config.merendaMonoFont)
    builder.setFontFace(nimkit.frMonospace, SystemTypeface())
  if config.merendaFontSize > 0.0'f32:
    for role in KosmoConfigTextStyleRoles:
      builder[role, nimkit.StyleFontSize] = config.merendaFontSize
  appearance.theme = builder.finish()
  app.setAppearance(appearance)

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
  app.supplementalFontCatalogProvider = proc(): seq[nimkit.FontCatalogEntry] =
    installKosmoBundledFonts(assetCacheDirectory).kosmoBundledFontCatalog()
  app.icon = nimkit.newImageResourceFromData(KosmoIconPng, name = "kosmo-icon")
  app.aboutInfo = nimkit.ApplicationAboutInfo(
    version: KosmoVersion,
    buildVersion: KosmoGitHash,
    credits: KosmoAboutCredits,
    creditLinks: @[nimkit.ApplicationAboutLink(text: KosmoMoeUrl, url: KosmoMoeUrl)],
  )
