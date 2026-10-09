## Embedded CSS theme definitions.

import ./[defaulttheme, themecore]
import ./private/bundledthemes

const PeachyCss = staticRead("stylesheets/peachy.css")

var peachyCssCache {.threadvar.}: BundledThemeCache

proc initPeachyTheme*(): Theme =
  bundledTheme(PeachyCss, initAquaTheme(), peachyCssCache)

registerThemeFactory("peachy", initPeachyTheme)
registerThemeFactory("peach", initPeachyTheme)
registerThemeFactory("peachy83", initPeachyTheme)
