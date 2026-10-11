## Embedded CSS theme definitions.

import ./[defaulttheme, themecore]
import ./private/bundledthemes

const NebulaCss = staticRead("stylesheets/nebula.css")

var nebulaCssCache {.threadvar.}: BundledThemeCache

proc initNebulaTheme*(): Theme =
  bundledTheme(NebulaCss, initAquaTheme(), nebulaCssCache)

registerThemeFactory("nebula", initNebulaTheme)
registerThemeFactory("nebula-glass", initNebulaTheme)
