# Merenda

<img width="2172" height="724" alt="Merenda banner" src="https://github.com/user-attachments/assets/f0a429f0-c5b5-49a4-819b-32d2cc454ac7" />

Merenda is a desktop GUI toolkit written in Nim, inspired by Cocoa and OpenStep.
It gives you buttons, text editors, tables, menus, and layouts for building desktop
apps, with themes you can change to suit your app. Its public module is called
NimKit: `import merenda/nimkit`.

The project is under active development, targeting macOS, Linux, FreeBSD, and
Windows. [Kosmo](#kosmo), a code editor built with Merenda, is a way to try it
without writing any code.

## How it looks

Merenda draws its own controls, so you can use the same theme across platforms.
Choose a familiar macOS look, glossy Aqua buttons, or something more colorful.
DarkBSD is the default.

<img width="800" alt="Merenda with the modern macOS theme" src="https://github.com/user-attachments/assets/4289a99e-be27-4e06-9d42-3d1a57e82987" />
<img width="400" alt="Merenda with the Aqua theme" src="https://github.com/user-attachments/assets/f2d8143b-e6ac-4ce0-b2eb-90b5c2fa0183" />
<img width="400" alt="Merenda with the Synthwave83 theme" src="https://github.com/user-attachments/assets/5b81393b-ce0a-439f-98c4-da0f721ad57d" />
<img width="400" alt="Merenda with the Peachy theme" src="https://github.com/user-attachments/assets/04f6dea9-c695-481a-a53a-b7f3f0eb61a1" />
<img width="400" alt="Merenda with the DarkBSD theme" src="https://github.com/user-attachments/assets/70674e38-e678-4fb6-8b0b-93da41d9f7fd" />

## Install and run Merenda

You'll need Nim 2.2.6 or newer, a C compiler, Git, and
[Atlas](https://github.com/nim-lang/atlas#installation) to install the Nim
dependencies. On Linux and FreeBSD, you'll also need the system libraries for
your windowing and graphics backend; Merenda uses Siwin for windows and FigDraw
for rendering.

To try the examples, clone the repository and run the controls showcase:

```sh
git clone https://github.com/elcritch/merenda.git
cd merenda
atlas install -tuk
nim r examples/controls_showcase.nim
```

The showcase lets you try the controls together in one window. To see another
theme, run it with `NIMKIT_THEME` set (in a POSIX shell):

```sh
NIMKIT_THEME=macos nim r examples/controls_showcase.nim
NIMKIT_THEME=aqua nim r examples/controls_showcase.nim
```

The built-in themes are [embedded CSS stylesheets](src/merenda/nimkit/themes/stylesheets)
with shared widget defaults. Application CSS can extend them, and typed Nim
styling APIs remain available for programmatic overrides.

Use CSS for control colors, fonts, gradients, state styles, edge pinning and
native layout constraints. Style StackView/GridView spacing and alignment and
control-specific metrics through `-nimkit-*` properties. The [CSS preview](examples/css_theme_demo.nim)
lays out its toolbar, sidebar and editor from a stylesheet and reloads it when
you click **Reload CSS**:

```sh
nim r examples/css_theme_demo.nim
```

Read the [CSS theming guide](docs/css-theming.md) for selectors, variables,
supported properties and appearance scope.

You can also [describe native GUIs in lightweight markup](docs/resources.md#gui-markup),
using HTML5 syntax and `data-*` attributes for native widget options:

```html
<nk-main>
  <nk-window id="window" title="Hello" data-frame="100 100 400 240">
    <nk-stack-view id="root" data-axis="vertical" data-padding="24" data-spacing="12">
      <nk-label data-label-style="title">Hello from Merenda</nk-label>
      <nk-text-field id="name" placeholder="Your name"/>
      <button id="save" data-action="saveDocument">Save</button>
    </nk-stack-view>
  </nk-window>
</nk-main>
```

`loadGuiResourceBundle` reads the interface and `instantiateResources` constructs
its native controls. One document can define independent windows. Built-in elements
use `nk-`; application widgets can use names such as `some-app-widget`. Use IDs to
look up controls and connect behavior in Nim.

Try the [GUI resource example](examples/html_ui_demo.nim) with
`nim ic -r examples/html_ui_demo.nim`. It includes compact preferences controls,
Preview and Reset actions, and a separate About window. The Appearance dropdown
switches both windows between the custom stylesheet and the built-in CSS themes.

To use Merenda in your own project, add this dependency to your `.nimble` file
and run `atlas install -tuk` from that project:

```nim
requires "merenda"
```

Build your app with threads enabled and ARC or ORC, for example
`nim r --threads:on --mm:arc main.nim`. The examples in this repository already
have those settings.

FigDraw is compiled into the application. Merenda's experimental
`useNativeDynlib` mode and `build_dynlib` task have been removed; omit
`-d:useNativeDynlib` from existing build commands.

### Running with Dev Control Mode

Compile Merenda apps with `-d:merenda.devControl` for optional local screenshots and input automation.
Setting `MERENDA_DEV_CONTROL=1` then starts and control socket.
`MERENDA_BACKGROUND=1` supports automated runs without activating the app.
See [development control](docs/dev-control.md) for the PID/socket CLI and protocol.

```sh
MERENDA_DEV_CONTROL=1 MERENDA_BACKGROUND=1 ./examples/controls_showcase &
app_pid=$!
./deps/merenda-dev --pid "$app_pid" windows
./deps/merenda-dev --pid "$app_pid" screenshot --window w1 --output /tmp/showcase.png
```

## A few small apps

### Hello, Merenda

A window, a label, and an application loop:

```nim
import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Hello", frame = rect(100, 100, 360, 180))
  root = newView()
  greeting = newTitleLabel("Hello, Merenda!")

root.addSubview(greeting)
greeting.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(window, root)
```

Save this as `examples/greeting.nim` in your checkout and run
`nim r examples/greeting.nim`.

### A button that does something

Here's a counter. A stack view arranges the controls, and the button's action
updates the label.

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

This is [examples/quick_start.nim](examples/quick_start.nim). Run it with:

```sh
nim r examples/quick_start.nim
```

### A Markdown reader in a handful of lines

NimKit's larger controls handle more of the work for you. This app opens a
Markdown file with selectable text, links, code blocks, tables, and images.
The view handles scrolling and layout as you resize the window. Up/Down arrows
scroll the reader, `j`/`k` select headings and paragraphs in reading order, and
Enter expands or collapses the selected block's section.

```nim
import std/os
import merenda/nimkit

let
  path = absolutePath(paramStr(1))
  app = sharedApplication()
  window = newWindow(path.extractFilename(), frame = rect(120, 80, 820, 700))
  root = newView()
  viewer = newMarkdownView(readFile(path), imageBasePath = path.parentDir)

root.addSubview(viewer)
viewer.pinEdges(toGuide = root.contentLayoutGuide(insets(20.0)))

app.runWindow(window, root, viewer)
```

Save it as `examples/reader.nim`, then run
`nim r examples/reader.nim README.md`. It expects a readable file path.
For a version with a built-in sample document, run:

```sh
nim r examples/markdown_viewer_demo.nim README.md
```

That is the kind of efficiency NimKit aims for: you write the app's behavior,
while the controls take care of text selection, focus, drawing, and layout.
For an app with more interaction, try the [to-do list](examples/todo_basic.nim)
or its [table-based version](examples/todo_table.nim), which adds row selection
and drag reordering.

### A table with model–view–presenter

For a small app, MVP doesn't need a class hierarchy. Here, `tasks` holds the
model data in an `ArrayController`, the table and button are the view, and
`markDone` acts as the presenter. Select a row and click **Mark done**: the
presenter updates the model and refreshes the table.

```nim
import merenda/nimkit
import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Tasks", frame = rect(100, 100, 460, 320))
  root = newView()
  table = newTableView(frame = rect(24, 24, 412, 200))
  doneButton = newButton("Mark done", frame = rect(24, 244, 140, 32))
  tasks = newArrayController(columns = [
    modelColumn("task", "Task", "task", 260.0),
    modelColumn("state", "State", "state", 100.0),
  ])

for index, title in ["Write release notes", "Try the demo"]:
  tasks.addItem(modelItem($index, fields = [
    modelField("task", toObj(title)),
    modelField("state", toObj("To do")),
  ]))

table.bindTableView(tasks)
table.selectionMode = tsmSingle

# The presenter turns a user action into a model update.
proc markDone(sender: DynamicAgent) =
  discard sender
  let selected = tasks.selectionController().selectedIdentifier()
  if selected.len > 0:
    tasks.setValue(selected, "state", toObj("Done"))
    table.reloadData()

let doneAction = actionSelector("markTaskDone")
doneButton.target = newActionTarget(doneAction, markDone)
doneButton.action = doneAction

root.addSubview(table)
root.addSubview(doneButton)
app.runWindow(window, root, table)
```

Save this as `examples/tasks_mvp.nim` and run `nim r examples/tasks_mvp.nim`.
The table binding supplies the columns and row values, so you only write the
action specific to your app. For a larger version, see the
[table-based to-do app](examples/todo_table.nim) or the
[model controller examples](examples/modelcontrollers_demo.nim).

### Change a view's behavior with a protocol

Sigils protocols let you attach methods to an individual object, even when its
type comes from a library. Here, an ordinary `View` gets a custom drawing method.
Click **Inspect layout** to replace that method with one that displays the
view's dimensions; click again to restore the preview.

```nim
import merenda/nimkit
import sigils/selectors

protocol PreviewDrawing of ViewDrawingProtocol:
  method draw(view: View, context: DrawContext) =
    context.addRectangle(view.bounds, fill(color(0.18, 0.32, 0.55)))
    context.addText(view.bounds, "Design preview", color(1, 1, 1), taCenter)

protocol LayoutDrawing of ViewDrawingProtocol:
  method draw(view: View, context: DrawContext) =
    context.addRectangle(view.bounds, fill(color(0.12, 0.22, 0.24)))
    let size = view.bounds.size
    context.addText(
      view.bounds, $size.width & " x " & $size.height, color(1, 1, 1), taCenter
    )

let
  app = sharedApplication()
  window = newWindow("Dynamic drawing", frame = rect(100, 100, 420, 260))
  root = newView()
  preview = newView(frame = rect(24, 24, 372, 140))
  button = newButton("Inspect layout", frame = rect(24, 188, 160, 32))
  inspectAction = actionSelector("toggleLayoutDrawing")

preview.withProtocol(PreviewDrawing)
var inspecting = false

proc toggleLayout(sender: DynamicAgent) =
  discard sender
  inspecting = not inspecting
  if inspecting:
    preview.withProtocol(LayoutDrawing)
  else:
    preview.withProtocol(PreviewDrawing)
  preview.needsDisplay = true

button.target = newActionTarget(inspectAction, toggleLayout)
button.action = inspectAction
root.addSubview(preview)
root.addSubview(button)
app.runWindow(window, root)
```

Save this as `examples/protocol_drawing.nim` and run
`nim r examples/protocol_drawing.nim`.

Both implementations are compiled Nim code with typed `View` and `DrawContext`
arguments. NimKit calls the drawing protocol, and Sigils dispatches to the method
currently installed on `preview`. Replacing it leaves other views alone and
keeps this view's identity, layout, and place in the window intact.

This is useful for adding diagnostics, swapping rendering strategies, or
customizing a library object without introducing a subclass for every variation.
The same pattern works for [view controller loading](examples/viewcontroller_demo.nim)
and [table delegates](examples/table_demo.nim).

### Slide between panels

An `animationGroup` turns ordinary property assignments into a coordinated
animation. These two panels slide together over 800 ms with linear motion.
**Next** slides to the details; **Back** reverses the trip.

```nim
import merenda/nimkit
import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Carousel", frame = rect(100, 100, 420, 260))
  root = newView()
  viewport = newView(frame = rect(24, 24, 372, 140))
  first = newGroupBox("Welcome", frame = rect(0, 0, 372, 140))
  second = newGroupBox("Details", frame = rect(372, 0, 372, 140))
  button = newButton("Next", frame = rect(24, 188, 160, 32))
  slideAction = actionSelector("slidePanels")

first.contentView = newLabel("Your first panel.")
second.contentView = newLabel("A little more information.")
viewport.clipsToBounds = true
var showingDetails = false

proc finishSlide(button: Button) {.slot.} =
  button.enabled = true

proc slidePanels(sender: DynamicAgent) =
  discard sender
  if button.enabled:
    button.enabled = false
    showingDetails = not showingDetails
    button.title = if showingDetails: "Back" else: "Next"
    let size = viewport.bounds.size
    let offset =
      if showingDetails:
        -size.width
      else:
        0.0'f32
    let slide = animationGroup(duration = 800.ms, curve = acLinear):
      first.frame = rect(offset, 0, size.width, size.height)
      second.frame = rect(offset + size.width, 0, size.width, size.height)
    slide.connect(finished, button, finishSlide)
    discard app.startAnimation(slide)

button.target = newActionTarget(slideAction, slidePanels)
button.action = slideAction
viewport.addSubview(first)
viewport.addSubview(second)
root.addSubview(viewport)
root.addSubview(button)
app.runWindow(window, root)
```

Run [the carousel example](examples/carousel_demo.nim) with
`nim r examples/carousel_demo.nim`. The viewport clips the panels as they move,
and the animation's `finished` signal enables the button for the next transition.
For more, see [property animations and sequences](examples/animation_demo.nim).

### Blur an overlay's background

A standard `Box` can blur the content behind its rounded bounds through FigDraw.
Its child controls stay sharp, and its fill follows the active theme:

```nim
let overlay = newBox(frame = rect(24, 24, 320, 96))
overlay.addStyleClass(PopoverBoxStyleClass)
overlay.backdropBlurRadius = 20
overlay.backdropTintOpacity = 0.78
overlay.addContentSubview(newTextField("Search"))
root.addSubview(overlay)
```

Set `backdropBlurRadius` to zero to restore the ordinary box fill.
`backdropTintOpacity` controls the themed tint over the blurred content, from
zero to one. This effect is rendered inside the application, independently of
native window backdrop effects.

## Reusable search controls

NimKit apps can reuse the same controls through `SearchBar` or attach a
`TextSearchController` to any host view:

```nim
let preview = newTextView("λcat and dog")
let search = newTextSearchController(
  preview, "document", textViewSearchAdapter(preview)
)
# Attach preview to a window before opening the controls.
discard search.showSearch()
```

Keep the controller alive while its controls are attached, and call `search.close()`
before releasing it if the host remains alive. Custom `TextSearchAdapter` callbacks
provide text snapshots, reveal matches, and clear selections for terminals,
multiple documents, or other data sources. An optional `replace` callback adds
collapsed replacement controls and receives a validated Reni pattern and capture
template. The adapter owns edits, undo, and checking that source content is current.
Hosts can route find shortcuts through `search.handleSearchKey(event)` and call
`search.refreshSearch()` when their source changes.

`SearchBar` is a regular `Box` containing standard text fields and buttons, arranged
with `StackView`. For embedded controls, add `newSearchBar(frame = ...)` to a
container (or use layout constraints) and set `hidden = false`. The host chooses
whether it floats; query, error, and replacement changes do not override an
embedded frame. `TextSearchController` anchors the floating controls with ordinary
layout constraints, allowing their height to follow their content.

## Kosmo

Kosmo is a code editor built with Merenda and Moe's Vim-style editing engine.
It brings together a file browser, split panes, terminal tabs, Markdown previews,
Git diffs, and GitHub issues and PRs. You can use it on its own or explore its
source to see how a larger Merenda app fits together.

### Install and open a project

You don't need Nim to use a prebuilt Kosmo release. Run the installer from a
shell (Git Bash on Windows):

```sh
curl -fsSL https://raw.githubusercontent.com/elcritch/merenda/HEAD/install.sh | bash
```

On macOS, it installs `Kosmo.app` in `~/Applications` and a `kosmo` command in
`~/.local/bin`. On Linux, FreeBSD, and Windows, the command goes in
`~/.local/bin`. Make sure that directory is on your `PATH`.

Open the current folder or a file:

```sh
kosmo .
kosmo README.md
```

These commands reuse a running Kosmo instance.
Use `kosmo --bg ./folder/` to start a new instance detached from your shell.
Start a new instance with `kosmo --new ./folder/`.
`kosmo -v` and `kosmo --version` print the version and exit.
On macOS, you can also open `Kosmo.app` from Finder.

```sh
kosmo --add ../shared-library
kosmo --bg ../shared-library
```

Run `kosmo --help` for command-line options. See the
[keyboard shortcut guide](src/merenda/kosmo/docs/shortcuts.md) for navigation
and Vim bindings, or [release and installer details](docs/releasing-kosmo.md)
for supported builds, custom install locations, and the static Linux build.

### Build from source

Install HarfBuzz and FriBidi development libraries for your platform first
(`brew install harfbuzz fribidi pkg-config` on macOS, or the `libharfbuzz-dev`
and `libfribidi-dev` packages on Debian/Ubuntu).

From your Merenda checkout, install the extra Kosmo dependencies, then build
and launch it:

```sh
atlas install -tuk --features:kosmo
nim c -o:kosmo src/merenda/kosmo/kosmo.nim
./kosmo .
```

On Windows, open a Visual Studio x64 Developer PowerShell and run
`bash .github/scripts/install-msvc-nim.sh` using Git for Windows Bash.
Use the compiler path it prints to build with
`& "<compiler-path>" c --cc:vcc -o:kosmo.exe src/merenda/kosmo/kosmo.nim`,
then run `./kosmo.exe .`.
The script makes a private copy of the official Nim 2.2.10 distribution,
installs checksum-verified atomic and large-string fixes, and builds the corrected
compiler once. Worker threads need the atomic fix; an unpatched MSVC build is
rejected at compile time. The string fix lets ARC/ORC embed the bundled assets.
Keep the Developer shell open when building: the project invokes `cl.exe`
directly so large applications can link using response files.

On macOS, install the current checkout as a complete `Kosmo.app` with its icon,
bundled notices, debug symbols, and local code signature:

```sh
brew install cmake meson ninja
nim install_kosmo
```

This uses Atlas to resolve dependencies, replaces `~/Applications/Kosmo.app`,
and updates the `~/.local/bin/kosmo` link. Restart Kosmo if it was already
running. Set `KOSMO_INSTALL_DIR` or `KOSMO_BIN_DIR` to choose other locations.
This build links HarfBuzz and FriBidi statically with `-d:harfbuzzyStatic`,
so the installed app does not require Homebrew at runtime.

## Explore more

The [examples directory](examples/) has complete apps you can run and change.
These are good places to go once you've tried the basics:

- Layouts: [stacks and constraints](examples/layout_showcase.nim),
  [constraint playground](examples/constraint_playground_demo.nim), and the
  [layout guide](docs/layout.md).
- Tables and trees: [table example](examples/table_demo.nim),
  [filter row](examples/filter_row.nim) (including date range pickers and token fields),
  [outline example](examples/outline_demo.nim), and
  [model controllers](examples/modelcontrollers_demo.nim).
- App workflows: [documents and windows](examples/document_workspace_demo.nim),
  [preferences](examples/preferences_demo.nim), and
  [settings and themes](examples/merenda_settings_demo.nim).
- Text and drawing: [Markdown viewer](examples/markdown_viewer_demo.nim),
  [canvas](examples/canvas_demo.nim), and [terminal](examples/terminal_demo.nim).
- Building UI from resources: [resource guide](docs/resources.md) and
  [example](examples/resource_ui_demo.nim).
- Development checks: [reliability and memory profiling](docs/reliability.md).
- Windows on FreeBSD: [disposable bhyve test VM and GPU passthrough](tools/windows-bhyve/README.md).
- Windows VirtualBox: [setup and FreeBSD GPU test results](tools/windows-virtualbox/README.md).
- Under the hood: [NimKit design](docs/design.md),
  [Kosmo workspace updates](docs/kosmo-workspace.md),
  [FigDraw](https://github.com/elcritch/figdraw/),
  [Siwin](https://github.com/levovix0/siwin), and
  [Sigils](https://github.com/elcritch/sigils).

## Tekton interface builder

Build a resource document with Tekton's widget palette, property inspector, and live
preview. Add layout guides and constraints, pin views to their parent, undo changes,
and save the result for your Merenda app. Use **Interact** to try controls in the preview.

```sh
nim r src/merenda/tekton.nim
# Or open an existing interface:
nim r src/merenda/tekton.nim path/to/interface.cbor
```

See [Tekton's authoring workflow](docs/resources.md#tekton-resource-editor) for supported
resources and how to load the saved interface in your app.
