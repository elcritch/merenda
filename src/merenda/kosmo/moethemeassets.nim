## Embedded Moe themes installed as TOML files for Moe's theme loader.

import std/[os, tempfiles]

from ../nimkit/foundation/assetcache import nimkitAssetCacheDirectory

template embedTheme(name: string): untyped =
  (
    fileName: name,
    contents:
      staticRead(currentSourcePath().parentDir / "../../../data/moe/themes" / name),
  )

template embedLicense(name: string): untyped =
  (
    fileName: name,
    contents: staticRead(
      currentSourcePath().parentDir / "../../../data/moe/themes/licenses" / name
    ),
  )

const EmbeddedMoeThemes = [
  embedTheme("catppuccin-latte.toml"),
  embedTheme("catppuccin-mocha.toml"),
  embedTheme("cyberdream-dark.toml"),
  embedTheme("cyberdream-light.toml"),
  embedTheme("dayfox.toml"),
  embedTheme("everforest-dark.toml"),
  embedTheme("everforest-light.toml"),
  embedTheme("gitHub-dark.toml"),
  embedTheme("gitHub-light.toml"),
  embedTheme("gruvbox-material-dark.toml"),
  embedTheme("gruvbox-material-light.toml"),
  embedTheme("kanagawa-lotus.toml"),
  embedTheme("kanagawa-wave.toml"),
  embedTheme("nightfox.toml"),
  embedTheme("one-dark.toml"),
  embedTheme("one-light.toml"),
  embedTheme("rose-pine-dawn.toml"),
  embedTheme("rose-pine.toml"),
  embedTheme("solarized-dark.toml"),
  embedTheme("solarized-light.toml"),
  embedTheme("tokyo-night-day.toml"),
  embedTheme("tokyo-night-moon.toml"),
]

const EmbeddedMoeThemeLicenses = [
  embedLicense("catppuccin.txt"),
  embedLicense("cyberdream.txt"),
  embedLicense("everforest.txt"),
  embedLicense("github.txt"),
  embedLicense("gruvbox.txt"),
  embedLicense("kanagawa.txt"),
  embedLicense("nightfox.txt"),
  embedLicense("onedark.txt"),
  embedLicense("rose.txt"),
  embedLicense("solarized.txt"),
  embedLicense("tokyo.txt"),
]

proc installTheme(directory, fileName, contents: string) =
  let targetPath = directory / fileName
  if fileExists(targetPath) and readFile(targetPath) == contents:
    return

  let output = createTempFile(".kosmo-theme-", ".part", directory)
  output.cfile.close()
  try:
    writeFile(output.path, contents)
    moveFile(output.path, targetPath)
  finally:
    removeFile(output.path)

proc installBundledMoeThemes*(cacheDirectory = ""): string =
  ## Return the cache directory containing Kosmo's embedded Moe themes.
  ## Missing or altered cache files are restored from the embedded originals.
  ## An unwritable cache leaves existing files available for discovery.
  let cacheRoot =
    if cacheDirectory.len > 0:
      cacheDirectory
    else:
      nimkitAssetCacheDirectory("kosmo")
  result = cacheRoot / "moe" / "themes"
  try:
    createDir(result)
    for theme in EmbeddedMoeThemes:
      installTheme(result, theme.fileName, theme.contents)
    let licenseDirectory = result / "licenses"
    createDir(licenseDirectory)
    for license in EmbeddedMoeThemeLicenses:
      installTheme(licenseDirectory, license.fileName, license.contents)
  except OSError, IOError:
    discard
