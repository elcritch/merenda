## Embedded CSS theme definitions.

import ./[defaulttheme, themecore]
import ./private/bundledthemes

const MacOSCss = staticRead("stylesheets/macos.css")

var macOSCssCache {.threadvar.}: BundledThemeCache
var macOSDarkCssCache {.threadvar.}: BundledThemeCache

proc initMacOSTheme*(): Theme =
  bundledTheme(MacOSCss, initAquaTheme(), macOSCssCache)

const MacOSDarkCss = staticRead("stylesheets/macos-dark.css")

proc initMacOSDarkTheme*(): Theme =
  bundledTheme(MacOSDarkCss, initMacOSTheme(), macOSDarkCssCache)

registerThemeFactory("macos", initMacOSTheme)
registerThemeFactory("mac", initMacOSTheme)
registerThemeFactory("modern-macos", initMacOSTheme)
registerThemeFactory("macos-dark", initMacOSDarkTheme)
registerThemeFactory("dark-macos", initMacOSDarkTheme)
registerThemeFactory("modern-macos-dark", initMacOSDarkTheme)
