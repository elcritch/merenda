## Punch's ink outlines, warm paper and orange accents, adapted from RUI2.

import ./[defaulttheme, themecore]
import ./private/bundledthemes

const PunchCss = staticRead("stylesheets/punch.css")

var punchCssCache {.threadvar.}: BundledThemeCache

proc initPunchTheme*(): Theme =
  ## Creates the bundled Punch theme, with bold captions and hard offset shadows.
  bundledTheme(PunchCss, initAquaTheme(), punchCssCache)

registerThemeFactory("punch", initPunchTheme)
