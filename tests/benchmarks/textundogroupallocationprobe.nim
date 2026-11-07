import std/[os, strutils]
import merenda/nimkit/text/textviews_profile_baseline

let
  edits = parseInt(paramStr(1))
  undoEnabled = paramStr(2) == "enabled"
  phase = paramStr(3)
  styled = paramStr(4) == "styled"
  source = repeat("a", 8 * 1024 * 1024)
  view = newTextView(source)
if styled:
  var attributes = view.textStorage().attributesAt(0)
  attributes.fontSize += 1
  view.textStorage().setAttributes(initTextRange(0, source.len div 2), attributes)
view.allowsUndo = undoEnabled
for i in 0 ..< edits:
  view.insertTextValue("x")
if phase == "group":
  view.beginUndoGrouping()
  view.insertTextValue("x")
  view.insertTextValue("y")
  view.endUndoGrouping()
if phase == "undo" or phase == "redo":
  for i in 0 ..< edits:
    doAssert view.undoText()
if phase == "redo":
  for i in 0 ..< edits:
    doAssert view.redoText()
echo "checkpoint edits=", edits, " undo=", undoEnabled, " phase=", phase, " styled=", styled,
  " length=", view.textStorage().len
stdout.flushFile()
discard readLine(stdin)
echo "source still live=", source.len, " document length=", view.textStorage().len
