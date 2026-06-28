import std/strutils

import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Mono Text Demo", frame = initRect(160, 140, 760, 520))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Mono Text")
  status = newStatusLabel("Raw: None")
  controls = newStackView(laHorizontal)
  forwardKeys = newCheckBox("Forward keys")
  captureKeys = newCheckBox("Capture keys")
  forwardMouse = newCheckBox("Forward mouse")
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
  policyAction = actionSelector("monoTextPolicyChanged")

proc describe(event: MonoTextRawEvent): string =
  let handling =
    if event.kind in editor.capturedRawEvents: " captured" else: " pass-through"
  $event.kind & handling & " " & event.input & " @ " & $event.row & "," & $event.column

proc applyPolicy() =
  var
    forwarded: MonoTextRawEventKinds = {}
    captured: MonoTextRawEventKinds = {}
  if forwardKeys.state == bsOn:
    forwarded = forwarded + {mtreKeyDown, mtreFlagsChanged}
  if captureKeys.state == bsOn:
    captured = captured + {mtreKeyDown, mtreFlagsChanged}
  if forwardMouse.state == bsOn:
    forwarded =
      forwarded + {mtreMouseDown, mtreMouseDragged, mtreMouseUp, mtreScrollWheel}
  editor.rawEventPolicy =
    initMonoTextRawEventPolicy(forwardedEvents = forwarded, capturedEvents = captured)

proc changePolicy(sender: DynamicAgent) =
  discard sender
  applyPolicy()
  status.text = "Raw: policy updated"

editor.rawEventHandler = proc(event: MonoTextRawEvent): bool =
  status.text = "Raw: " & event.describe()
  false

editor.fontSize = 14.0
editor.cursorStyle = mtcVertical
forwardKeys.state = bsOn
forwardMouse.state = bsOn
let policyTarget = newActionTarget(policyAction, changePolicy)
for checkbox in [forwardKeys, captureKeys, forwardMouse]:
  checkbox.target = policyTarget
  checkbox.action = policyAction
applyPolicy()

scroll.hasHorizontalScroller = true
scroll.hasVerticalScroller = true
scroll.frame = initRect(0, 0, 704, 360)

layout.spacing = 10.0
layout.alignment = svaFill
controls.spacing = 12.0
controls.alignment = svaLeading
controls.addArrangedSubview(forwardKeys, captureKeys, forwardMouse)
layout.addArrangedSubview(title, status, controls, scroll)

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
