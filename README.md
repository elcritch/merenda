# Merenda

<img width="2172" height="724" alt="merenda-github-banner-robot-chocolate" src="https://github.com/user-attachments/assets/f0a429f0-c5b5-49a4-819b-32d2cc454ac7" />

Merenda is a modern desktop GUI toolkit based on Cocoa and OpenStep, written in pure Nim. It uses [FigDraw](https://github.com/elcritch/figdraw/) for fast 2D rendering with shadows and gloss, and [siwin](https://github.com/levovix0/siwin) for cross-platform windowing and events. It currently aims to support macOS, FreeBSD, Linux, and Windows.

The main public module is `merenda/nimkit`. NimKit is designed around [Sigils](https://github.com/elcritch/sigils), which provides Objective-C-style dynamic selectors and protocols along with Qt-style signals and slots. NimKit uses selectors to build Cocoa-style responder/action patterns, while signals and slots cover observable control events. It also provides model controllers, a theme system, and custom chrome for desktop application workflows.

<img width="400"  alt="Screenshot 2026-06-23 at 9 49 13 PM" src="https://github.com/user-attachments/assets/8737afcd-bbcf-4ad1-a7d7-8e5574406c54" /> <img width="400" alt="Screenshot 2026-06-23 at 9 43 10 PM" src="https://github.com/user-attachments/assets/24514943-f0fa-46cd-a6fd-feb2327ad81c" />

## Why Try It?

- **Native Nim**: The power and structure of Cocoa and OpenStep, implemented in a modern systems language.
- **Useful controls already work**: buttons, toggle buttons, checkboxes, radio
  buttons, text fields, combo boxes, menus, sliders, steppers, switches,
  scroll views, tabs, tables, outlines, collection views, matrices, and
  document tabs.
- **Model-backed views**: array, tree, and selection controllers can drive
  tables, outlines, cascading views, combo boxes, document tabs, menus, and
  matrices.
- **Custom chrome and theming**: built-in controls use theme rules and chrome
  modules to support first-class visual customization.
- **OpenStep based interaction model**: target/action, responders, first
  responder, key-view tabbing, focus rings, and platform key bindings are built in.
- **Custom drawing is direct**: views can provide their own draw hook and render into a `DrawContext`.
- **FigDraw rendering**: controls render into a FigDraw tree, making drawing
  testable and portable across supported FigDraw backends.
- **Cassowary constraint engine**: [kiwiberry](https://github.com/elcritch/kiwiberry) is a full port of the Kiwi C++ Cassowary engine. NimKit provides a convenient layout DSL on top.

## Install

Add Merenda to your package:

```nim
requires "https://github.com/elcritch/merenda"
```

Then install dependencies with Atlas:

```sh
atlas install --update
```

Note: You'll want to install the most recent [Atlas](https://github.com/nim-lang/atlas#installation), where curl install is the easiest. Nimble should also work but it's not tested currently.

## Quick Start

```nim
import merenda/nimkit
import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Counter", frame = rect(100, 100, 320, 220))
  root = newView()
  layout = newStackView(laVertical)
  label = newStatusLabel("Clicked 0 times")
  button = newButton("Click")
  clickAction = actionSelector("counterClicked")

var clicks = 0

proc onClick(sender: DynamicAgent) =
  if not sender.isNil:
    inc clicks
    label.text = "Clicked " & $clicks & " times"

button.target = newActionTarget(clickAction, onClick)
button.action = clickAction

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(label, button)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(44.0, 44.0, 0.0, 44.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root)
```

The same example lives in `examples/quick_start.nim` and can be run with:

```sh
nim r examples/quick_start.nim
```

Use `app.showWindow(window, root)` instead when you want to install and show a
window without entering the application run loop. Pass an initial responder as
the third argument, such as `app.runWindow(window, root, textField)`, when a
specific control should receive focus first.

The application run loop keeps NimKit views, responders, signal-slot dispatch,
animations, native windows, and platform services on the main thread. When the
selected FigDraw backend supports it, rendering runs on a dedicated thread and
receives moved render trees through bounded latest-frame channels; unsupported
backends render directly on the main thread. Merenda builds with threads and ARC
enabled, as configured by the repository's `config.nims`.

Constraint-wrapped views expose their minimum layout through `fittingSize()`.
Set `window.automaticallyAdjustsContentMinSize = true` to keep a resizable
window from becoming smaller than that fitting size. Tab views include the
largest fitting width and height required by any of their pages, so switching
pages does not reveal clipped content.

Merenda apps automatically use the native window content scale. To force a
specific UI scale for development or display debugging, set `UISCALE` or
`NIMKIT_UISCALE`:

```sh
UISCALE=1.5 nim r examples/quick_start.nim
```

`NIMKIT_UISCALE` and `MERENDA_UISCALE` take priority over `UISCALE`, and
FigDraw's legacy `HDI` variable remains a fallback.

Text rendering and measurement use two global font roles: `frUI` for normal
interface text and `frMonospace` for code and fixed-width text. Applications and
the settings panel only choose those two fonts. Script, symbol, and emoji faces
are selected automatically from the bundled and installed system fonts.

Set `NIMKIT_FONT` and `NIMKIT_MONOSPACE_FONT` to seed the two roles with a
bundled font name, system font name, or font file path. `NIMKIT_FONT_SIZE`
overrides the default size used by text and `em` layout lengths:

```sh
NIMKIT_FONT=IBMPlexSans-Regular.ttf \
NIMKIT_MONOSPACE_FONT=HackNerdFont-Regular.ttf \
NIMKIT_FONT_SIZE=15 nim r examples/quick_start.nim
```

The `NIMKIT_` variables take priority over their `MERENDA_FONT`,
`MERENDA_MONOSPACE_FONT`, and `MERENDA_FONT_SIZE` aliases. Font roles can also
be configured directly on a theme:

```nim
var theme = initTheme()
theme.setFontName(frUI, "IBMPlexSans-Regular.ttf")
theme.setFontName(frMonospace, "HackNerdFont-Regular.ttf")
root.appearance = initAppearance(theme)
```

Merenda follows FigDraw's resolved `figdrawTextBackend` constant. The default
Pixie backend is lightweight and supports the Interface and Monospace roles.
The HarfBuzzy and hybrid backends additionally detect Unicode scripts, preserve
bidirectional runs, and choose fallback faces automatically. A FigDraw package
feature or string-define can select a backend; application code should inspect
`figdrawTextBackend` rather than the selection mechanism.

The process locale supplies the default BCP 47 language preference. Attributed
text can override it when the selected backend supports language-specific
shaping or CJK font choice:

```nim
var attributes = defaultTextAttributes(language = initLanguageTag("ja-JP"))
textView.textStorage().setAttributes(initTextRange(0, 5), attributes)
```

With the HarfBuzzy backend, HarfBuzz reads the font tables, detects scripts,
chooses fallbacks, and shapes glyph ids. FigDraw obtains their outlines through
HarfBuzz draw callbacks and uses Pixie's path/image machinery to rasterize them.
This currently produces monochrome outlines; bitmap, SVG, and COLR color emoji
paint is not yet rendered. Per-role or per-class rules can still override
`StyleFontName`, `StyleFontSize`, and `StyleLanguage`.

Fallback fonts are loaded lazily, only after the selected UI or monospace font
is missing a codepoint. Applications can extend or replace the runtime BCP 47
language/script table. Categories use lowercase ISO 15924 script tags, plus
`symbols`, `emoji`, and `*`:

```nim
addFontFallbackGroup(
  "th", "thai", ["Noto Sans Thai", "Leelawadee UI"], prepend = true
)
setFontFallbackGroups("x-demo", "latn", @[@["Demo Latin"]])
```

Each inner group contains alternative names for one font choice. Groups are
tried in order, one at a time, until the missing text is covered. Language keys
match BCP 47 prefixes, so a rule for `th` also applies to `th-TH`.

Run the font fallback example to see both user-selectable roles alongside
automatic language, symbol, and outline-emoji fallback:

```sh
nim r -d:figdrawTextBackend=harfbuzzy examples/font_fallback_demo.nim
```

For a flatter, modern macOS-style appearance, select the built-in `macos` theme
at startup or construct it directly:

```sh
NIMKIT_THEME=macos nim r examples/controls_showcase.nim
```

```nim
root.appearance = initAppearance(initMacOSTheme())
```

The `mac` and `modern-macos` names are aliases. The theme is platform-neutral,
so Linux applications can use the same look while macOS continues to use its
native application menu bar.

Use `macos-dark` for the matching dark appearance:

```sh
NIMKIT_THEME=macos-dark nim r examples/controls_showcase.nim
```

```nim
root.appearance = initAppearance(initMacOSDarkTheme())
```

The `dark-macos` and `modern-macos-dark` names are aliases.

Compose Finder-style icon rows with `IconLabel`. The icon is a Unicode glyph,
rendered through the same FigDraw glyph atlas as other text, and can have an
independent semantic tint:

```nim
let downloads = newIconLabel("↓", "Downloads", color(0.04, 0.52, 1.0))
let shared = newIconLabel("⌘", "Shared", color(0.0, 0.62, 0.78))
```

Omit the color to use the active theme's icon accent.

## Controls

NimKit ships the core controls needed for desktop-style interfaces:

- Windows and views: `newApplication`, `sharedApplication`, `newWindow`, `newView`
- Layout and containers: `newStackView`, `newGridView`, `newFormView`, `newSplitView`, `newScrollView`, `newTabView`, `newBox`, `newGroupBox`, `newSeparatorBox`
- Text: `newTextField`, `newLabel`, `newTitleLabel`, `newStatusLabel`, `newTextEditor`, `newMonoTextEditor`
- Buttons and choices: `newButton`, `newCheckBox`, `newRadioButton`, `newComboBox`, `newPopupMenuButton`, `newMenu`, `newMenuItem`
- Value and status controls: `newSlider`, `newStepper`, `newSwitchButton`, `newProgressIndicator`
- Data and navigation views: `newTableView`, `newOutlineView`, `newCascadingView`, `newCollectionView`, `newDocumentTabs`, `newButtonMatrix`, `newRadioMatrix`

Controls use Cocoa-style target/action for commands:

```nim
let action = actionSelector("saveClicked")

proc save(sender: DynamicAgent) =
  if not sender.isNil:
    echo "save"

button.target = newActionTarget(action, save)
button.action = action
```

Application menus use the same `Menu` and `MenuItem` tree on every platform.
Assigning the tree to `app.mainMenu` publishes a native menu in the macOS menu
bar, including submenus, separators, validation, state, and key equivalents.
On macOS, `newApplication` and `sharedApplication` start with the standard
application, File, Edit, Window, and Help menus. The application menu includes
About, Services, Hide, and Quit; the Window menu retains Minimize and Zoom while
automatically listing open windows. Pass an application name to
`newApplication("My App")` when the executable name is not the desired display
name. Call `app.installStandardMainMenu()` to restore the standard tree after
replacing `app.mainMenu`, or add application-specific top-level menus directly
to the existing tree.

When an application first pumps a frame, NimKit installs a default local Sigils
scheduler unless the thread already has one. Set
`app.automaticallyStartsLocalSigilThread = false` before running to opt out;
NimKit never replaces or removes an existing local scheduler.

The default `mmpAutomatic` presentation uses that native menu when available.
Applications can switch `app.mainMenuPresentation` at runtime between
`mmpNative` and `mmpInWindow`; `app.usesNativeMainMenu()` reports the effective
choice. For a standard window, wrap its content with
`newMenuRootView(app.mainMenu(), content)`. The root owns a `MenuBar` and hides
or shows it as the presentation changes. Standalone `newMenuBar` presenters
follow the same policy, and layout containers such as `StackView` automatically
omit the hidden menu bar.

Buttons can behave as push, toggle, checkbox, or radio controls:

```nim
let toggle = newButton("Enable Sync")
toggle.buttonType = btToggle
toggle.allowsMixedState = true
toggle.state = bsOn
```

Controls that expose continuous state can also emit signals:

```nim
let volume = newSlider(0.0, 100.0, 42.0)
let label = newStatusLabel("Volume: 42")

proc updateVolume(slider: Slider, sender: DynamicAgent) {.slot.} =
  discard sender
  label.text = "Volume: " & $slider.value.int

volume.connect(actionDidSend, volume, updateVolume)
```

Tables and choice controls can share `ArrayController` data:

```nim
let
  items = @[
    modelItem(
      "ada",
      objectValue = toObj("Ada"),
      fields = [
        modelField("name", toObj("Ada")),
        modelField("score", toObj(31)),
      ],
    ),
    modelItem(
      "grace",
      objectValue = toObj("Grace"),
      fields = [
        modelField("name", toObj("Grace")),
        modelField("score", toObj(45)),
      ],
    ),
  ]
  columns = @[
    modelColumn("person", "Person", "name", 120.0),
    modelColumn("rank", "Score", "score", 64.0),
  ]
  controller = newArrayController(items, columns)
  table = newTableView()
  combo = newComboBox()

bindTableView(table, controller)
bindComboBox(combo, controller)
```

For larger examples, see:

- `examples/controls_showcase.nim`
- `examples/modelcontrollers_demo.nim`
- `examples/preferences_demo.nim`
- `examples/table_demo.nim`
- `examples/tabview_demo.nim`

## Keyboard And Focus

NimKit supports first responder focus, tab navigation, and platform-aware text
editing shortcuts. macOS defaults to Cocoa-style bindings such as control-A,
control-E, option-left, and option-right. Windows and Linux/BSD use their own
default binding profiles.

```nim
discard window.selectNextKeyView()
discard window.makeFirstResponder(textField)
```

Buttons can be tab-selected and activated from the keyboard.

## Resource-Backed UI

NimKit can encode plain resource records as canonical CBOR, validate them without
constructing UI identities, and explicitly instantiate view/controller trees,
windows, panels, menus, commands, images, localized strings, key bindings, theme
fragments, layout guides, and constraints.

```nim
import merenda/nimkit/resources

let loaded = loadResourceBundle("ui/main.cbor")
if loaded.loaded:
  let context = initResourceInstantiationContext(
    locale = "en", assetBasePath = "ui"
  )
  let construction = loaded.bundle.instantiateResources(context)
  if construction.instantiated:
    let window = construction.instance.window(resourceId("main.window"))
```

Custom view/controller kinds and Sigils property protocols can be added through
`ResourceRegistry`; compatible property getter/setter pairs are discovered and bound
automatically. The built-in resource-editor palette includes views, controls,
buttons, check/radio buttons, text fields, labels, image/stack views, switches,
progress indicators, boxes, and split views. Its inspector uses checkboxes for
booleans, registry-backed combo boxes for enum properties, and popup color wells for
colors. The Tekton builder and its reusable editor API live under
`src/merenda/tekton/`. See
[docs/resources.md](docs/resources.md) and `examples/resource_ui_demo.nim` for the
format and construction workflow.

## Styling

Use an `Appearance` to override theme tokens or style selectors. Views can carry
style classes, giving the theme system stable targets without requiring CSS.

```nim
let titleStyle = initStyleSelector(srTextField, classes = @["title"])
var appearance = initAppearance()

appearance.setStyle(titleStyle, StyleFill, fill(color(0.88, 0.92, 0.98)))
appearance.setStyle(titleStyle, StyleTextColor, color(0.09, 0.14, 0.26))
appearance.setStyle(titleStyle, StyleCornerRadius, 6.0)

title.styleClasses = ["title"]
root.appearance = appearance
```

Appearance inherits through the app, window, and view hierarchy, so local
overrides can be scoped to a whole window or a single subtree.

Document tabs expose their active marker and close-button placement through the
same look-and-feel rules:

```nim
var appearance = initAppearance()
let documentTab = initStyleSelector(srDocumentTab)

appearance.setStyle(
  documentTab, StyleSelectionIndicatorPosition, styleKeyword(dtipTop)
)
appearance.setStyle(
  documentTab, StyleSelectionIndicatorInsets, insets(3.0, 12.0, 0.0, 12.0)
)
appearance.setStyle(documentTab, StyleSelectionIndicatorSize, 2.0)
appearance.setStyle(
  documentTab, StyleCloseButtonPosition, styleKeyword(dtcbRight)
)
```

The marker position can be `dtipTop`, `dtipBottom`, `dtipLeft`, `dtipRight`, or
`dtipNone`. Set `StyleSelectionIndicatorFill` and
`StyleSelectionIndicatorCornerRadius` to customize its color and shape. With
`dtipNone`, the selected `StyleFill`, `StyleBorderColor`, `StyleBorderWidth`,
and `StyleCornerRadius` rules can provide filled, outlined, pill, or segmented
tab styles without an additional marker. The default and macOS themes place
close buttons on the left.

## Drawing

Custom views draw through a `DrawContext`, which wraps the active FigDraw render
list, local bounds, visible rect, and coordinate conversion helpers.

```nim
type BadgeView = ref object of View

protocol BadgeDrawing of ViewDrawingProtocol:
  method draw(view: BadgeView, context: DrawContext) =
    context.addRectangle(
      rect(0, 0, 120, 32),
      fill(color(0.18, 0.32, 0.55)),
    )
    context.addText(
      rect(12, 0, 96, 32),
      "Ready",
      color(1, 1, 1),
      taCenter,
    )

proc newBadgeView(frame: Rect): BadgeView =
  result = BadgeView()
  initViewFields(result, frame)
  discard result.withProtocol(BadgeDrawing)
```

For retained, browser-style drawing, use `CanvasView` and its `"2d"` context:

```nim
let
  canvas = newCanvasView(rect(0, 0, 640, 420))
  context = canvas.getContext("2d")

context.fillStyle = "rebeccapurple"
context.fillRect(24, 24, 120, 72)
context.beginPath()
context.moveTo(220, 30)
context.lineTo(280, 130)
context.lineTo(170, 100)
context.closePath()
context.fill()
```

Primitive operations are retained as FigDraw drawables, arbitrary filled paths
are converted to MTSDF resources, and `drawImage` retains an `ImageResource`.
Run `nim r examples/canvas_demo.nim` for a tool palette with drag drawing,
color and stroke controls, image stamping, clearing, and undo.

## Examples

Run the combined controls demo:

```sh
nim r examples/controls_showcase.nim
```

Current examples are mirrored by `examples/all_compile.nim`:

- Basics: `quick_start`, `hello`, `button_counter`, `button_demo`, `todo_basic`, `todo_stack_drag`, `todo_table`, `controls_showcase`
- Controls: `textfield_demo`, `checkbox_demo`, `radio_demo`, `combobox_demo`, `combo_scroll_demo`, `stepper_demo`, `progress_indicator_demo`
- Layout and containers: `box_demo`, `splitview_demo`, `scrollview_demo`, `tabview_demo`, `layout_showcase`, `constraint_playground_demo`, `grid_preferences`
- Data and models: `table_demo`, `treeview_demo`, `outline_demo`, `cascading_demo`, `collectionview_demo`, `documenttabs_demo`, `matrix_demo`, `menu_demo`, `modelcontrollers_demo`
- Application workflows: `panel_demo`, `document_workspace_demo`, `preferences_demo`, `viewcontroller_demo`, `view_inspector_demo`
- Drawing and media: `canvas_demo`, `svg_viewer_demo`, `image_resources_demo`
- Text and animation: `texteditor_demo`, `synedit_demo`, `monotext_demo`, `animation_demo`

Run any focused example with:

```sh
nim r examples/<name>.nim
```

## Tests

Run the NimKit test suite through Atlas:

```sh
atlas-run tests
```

Compile-check the example import bundle with:

```sh
atlas-run tests --compile-only examples/all_compile.nim
```
