# Content themes

NimKit's `contentthemes` module provides plain value types for a shared text
palette. It has no editor-engine dependency. The same theme can color Markdown,
the built-in syntax editor, and a terminal:

```nim
import merenda/nimkit

let theme = loadContentTheme("/path/to/theme.toml")
let reader = newMarkdownView("# Hello")
let editor = newSynEditView("let answer = 42")
let terminal = newTerminalView()

reader.contentTheme = theme
editor.contentTheme = theme
terminal.contentTheme = theme
```

Assignment preserves the Markdown viewer's font and layout settings. For custom
presentation, use `style.applyContentTheme(theme)`, `theme.toSynEditTheme()`, or
`theme.toTerminalPalette()`.

Create a palette directly with `initContentPalette()`, change its fields, then
pass it to `initContentTheme("My theme", palette)`. All theme data is stored in
ordinary value objects.

## Files and discovery

`loadContentTheme(path)` loads a TOML file and raises a catchable exception for
missing files, malformed TOML, or invalid recognized colors. The minimal format is:

```toml
[Colors]
foreground = "#cdd6f4"
background = "#1e1e2e"
keyword = { fg = "#cba6f7" }
functionName = { fg = "#89b4fa" }
stringLit = { fg = "#a6e3a1" }
comment = { fg = "#6c7086" }
errorMessage = { fg = "#f38ba8" }
warnMessage = { fg = "#f9e2af" }
operator = { fg = "#89dceb" }
selectArea = { bg = "#585b70" }
```

Omitted colors retain the default palette. Additional keys can carry
application-specific settings; the content palette loader ignores them.

`discoverContentThemes(directory)` returns the default entry followed by valid
TOML themes sorted by name. Malformed files are skipped. Theme file identifiers
use normalized absolute paths, so applications can persist a selection.

`installBundledContentThemes()` installs the embedded palettes and upstream
licenses into NimKit's asset cache and returns their directory. Pass a cache
directory to choose an application-owned location. Discovery does not depend on
the source checkout or current working directory.

Kosmo uses this model for readers and terminals. Its Moe adapter, engine
configuration, and user-directory policy remain in Kosmo.
