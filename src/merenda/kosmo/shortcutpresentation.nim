## User-facing labels and settings rows for resolved Kosmo shortcuts.

import std/strutils

import ../nimkit as nimkit
import ./[settings, shortcuts]

func shortcutKeyTitle(stroke: nimkit.KeyStroke): string =
  if stroke.text.len > 0:
    return stroke.text.toUpperAscii()
  if stroke.key >= nimkit.keyA and stroke.key <= nimkit.keyZ:
    return $char(ord('A') + ord(stroke.key) - ord(nimkit.keyA))
  if stroke.key >= nimkit.key1 and stroke.key <= nimkit.key9:
    return $char(ord('1') + ord(stroke.key) - ord(nimkit.key1))
  if stroke.key == nimkit.key0:
    return "0"
  if stroke.key >= nimkit.keyF1 and stroke.key <= nimkit.keyF15:
    return "F" & $(ord(stroke.key) - ord(nimkit.keyF1) + 1)
  case stroke.key
  of nimkit.keyTilde:
    "`"
  of nimkit.keyMinus:
    "-"
  of nimkit.keyEqual:
    "="
  of nimkit.keyLeftBracket:
    "["
  of nimkit.keyRightBracket:
    "]"
  of nimkit.keySpace:
    "Space"
  of nimkit.keyEscape:
    "Esc"
  of nimkit.keyEnter:
    "Enter"
  of nimkit.keyTab:
    "Tab"
  of nimkit.keyBackspace:
    "Backspace"
  of nimkit.keySlash:
    "/"
  of nimkit.keyDot:
    "."
  of nimkit.keyComma:
    ","
  of nimkit.keySemicolon:
    ";"
  of nimkit.keyQuote:
    "'"
  of nimkit.keyBackslash:
    "\\"
  of nimkit.keyPageUp:
    "Page Up"
  of nimkit.keyPageDown:
    "Page Down"
  of nimkit.keyHome:
    "Home"
  of nimkit.keyEnd:
    "End"
  of nimkit.keyInsert:
    "Insert"
  of nimkit.keyDelete:
    "Delete"
  of nimkit.keyArrowLeft:
    "Left"
  of nimkit.keyArrowRight:
    "Right"
  of nimkit.keyArrowUp:
    "Up"
  of nimkit.keyArrowDown:
    "Down"
  of nimkit.keyUnknown:
    if stroke.keyCode == 0:
      "Unknown"
    else:
      $stroke.keyCode
  else:
    let name = $stroke.key
    if name.startsWith("key"):
      name[3 .. ^1]
    else:
      name

func shortcutStrokeTitle(stroke: nimkit.KeyStroke): string =
  var parts: seq[string]
  if nimkit.kmCommand in stroke.modifiers:
    when defined(macosx) or defined(macos):
      parts.add "Cmd"
    else:
      parts.add "Super"
  if nimkit.kmControl in stroke.modifiers:
    parts.add "Ctrl"
  if nimkit.kmOption in stroke.modifiers:
    parts.add "Option"
  if nimkit.kmShift in stroke.modifiers:
    parts.add "Shift"
  parts.add stroke.shortcutKeyTitle()
  parts.join("+")

func shortcutSequenceTitle(sequence: nimkit.KeySequence): string =
  for index, stroke in sequence.strokes:
    if index > 0:
      result.add " "
    result.add stroke.shortcutStrokeTitle()

func kosmoShortcutSettings*(
    bindings: nimkit.KeyBindingTable
): seq[KosmoShortcutSetting] =
  ## Build display rows for Kosmo's currently resolved shortcut bindings.
  for action in kosmoActions():
    var keys: seq[string]
    for binding in bindings.bindings:
      if $binding.selector.name == action.identifier:
        keys.add binding.sequence.shortcutSequenceTitle()
    if action.identifier == KosmoSplitHorizontalAction:
      keys.add "Ctrl+W S / Ctrl+W Ctrl+S"
    elif action.identifier == KosmoSplitVerticalAction:
      keys.add "Ctrl+W V / Ctrl+W Ctrl+V"
    result.add KosmoShortcutSetting(
      action: action.identifier, description: action.description, keys: keys.join(", ")
    )

func focusPanelNumber*(selector: nimkit.CommandSelector): int =
  let name = $selector.name
  if not name.startsWith(KosmoFocusPanelActionPrefix):
    return
  try:
    result = parseInt(name[KosmoFocusPanelActionPrefix.len .. ^1])
  except ValueError:
    discard
  if result notin 1 .. KosmoMaxFocusPanelShortcut:
    result = 0
