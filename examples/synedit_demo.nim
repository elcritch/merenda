import std/strutils

import merenda/nimkit
import merenda/nimkit/text/syneditviews

import sigils/selectors

const SampleCode = """
import std/[strutils, tables]

type
  TodoPriority = enum
    low, normal, high

  TodoItem = object
    title: string
    done: bool
    priority: TodoPriority

proc describe(item: TodoItem): string =
  let marker = if item.done: "[x]" else: "[ ]"
  marker & " " & item.title & " (" & $item.priority & ")"

proc main() =
  var items = @[
    TodoItem(title: "Port uirelays SynEdit", priority: high),
    TodoItem(title: "Keep Merenda text input", priority: normal),
    TodoItem(title: "Add a demo", done: true, priority: low),
  ]

  for item in items.mitems:
    if "SynEdit" in item.title:
      item.done = true
    echo item.describe()

when isMainModule:
  main()
""".strip()

let
  app = sharedApplication()
  window = newWindow("SynEdit Demo", frame = rect(180, 120, 900, 640))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("SynEdit")
  controls = newStackView(laHorizontal)
  toggleNumbers = newCheckBox("Line numbers")
  nimButton = newButton("Nim")
  markdownButton = newButton("Markdown")
  editor = newSynEditView(SampleCode, language = langNim)
  status = newStatusLabel("Nim source editor with uirelays-style tokens")
  action = actionSelector("synEditDemoChanged")

const MarkdownSample = """
# SynEdit Markdown

This is the same widget with the Markdown token mode enabled.

```nim
echo "fenced Nim text"
```

- line-number gutter
- syntax token spans
- Merenda text editing
""".strip()

proc refreshStatus() =
  status.text =
    (if editor.language == langNim: "Nim" else: "Markdown") & "  " & $editor.lineCount &
    " lines"

proc applyDemoChange(sender: DynamicAgent) =
  if sender == DynamicAgent(toggleNumbers):
    editor.showLineNumbers = toggleNumbers.state == bsOn
  elif sender == DynamicAgent(nimButton):
    editor.language = langNim
    editor.text = SampleCode
  elif sender == DynamicAgent(markdownButton):
    editor.language = langMarkdown
    editor.text = MarkdownSample
  refreshStatus()

editor.fontSize = 14.0
editor.setHuggingPriority(LayoutPriorityLow, laVertical)
editor.setCompressionPriority(LayoutPriorityLow, laVertical)
toggleNumbers.state = bsOn

let target = newActionTarget(action, applyDemoChange)
for control in [Control(toggleNumbers), Control(nimButton), Control(markdownButton)]:
  control.target = target
  control.action = action

controls.spacing = 8.0
controls.alignment = svaLeading
controls.setHuggingPriority(LayoutPriorityRequired, laVertical)
controls.setCompressionPriority(LayoutPriorityRequired, laVertical)
controls.addArrangedSubview(toggleNumbers, nimButton, markdownButton)

layout.spacing = 10.0
layout.alignment = svaFill
layout.addArrangedSubview(title, controls, editor, status)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 24.0, 28.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

refreshStatus()
window.setContentView(root)
discard window.makeFirstResponder(editor.textEditor)
app.addWindow(window)
window.makeKeyAndOrderFront()
app.run()
