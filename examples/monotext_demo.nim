import std/strutils

import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("Nimkit Mono Text Demo", frame = initRect(160, 140, 760, 520))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Mono Text")
  status = newStatusLabel("Raw: None")
  editor = newMonoTextEditor(
    """
proc renderVisibleRows(view: MonoTextView) =
  let metrics = view.monoTextMetrics()
  for row in visibleRows(view):
    drawRowRuns(row, metrics)

# This editor is a flat monospace grid.
# It forwards raw key, mouse, and scroll events before local editing.
""".strip(),
    frame = initRect(0, 0, 980, 920),
  )
  scroll = newScrollView(documentView = editor)

proc describe(event: MonoTextRawEvent): string =
  $event.kind & " " & event.input & " @ " & $event.row & "," & $event.column

editor.rawEventHandler = proc(event: MonoTextRawEvent): bool =
  status.text = "Raw: " & event.describe()
  false

editor.fontSize = 14.0
editor.cursorStyle = mtcVertical

scroll.hasHorizontalScroller = true
scroll.hasVerticalScroller = true
scroll.frame = initRect(0, 0, 704, 360)

layout.spacing = 10.0
layout.alignment = svaFill
layout.addArrangedSubview(title, status, scroll)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 24.0, 28.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

window.setContentView(root)
discard window.makeFirstResponder(editor)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
