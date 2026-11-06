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

## Try Merenda

You'll need Nim 2.2.10 or newer, a C compiler, Git, and a recent
[Atlas](https://github.com/nim-lang/atlas#installation) (0.16.3 or newer).
On Linux and FreeBSD, you'll also need the system libraries for your windowing
and graphics backend. On Windows, use MinGW-w64 GCC.

Clone the repository and run the controls showcase:

```sh
git clone https://github.com/elcritch/merenda.git
cd merenda
atlas install -tuk
nim ic -r examples/controls_showcase.nim
```

The showcase lets you try the controls together in one window.

To use Merenda in your own project, add this dependency to your `.nimble` file
and run `atlas install -tuk`:

```nim
requires "https://github.com/elcritch/merenda"
```

Build your app with threads enabled and ARC or ORC, for example
`nim ic -r --threads:on --mm:arc main.nim`. The examples in this repository
already have those settings.

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
`nim ic -r examples/greeting.nim`.

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
nim ic -r examples/quick_start.nim
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
`nim ic -r examples/reader.nim README.md`. It expects a readable file path.
For a version with a built-in sample document, run:

```sh
nim ic -r examples/markdown_viewer_demo.nim README.md
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

Save this as `examples/tasks_mvp.nim` and run `nim ic -r examples/tasks_mvp.nim`.
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
`nim ic -r examples/protocol_drawing.nim`.

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
`nim ic -r examples/carousel_demo.nim`. The viewport clips the panels as they move,
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

### Reusable search controls

Add find controls to a text view with `TextSearchController`:

```nim
let preview = newTextView("λcat and dog")
let search = newTextSearchController(
  preview, "document", textViewSearchAdapter(preview)
)
# Attach preview to a window before opening the controls.
discard search.showSearch()
```

Keep the controller alive while its controls are attached, and call `search.close()`
before releasing it if the host remains alive. Route find shortcuts through
`search.handleSearchKey(event)` and call `search.refreshSearch()` when the text
changes. For embedded controls, use a `SearchBar` in your own layout.

## Make it your own

Choose a built-in theme with `NIMKIT_THEME` (in a POSIX shell):

```sh
NIMKIT_THEME=macos nim ic -r examples/controls_showcase.nim
NIMKIT_THEME=aqua nim ic -r examples/controls_showcase.nim
NIMKIT_THEME=punch nim ic -r examples/controls_showcase.nim
```

`macos-adaptive` recolors the macOS Dark chrome from a shared content
palette such as Catppuccin Mocha; in Kosmo it follows the selected editor
theme. Use [CSS](docs/css-theming.md) to customize colors, fonts, spacing,
and layout.
The [CSS preview](examples/css_theme_demo.nim) lets you edit a stylesheet and
reload it while the app is running.

You can also describe interfaces in [lightweight markup](docs/resources.md#gui-markup):

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

Use IDs to look up controls and connect behavior in Nim. Try the
[GUI resource example](examples/html_ui_demo.nim) with
`nim ic -r examples/html_ui_demo.nim`, or build an interface visually with
[Tekton](#tekton-interface-builder).

## Kosmo

Kosmo is a code editor built with Merenda and Moe's Vim-style editing engine.
It brings together a file browser, split panes, terminal tabs, Markdown previews,
Git diffs, and GitHub issues and PRs. Use it on its own or explore its source to
see how a larger Merenda app fits together.

Kitty-style `F6` hints pick text that is visible on screen — press `F6` to
label every link, `Shift-F6` for file locations, or `Alt-F6` for words, then
type a marker to open or copy the snippet.

You don't need Nim to use a prebuilt Kosmo release. Run the installer from a
shell (Git Bash on Windows):

```sh
curl -fsSL https://raw.githubusercontent.com/elcritch/merenda/HEAD/install.sh | bash
```

The installer adds a `kosmo` command in `~/.local/bin`; make sure that directory
is on your `PATH`. On macOS, it also installs `Kosmo.app` in `~/Applications`.

Open a project or a file:

```sh
kosmo .
kosmo README.md
```

To build and run Kosmo from your Merenda checkout:

```sh
atlas install -tuk --features:kosmo
nim ic -o:kosmo src/merenda/kosmo/kosmo.nim
./kosmo .
```

See the [keyboard shortcut guide](src/merenda/kosmo/docs/shortcuts.md),
run `kosmo --help` for command-line options, or read the
[installation and release details](docs/releasing-kosmo.md).

## Tekton interface builder

Build an interface with Tekton's widget palette, property inspector, and live
preview, then save it for your Merenda app.

```sh
nim ic -r src/merenda/tekton.nim
```

See [Tekton's authoring guide](docs/resources.md#tekton-resource-editor) to get started.

## Explore more

The [examples directory](examples/) has complete apps you can run and change:

- Build a small app: [to-do list](examples/todo_basic.nim) or
  [table-based to-do list](examples/todo_table.nim).
- Arrange controls: [layout showcase](examples/layout_showcase.nim) and
  [layout guide](docs/layout.md).
- Work with text: [Markdown reader](examples/markdown_viewer_demo.nim),
  [text editor](examples/texteditor_demo.nim), and [terminal](examples/terminal_demo.nim).
- Add motion and drawing: [animations](examples/animation_demo.nim) and
  [canvas](examples/canvas_demo.nim).
- Build larger apps: [documents and windows](examples/document_workspace_demo.nim),
  [preferences](examples/preferences_demo.nim), and
  [model controllers](examples/modelcontrollers_demo.nim).
