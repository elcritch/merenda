## Compile application CSS into the same snapshots as the bundled themes.

import ./[defaulttheme, themecore]
import ./private/csscompiler
export csscompiler.CssDiagnostic, csscompiler.CssThemeResult

proc parseCssTheme*(source: string, base: Theme = initTheme()): CssThemeResult =
  ## Appends CSS in the application layer. Use the original base to replace CSS.
  compileCssTheme(source, base)

proc loadCssTheme*(path: string, base: Theme = initTheme()): CssThemeResult =
  ## Reads a stylesheet. Filesystem failures raise `IOError` or `OSError`.
  parseCssTheme(readFile(path), base)
