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

## Your first app

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

For a button that updates a counter, try
[the quick start example](examples/quick_start.nim):

```sh
nim ic -r examples/quick_start.nim
```

To use Merenda in your own project, add this dependency to your `.nimble` file
and run `atlas install -tuk`:

```nim
requires "https://github.com/elcritch/merenda"
```

Build your app with threads enabled and ARC or ORC, for example
`nim ic -r --threads:on --mm:arc main.nim`. The examples in this repository
already have those settings.

## Make it your own

Choose a built-in theme with `NIMKIT_THEME` (in a POSIX shell):

```sh
NIMKIT_THEME=macos nim ic -r examples/controls_showcase.nim
NIMKIT_THEME=aqua nim ic -r examples/controls_showcase.nim
NIMKIT_THEME=punch nim ic -r examples/controls_showcase.nim
```

Use [CSS](docs/css-theming.md) to customize colors, fonts, spacing, and layout.
The [CSS preview](examples/css_theme_demo.nim) lets you edit a stylesheet and
reload it while the app is running.

You can build interfaces in Nim, describe them in
[lightweight markup](docs/resources.md#gui-markup), or use the
[Tekton interface builder](#tekton-interface-builder).

## Kosmo

Kosmo is a code editor built with Merenda and Moe's Vim-style editing engine.
It brings together a file browser, split panes, terminal tabs, Markdown previews,
Git diffs, and GitHub issues and PRs. Use it on its own or explore its source to
see how a larger Merenda app fits together.

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
