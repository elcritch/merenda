import merenda/nimkit

import std/unicode

import sigils/core
import sigils/selectors

proc makeIntroStorage(): TextStorage =
  result = newTextStorage(
    "NimKit Text Editor\n\n" &
      "This is a multi-line editor built like Cocoa: a scroll view owns a text view document.\n\n" &
      "It supports selection, undo, pasteboard rich text, wrapping, insets, and attributed runs. Try editing this text, toggling wrapping, and changing the highlighted range."
  )
  result.setAttributes(
    initTextRange(0, 18), defaultTextAttributes(initColor(0.95, 0.42, 0.78, 1.0), 18.0)
  )
  result.setAttributes(
    initTextRange(95, 31), defaultTextAttributes(initColor(0.1, 0.58, 0.95, 1.0), 13.0)
  )
  var emphasis = defaultTextAttributes(initColor(0.95, 0.56, 0.24, 1.0), 13.0)
  emphasis.underline = true
  result.setAttributes(initTextRange(183, 15), emphasis)

let
  app = sharedApplication()
  window = newWindow("NimKit Text Editor Demo", frame = initRect(130, 110, 720, 520))
  root = newView()
  layout = newStackView(laVertical)
  header = newTitleLabel("Text Editor Demo")
  summary = newStatusLabel("")
  editor = newTextEditor(frame = initRect(0, 0, 640, 280))
  controls = newStackView(laHorizontal)
  wrapCheck = newCheckBox("Wrap text")
  richCheck = newCheckBox("Rich text")
  insetChoice = newComboBox(["Compact inset", "Cocoa inset", "Roomy inset"])
  tintButton = newButton("Style Selection")
  resetButton = newButton("Reset Text")
  wrapAction = actionSelector("toggleTextWrap")
  richAction = actionSelector("toggleRichText")
  insetAction = actionSelector("selectTextInset")
  tintAction = actionSelector("styleSelection")
  resetAction = actionSelector("resetTextEditor")
  contextWrapAction = actionSelector("contextToggleTextWrap")

proc updateSummary() =
  let selected = editor.selectedRange()
  summary.text =
    "Characters: " & $editor.stringValue().runeLen & " / Selection: " &
    $selected.location & ":" & $selected.length & " / Wrap: " & $editor.wraps &
    " / Rich text: " & $editor.richText

proc applyInsetChoice() =
  case insetChoice.indexOfSelectedItem()
  of 0:
    editor.textInsets = insets(3.0, 5.0, 3.0, 5.0)
  of 2:
    editor.textInsets = insets(14.0, 18.0, 14.0, 18.0)
  else:
    editor.textInsets = insets(6.0, 7.0, 6.0, 7.0)

proc resetDocument() =
  editor.attributedText = makeIntroStorage()
  editor.selectedRange = initTextRange(0, 0)
  updateSummary()

proc editorChanged(textEditor: TextEditor, sender: DynamicAgent) {.slot.} =
  discard textEditor
  discard sender
  updateSummary()

proc toggleWrap(sender: DynamicAgent) =
  discard sender
  editor.wraps = wrapCheck.state == bsOn
  updateSummary()

proc toggleRichText(sender: DynamicAgent) =
  discard sender
  editor.richText = richCheck.state == bsOn
  updateSummary()

proc selectInset(sender: DynamicAgent) =
  discard sender
  applyInsetChoice()
  updateSummary()

proc styleSelection(sender: DynamicAgent) =
  discard sender
  let selected = editor.selectedRange()
  if selected.length == 0:
    return
  var attributes = defaultTextAttributes(initColor(0.0, 0.85, 0.95, 1.0), 14.0)
  attributes.underline = true
  editor.setAttributes(selected, attributes)
  updateSummary()

proc resetText(sender: DynamicAgent) =
  discard sender
  resetDocument()

proc toggleWrapFromMenu(sender: DynamicAgent) =
  discard sender
  wrapCheck.state = if wrapCheck.state == bsOn: bsOff else: bsOn
  toggleWrap(sender)

let
  contextMenu = newMenu("Text Editor Context")
  contextStyleItem = newMenuItem("Style Selection", tintAction)
  contextWrapItem = newMenuItem("Toggle Wrap", contextWrapAction)
  contextResetItem = newMenuItem("Reset Text", resetAction)

contextStyleItem.target = newActionTarget(tintAction, styleSelection)
contextWrapItem.target = newActionTarget(contextWrapAction, toggleWrapFromMenu)
contextResetItem.target = newActionTarget(resetAction, resetText)
discard contextMenu.addItem(contextStyleItem)
discard contextMenu.addItem(contextWrapItem)
discard contextMenu.addSeparator()
discard contextMenu.addItem(contextResetItem)

layout.spacing = 12.0
layout.alignment = svaFill
layout.edgeInsets = insets(22.0, 24.0)

editor.wraps = true
editor.richText = true
editor.menu = contextMenu
editor.minimumDocumentSize = initSize(640.0, 280.0)
editor.setHuggingPriority(LayoutPriorityLow, laVertical)
editor.setCompressionPriority(LayoutPriorityRequired, laVertical)

wrapCheck.state = bsOn
richCheck.state = bsOn
insetChoice.selectItemAtIndex(1)

controls.spacing = 8.0
controls.alignment = svaCenter
controls.distribution = svdNatural
controls.setHuggingPriority(LayoutPriorityRequired, laVertical)
controls.setCompressionPriority(LayoutPriorityRequired, laVertical)

wrapCheck.target = newActionTarget(wrapAction, toggleWrap)
wrapCheck.action = wrapAction
richCheck.target = newActionTarget(richAction, toggleRichText)
richCheck.action = richAction
insetChoice.target = newActionTarget(insetAction, selectInset)
insetChoice.action = insetAction
tintButton.target = newActionTarget(tintAction, styleSelection)
tintButton.action = tintAction
resetButton.target = newActionTarget(resetAction, resetText)
resetButton.action = resetAction

editor.connect(textDidChange, editor, editorChanged)

controls.addArrangedSubview(wrapCheck, richCheck, insetChoice, tintButton, resetButton)
controls.addFlexibleSpacer()
layout.addArrangedSubview(header, summary, editor, controls)
layout.addFlexibleSpacer()
root.addSubview(layout)
discard layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(0.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

resetDocument()
window.setContentView(root)
discard window.makeFirstResponder(editor)
app.addWindow(window)
window.makeKeyAndOrderFront()
app.run()
