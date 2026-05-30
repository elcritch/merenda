# Merenda

Merenda is a Nim-native UI toolkit built on FigDraw for drawing and `siwin` for
native windows and events.

The main public module is `merenda/nimkit`. NimKit is designed around plain Nim
objects, Cocoa-style responder/action patterns, and a small theme system that can
grow toward richer query-based styling later.

## Why Try It?

- **Native Nim API**: windows, views, controls, geometry, colors, events, and
  theme data are plain Nim types.
- **FigDraw rendering**: controls render into a FigDraw tree, making drawing
  testable and portable across supported FigDraw backends.
- **Cocoa-inspired interaction model**: target/action, responders, first
  responder, key-view tabbing, focus rings, and platform key bindings are built
  in.
- **Useful controls already work**: buttons, toggle buttons, checkboxes, radio
  buttons, text fields, and combo boxes.
- **Custom drawing is direct**: views can provide their own draw hook and render
  into a `DrawContext`.

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
  window = newWindow(100, 100, 320, 220, "Counter")
  root = newView(0, 0, 320, 220)
  label = newTextField(36, 46, 240, 28, "Clicked 0 times")
  button = newButton(36, 98, 140, 34, "Click")
  clickAction = actionSelector("counterClicked")

var clicks = 0

proc onClick(sender: DynamicAgent) =
  if not sender.isNil:
    inc clicks
    label.setStringValue("Clicked " & $clicks & " times")

label.setEditable(false)
label.setSelectable(false)
button.setTarget(newActionTarget(clickAction, onClick))
button.setAction(clickAction)

root.addSubview(label)
root.addSubview(button)
window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
```

Save that as a Nim file and run it with:

```sh
nim r counter.nim
```

## Controls

NimKit currently includes:

- `newWindow`, `newView`
- `newTextField`
- `newButton`
- `newCheckBox`
- `newRadioButton`
- `newComboBox`

Controls use target/action for user commands:

```nim
let action = actionSelector("saveClicked")

proc save(sender: DynamicAgent) =
  if not sender.isNil:
    echo "save"

button.setTarget(newActionTarget(action, save))
button.setAction(action)
```

Buttons can behave as push, toggle, checkbox, or radio controls:

```nim
button.setButtonType(btToggle)
button.setAllowsMixedState(true)
```

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

title.setStyleClasses(["title"])
root.setAppearance(appearance)
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
nim r examples/nimkit_controls_showcase.nim
```

Other focused examples:

```sh
nim r examples/nimkit_hello.nim
nim r examples/nimkit_button_counter.nim
nim r examples/nimkit_textfield_demo.nim
nim r examples/nimkit_checkbox_demo.nim
nim r examples/nimkit_radio_demo.nim
nim r examples/nimkit_combobox_demo.nim
```

## Tests

Run the NimKit test suite and compile the NimKit examples:

```sh
nim test
```
