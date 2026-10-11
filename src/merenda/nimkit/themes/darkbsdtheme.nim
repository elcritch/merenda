## Embedded CSS theme definitions.

import ./[defaulttheme, themecore, macostheme]
import ./private/bundledthemes

const DarkBSDCss = staticRead("stylesheets/darkbsd.css")

var darkBSDCssCache {.threadvar.}: BundledThemeCache

proc initDarkBSDTheme*(): Theme =
  bundledTheme(DarkBSDCss, initMacOSDarkTheme(), darkBSDCssCache)

registerThemeFactory("darkbsd", initDarkBSDTheme)
registerThemeFactory("dark-bsd", initDarkBSDTheme)
registerThemeFactory("ruby-bsd", initDarkBSDTheme)
registerDefaultThemeFactory(initDarkBSDTheme)
