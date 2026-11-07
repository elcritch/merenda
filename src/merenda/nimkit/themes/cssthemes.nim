## Compile application CSS into the same snapshots as the bundled themes.

import std/[os, strutils]
import ./[adaptivetheme, defaulttheme, themecore]
import ./private/csscompiler
export csscompiler.CssDiagnostic, csscompiler.CssThemeResult

proc parseCssTheme*(source: string, base: Theme = initTheme()): CssThemeResult =
  ## Appends CSS in the application layer. Use the original base to replace CSS.
  compileCssTheme(source, base)

proc loadCssTheme*(path: string, base: Theme = initTheme()): CssThemeResult =
  ## Reads a stylesheet. Filesystem failures raise `IOError` or `OSError`.
  parseCssTheme(readFile(path), base)

const BuiltinThemeCssDirectory* = currentSourcePath().parentDir() / "stylesheets"

proc themeCssDirectory*(): string =
  ## Source CSS directory used by Settings' Refresh theme button.
  getEnv("MERENDA_THEME_CSS_DIR", BuiltinThemeCssDirectory)

proc reloadThemeCss*(name: string, directory = themeCssDirectory()): CssThemeResult =
  ## Rebuild a bundled theme from its complete on-disk inheritance chain.
  ## Deleted declarations disappear; native font and chrome resources remain.
  ## The caller applies the snapshot only when diagnostics is empty.
  var files = @["base", "aqua"]
  var adaptiveCss = ""
  case name.strip().toLowerAscii()
  of "aqua":
    discard
  of "macos", "mac":
    files.add "macos"
  of "macos-dark", "dark-macos":
    files.add ["macos", "macos-dark"]
  of "macos-adaptive", "adaptive", "adaptive-macos":
    files.add ["macos", "macos-dark"]
    adaptiveCss = adaptiveThemeCss(adaptiveContentPalette())
  of "darkbsd", "dark-bsd":
    files.add ["macos", "macos-dark", "darkbsd"]
  of "banner", "nebula", "peachy", "punch", "synthwave83":
    files.add name.toLowerAscii().strip()
  else:
    raise newException(ValueError, "Unknown CSS theme: " & name)
  var source: string
  for file in files:
    source.add readFile(directory / (file & ".css"))
    source.add '\n'
  source.add adaptiveCss
  compileCssTheme(source, initThemeResources(), sroTheme)
