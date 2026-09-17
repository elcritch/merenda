## Embedded Moe themes installed as TOML files for Moe's theme loader.

import std/[os, tempfiles]

from ../nimkit/foundation/assetcache import nimkitAssetCacheDirectory

template embedTheme(name: string): untyped =
  (
    fileName: name,
    contents:
      staticRead(currentSourcePath().parentDir / "../../../data/moe/themes" / name),
  )

const EmbeddedMoeThemes = [
  embedTheme("catppuccin-latte.toml"),
  embedTheme("catppuccin-mocha.toml"),
  embedTheme("kanagawa-wave.toml"),
  embedTheme("one-dark.toml"),
  embedTheme("tokyo-night-moon.toml"),
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
  except OSError, IOError:
    discard
