import std/strutils

import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Mono Text Demo", frame = rect(160, 140, 760, 520))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Mono Text")
  status = newStatusLabel("Policy: keys forwarded; mouse forwarded")
  controls = newStackView(laHorizontal)
  forwardKeys = newCheckBox("Forward key events")
  captureKeys = newCheckBox("Capture key events")
  forwardMouse = newCheckBox("Forward mouse events")
  editor = newMonoTextEditor(
    """
proc renderVisibleRows(view: MonoTextView) =
  let metrics = view.monoTextMetrics()
  for row in visibleRows(view):
    drawRowRuns(row, metrics)

# This editor is a flat monospace grid.
# Forwarded events are reported here before local editing.
# Captured key events are reported here and then swallowed.
""".strip(),
    frame = rect(0, 0, 980, 920),
  )
  scroll = newScrollView(documentView = editor)
  policyAction = actionSelector("monoTextPolicyChanged")

proc describe(event: MonoTextRawEvent): string =
  let handling = if event.kind in editor.capturedRawEvents: "captured" else: "forwarded"
  let effect =
    if event.kind in {mtreKeyDown, mtreFlagsChanged}:
      if event.kind in editor.capturedRawEvents: "editor blocked" else: "editor edits"
    else:
      "view handles normally"
  "Raw: " & $event.kind & " " & handling & " (" & effect & ") " & event.input & " @ " &
    $event.row & "," & $event.column

proc policySummary(): string =
  let keyMode =
    if captureKeys.state == bsOn:
      "keys captured"
    elif forwardKeys.state == bsOn:
      "keys forwarded"
    else:
      "keys local"
  let mouseMode = if forwardMouse.state == bsOn: "mouse forwarded" else: "mouse local"
  let typingMode =
    if captureKeys.state == bsOn:
      "typing will not change text"
    elif forwardKeys.state == bsOn:
      "typing reports raw events and edits"
    else:
      "typing edits without raw reports"
  "Policy: " & keyMode & "; " & mouseMode & "; " & typingMode

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
  status.text = policySummary()
  let owner = editor.window()
  if owner of Window:
    discard Window(owner).makeFirstResponder(editor)

editor.rawEventHandler = proc(event: MonoTextRawEvent): bool =
  status.text = event.describe()
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
status.text = policySummary()

scroll.hasHorizontalScroller = true
scroll.hasVerticalScroller = true
scroll.frame = rect(0, 0, 704, 360)

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
