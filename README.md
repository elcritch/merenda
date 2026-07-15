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

Text rendering and measurement use the active theme's `StyleFontName` and
`StyleFontSize` values. To seed those theme defaults from the command line, set
`NIMKIT_FONT` to a bundled font name, system font name, or font file path. Set
`NIMKIT_FONT_SIZE` to override the default font size used by text and `em`
layout lengths:

```sh
NIMKIT_FONT=HackNerdFont-Regular.ttf NIMKIT_FONT_SIZE=15 nim r examples/quick_start.nim
```

`NIMKIT_FONT` and `NIMKIT_FONT_SIZE` take priority over `MERENDA_FONT` and
`MERENDA_FONT_SIZE`. If the font override cannot be resolved, NimKit falls back
to its bundled default font list. Per-role or per-class theme rules can override
the same values with `StyleFontName` and `StyleFontSize`.

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

## Examples

Run the combined controls demo:

```sh
nim r examples/controls_showcase.nim
```

Current examples are mirrored by `examples/all_compile.nim`:

- Basics: `quick_start`, `hello`, `button_counter`, `button_demo`, `todo_basic`, `todo_stack_drag`, `todo_table`, `controls_showcase`
- Controls: `textfield_demo`, `checkbox_demo`, `radio_demo`, `combobox_demo`, `combo_scroll_demo`, `stepper_demo`, `progress_indicator_demo`
- Layout and containers: `box_demo`, `splitview_demo`, `scrollview_demo`, `tabview_demo`, `layout_showcase`, `constraint_playground_demo`, `grid_preferences`
- Data and models: `table_demo`, `outline_demo`, `cascading_demo`, `collectionview_demo`, `documenttabs_demo`, `matrix_demo`, `menu_demo`, `modelcontrollers_demo`
- Application workflows: `panel_demo`, `document_workspace_demo`, `preferences_demo`, `viewcontroller_demo`, `view_inspector_demo`, `image_resources_demo`
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
