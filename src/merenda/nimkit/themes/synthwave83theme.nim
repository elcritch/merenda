## Embedded CSS theme definitions.

import ./[defaulttheme, themecore]
import ./private/bundledthemes

const Synthwave83Css = staticRead("stylesheets/synthwave83.css")

var synthwave83CssCache {.threadvar.}: BundledThemeCache

proc initSynthwave83Theme*(): Theme =
  bundledTheme(Synthwave83Css, initAquaTheme(), synthwave83CssCache)

registerThemeFactory("synthwave83", initSynthwave83Theme)
registerThemeFactory("synthwave", initSynthwave83Theme)
