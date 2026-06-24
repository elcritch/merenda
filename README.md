# Merenda

<img width="2172" height="724" alt="merenda-github-banner-robot-chocolate" src="https://github.com/user-attachments/assets/f0a429f0-c5b5-49a4-819b-32d2cc454ac7" />

Merenda is an OpenStep-based GUI written in pure Nim. It uses [FigDraw](https://github.com/elcritch/figdraw/) for fast 2d rendering with shadows and gloss. It uses [siwin](https://github.com/levovix0/siwin) for cross-platform windowing and events. It currently aims to support macOS, FreeBSD, Linux, and Windows.

The main public module is `merenda/nimkit`. NimKit is designed around [Sigils](https://github.com/elcritch/sigils), which provides Objective-C-style dynamic selectors and protocols along with Qt-style signals and slots. NimKit uses selectors to build Cocoa-style responder/action patterns, while signals and slots cover observable control events. It also provides a theme and chrome system for high levels of customization.

<img width="877" height="744" alt="Screenshot 2026-06-23 at 9 49 13 PM" src="https://github.com/user-attachments/assets/8737afcd-bbcf-4ad1-a7d7-8e5574406c54" />

<img width="862" height="754" alt="Screenshot 2026-06-23 at 9 43 10 PM" src="https://github.com/user-attachments/assets/24514943-f0fa-46cd-a6fd-feb2327ad81c" />

## Why Try It?

- **Native Nim API**: windows, views, controls, geometry, colors, events, and
  theme data are Nim objects enhanced with dynamic protocols.
- **FigDraw rendering**: controls render into a FigDraw tree, making drawing
  testable and portable across supported FigDraw backends.
- **OpenStep based interaction model**: target/action, responders, first
  responder, key-view tabbing, focus rings, and platform key bindings are built in.
- **Useful controls already work**: buttons, toggle buttons, checkboxes, radio
  buttons, text fields, combo boxes, sliders, switches, scroll views, tabs, and
  tables.
- **Custom chrome and theming**: built-in controls use theme rules and chrome
  modules to support first-class visual customization.
- **Custom drawing is direct**: views can provide their own draw hook and render into a `DrawContext`.
- **Cassowary Base Constraint Engine**: [kiwiberry](https://github.com/elcritch/kiwiberry) is a full port of Kiwi C++ Cassowary engine. Nimkit provides convenient DSL on top for easy layout designs.

## Install

Add Merenda to your package:

```nim
requires "https://github.com/elcritch/merenda"
```

Then resolve dependencies with Atlas:

```sh
atlas install
```

## Quick Start

```nim
import merenda/nimkit
import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Counter", frame = initRect(100, 100, 320, 220))
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
  toGuide = root.contentLayoutGuide(initEdgeInsets(44.0, 44.0, 0.0, 44.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
```

Save that as a Nim file and run it with:

```sh
nim r examples/quick_start.nim
```

## Controls

NimKit ships the core controls needed for desktop-style interfaces:

- Windows and views: `newWindow`, `newView`, `newStackView`, `newScrollView`
- Text: `newTextField`, `newLabel`, `newTitleLabel`, `newStatusLabel`
- Buttons and choices: `newButton`, `newCheckBox`, `newRadioButton`
- Value controls: `newComboBox`, `newSlider`, `newSwitchButton`
- Containers: `newTabView`, `newTableView`, `newGridView`, `newFormView`

Controls use Cocoa-style target/action for commands:

```nim
let action = actionSelector("saveClicked")

proc save(sender: DynamicAgent) =
  if not sender.isNil:
    echo "save"

button.target = newActionTarget(action, save)
button.action = action
```

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

volume.connect(
  actionDidSend,
  volume,
  proc(slider: Slider, sender: DynamicAgent) {.slot.} =
    discard sender
    label.text = "Volume: " & $slider.value.int,
)
```

For larger examples, see:

- `examples/controls_showcase.nim`
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

appearance.setStyle(titleStyle, StyleFill, initColor(0.88, 0.92, 0.98))
appearance.setStyle(titleStyle, StyleTextColor, initColor(0.09, 0.14, 0.26))
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
proc drawBadge(context: DrawContext) =
  context.addRectangle(
    initRect(0, 0, 120, 32),
    initColor(0.18, 0.32, 0.55),
  )
  context.addText(
    initRect(12, 0, 96, 32),
    "Ready",
    initColor(1, 1, 1),
    taCenter,
  )
```

## Examples

Run the combined controls demo:

```sh
nim r examples/controls_showcase.nim
```

Other focused examples:

```sh
nim r examples/quick_start.nim
nim r examples/hello.nim
nim r examples/button_counter.nim
nim r examples/textfield_demo.nim
nim r examples/checkbox_demo.nim
nim r examples/radio_demo.nim
nim r examples/combobox_demo.nim
nim r examples/tabview_demo.nim
nim r examples/table_demo.nim
nim r examples/preferences_demo.nim
```

## Tests

Run the NimKit test suite through Atlas:

```sh
atlas-run tests
```
