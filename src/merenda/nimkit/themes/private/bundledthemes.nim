## Strict construction for checked-in stylesheets; runtime file loading remains explicit.

import ../themecore
import ./csscompiler

type BundledThemeCache* = object
  theme: Theme
  baseGeneration: ThemeGeneration

proc bundledTheme*(source: string, base: Theme): Theme =
  let parsed = compileCssTheme(source, base, sroTheme)
  if parsed.diagnostics.len > 0:
    raise newException(ValueError, "Invalid bundled theme CSS: " & $parsed.diagnostics)
  parsed.theme

proc bundledTheme*(source: string, base: Theme, cache: var BundledThemeCache): Theme =
  ## Callers own one cache per embedded stylesheet and per thread.
  if not cache.theme.isInitialized or cache.baseGeneration != base.generation:
    cache.theme = bundledTheme(source, base)
    cache.baseGeneration = base.generation
  cache.theme
