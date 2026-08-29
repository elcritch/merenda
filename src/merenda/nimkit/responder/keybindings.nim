import std/[options, strutils]

import ../foundation/selectors
import ../foundation/events

type
  ShortcutModifier* = enum
    smShift
    smControl
    smOption
    smCommand
    smShortcut

  KeyBindingProfile* = enum
    kbpMacOS
    kbpWindows
    kbpLinuxBsd

  KeyStroke* = object
    text*: string
    key*: Key
    keyCode*: int
    modifiers*: set[KeyModifier]

  KeySequence* = object
    strokes*: seq[KeyStroke]

  KeyBinding* = object
    sequence*: KeySequence
    selector*: CommandSelector

  KeyBindingTable* = object
    bindings*: seq[KeyBinding]

  KeyBindingMatchKind* = enum
    kbmNone
    kbmPrefix
    kbmCommand

  KeyBindingMatch* = object
    kind*: KeyBindingMatchKind
    selector*: CommandSelector

proc normalizedKeyText(text: string): string =
  text.toLowerAscii()

proc keyForCode*(keyCode: int): Key =
  if keyCode < ord(low(Key)) or keyCode > ord(high(Key)):
    return keyUnknown
  Key(keyCode)

proc keyForText*(text: string): Key =
  let normalized = text.normalizedKeyText()
  if normalized.len != 1:
    return keyUnknown

  case normalized[0]
  of 'a' .. 'z':
    Key(ord(keyA) + ord(normalized[0]) - ord('a'))
  of '1' .. '9':
    Key(ord(key1) + ord(normalized[0]) - ord('1'))
  of '0':
    key0
  of '`', '~':
    keyTilde
  of '-':
    keyMinus
  of '=':
    keyEqual
  of '[':
    keyLeftBracket
  of ']':
    keyRightBracket
  of ' ':
    keySpace
  of '\n', '\r':
    keyEnter
  of '\t':
    keyTab
  of '/':
    keySlash
  of '.':
    keyDot
  of ',':
    keyComma
  of ';':
    keySemicolon
  of '\'':
    keyQuote
  of '\\':
    keyBackslash
  else:
    keyUnknown

proc keyCodeForText*(text: string): int =
  let key = text.keyForText()
  if key == keyUnknown:
    return 0
  ord(key)

proc shortcutModifiers*(): set[KeyModifier] =
  when defined(macosx) or defined(macos):
    {kmCommand}
  else:
    {kmControl}

proc toKeyModifiers*(modifiers: set[ShortcutModifier]): set[KeyModifier] =
  for modifier in modifiers:
    case modifier
    of smShift:
      result.incl kmShift
    of smControl:
      result.incl kmControl
    of smOption:
      result.incl kmOption
    of smCommand:
      result.incl kmCommand
    of smShortcut:
      result = result + shortcutModifiers()

proc initKeyStroke*(
    text: string, modifiers: set[KeyModifier] = {}, keyCode = 0
): KeyStroke =
  let key = text.keyForText()
  let resolvedCode =
    if keyCode == 0:
      ord(key)
    else:
      keyCode
  KeyStroke(
    text: text.normalizedKeyText, key: key, keyCode: resolvedCode, modifiers: modifiers
  )

proc initKeyStroke*(key: Key, modifiers: set[KeyModifier] = {}): KeyStroke =
  KeyStroke(key: key, keyCode: ord(key), modifiers: modifiers)

proc initKeyStroke*(keyCode: int, modifiers: set[KeyModifier] = {}): KeyStroke =
  KeyStroke(key: keyCode.keyForCode(), keyCode: keyCode, modifiers: modifiers)

proc initShortcutStroke*(
    text: string, modifiers: set[ShortcutModifier] = {}
): KeyStroke =
  initKeyStroke(text, modifiers.toKeyModifiers)

proc initShortcutStroke*(key: Key, modifiers: set[ShortcutModifier] = {}): KeyStroke =
  initKeyStroke(key, modifiers.toKeyModifiers)

proc initKeySequence*(strokes: openArray[KeyStroke]): KeySequence =
  if strokes.len == 0:
    raise newException(ValueError, "Key sequence cannot be empty")
  KeySequence(strokes: @strokes)

proc initKeyBinding*(sequence: KeySequence, selector: CommandSelector): KeyBinding =
  if sequence.strokes.len == 0:
    raise newException(ValueError, "Key sequence cannot be empty")
  KeyBinding(sequence: sequence, selector: selector)

proc initKeyBinding*(stroke: KeyStroke, selector: CommandSelector): KeyBinding =
  initKeyBinding(initKeySequence([stroke]), selector)

proc matches*(stroke: KeyStroke, event: KeyEvent): bool =
  if stroke.modifiers != event.modifiers:
    return false
  if stroke.text.len > 0 and event.text.len > 0:
    return stroke.text == event.text.normalizedKeyText
  if stroke.key != keyUnknown and event.key != keyUnknown:
    return stroke.key == event.key
  if stroke.keyCode != 0:
    return stroke.keyCode == event.keyCode
  false

proc equivalent(first, second: KeyStroke): bool =
  if first.modifiers != second.modifiers:
    return false
  if first.key != keyUnknown and second.key != keyUnknown:
    return first.key == second.key
  if first.keyCode != 0 and second.keyCode != 0:
    return first.keyCode == second.keyCode
  first.text.len > 0 and second.text.len > 0 and
    first.text.normalizedKeyText == second.text.normalizedKeyText

proc isPrefix(first, second: KeySequence): bool =
  if first.strokes.len > second.strokes.len:
    return false
  for index, stroke in first.strokes:
    if not stroke.equivalent(second.strokes[index]):
      return false
  true

proc add*(
    table: var KeyBindingTable, sequence: KeySequence, selector: CommandSelector
) =
  if sequence.strokes.len == 0:
    raise newException(ValueError, "Key sequence cannot be empty")
  for binding in table.bindings.mitems:
    if sequence.strokes.len == binding.sequence.strokes.len and
        sequence.isPrefix(binding.sequence):
      binding.selector = selector
      return
    if sequence.isPrefix(binding.sequence) or binding.sequence.isPrefix(sequence):
      raise newException(
        ValueError, "Key sequence cannot also be the prefix of another binding"
      )
  table.bindings.add initKeyBinding(sequence, selector)

proc add*(table: var KeyBindingTable, stroke: KeyStroke, selector: CommandSelector) =
  table.add(initKeySequence([stroke]), selector)

proc remove*(table: var KeyBindingTable, sequence: KeySequence): bool {.discardable.} =
  for index, binding in table.bindings:
    if sequence.strokes.len == binding.sequence.strokes.len and
        sequence.isPrefix(binding.sequence):
      table.bindings.delete(index)
      return true

proc remove*(table: var KeyBindingTable, stroke: KeyStroke): bool {.discardable.} =
  table.remove(initKeySequence([stroke]))

proc remove*(
    table: var KeyBindingTable, selector: CommandSelector
): int {.discardable.} =
  ## Remove every stroke that invokes `selector` and return the number removed.
  var writeIndex = 0
  for binding in table.bindings:
    if binding.selector == selector:
      inc result
    else:
      table.bindings[writeIndex] = binding
      inc writeIndex
  table.bindings.setLen(writeIndex)

proc clear*(table: var KeyBindingTable) =
  table.bindings.setLen(0)

proc bindKey*(
    table: var KeyBindingTable,
    text: string,
    modifiers: set[KeyModifier],
    selector: CommandSelector,
) =
  table.add(initKeyStroke(text, modifiers), selector)

proc bindKey*(
    table: var KeyBindingTable,
    key: Key,
    modifiers: set[KeyModifier],
    selector: CommandSelector,
) =
  table.add(initKeyStroke(key, modifiers), selector)

proc bindKey*(
    table: var KeyBindingTable,
    keyCode: int,
    modifiers: set[KeyModifier],
    selector: CommandSelector,
) =
  table.add(initKeyStroke(keyCode, modifiers), selector)

proc bindSequence*(
    table: var KeyBindingTable, strokes: openArray[KeyStroke], selector: CommandSelector
) =
  table.add(initKeySequence(strokes), selector)

proc bindShortcut*(
    table: var KeyBindingTable,
    text: string,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  table.bindKey(text, modifiers.toKeyModifiers, selector)

proc bindShortcut*(
    table: var KeyBindingTable,
    key: Key,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  table.bindKey(key, modifiers.toKeyModifiers, selector)

proc bindShortcuts*(
    table: var KeyBindingTable,
    text: string,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  table.bindShortcut(text, modifiers, selector)

proc bindShortcuts*(
    table: var KeyBindingTable,
    key: Key,
    modifiers: set[ShortcutModifier],
    selector: CommandSelector,
) =
  table.bindShortcut(key, modifiers, selector)

proc match*(table: KeyBindingTable, events: openArray[KeyEvent]): KeyBindingMatch =
  if events.len == 0:
    return
  for binding in table.bindings:
    if events.len <= binding.sequence.strokes.len:
      var matches = true
      for index, event in events:
        if not binding.sequence.strokes[index].matches(event):
          matches = false
          break
      if matches:
        if events.len == binding.sequence.strokes.len:
          return KeyBindingMatch(kind: kbmCommand, selector: binding.selector)
        result.kind = kbmPrefix

proc commandFor*(table: KeyBindingTable, event: KeyEvent): Option[CommandSelector] =
  let bindingMatch = table.match([event])
  if bindingMatch.kind == kbmCommand:
    return some(bindingMatch.selector)
  none(CommandSelector)

proc shortcutKey(name: string, modifiers: var set[KeyModifier]): Key =
  case name
  of "{":
    modifiers.incl kmShift
    keyLeftBracket
  of "}":
    modifiers.incl kmShift
    keyRightBracket
  of "space":
    keySpace
  of "enter", "return":
    keyEnter
  of "tab":
    keyTab
  of "escape", "esc":
    keyEscape
  of "backspace":
    keyBackspace
  of "delete":
    keyDelete
  of "left":
    keyArrowLeft
  of "right":
    keyArrowRight
  of "up":
    keyArrowUp
  of "down":
    keyArrowDown
  of "pageup":
    keyPageUp
  of "pagedown":
    keyPageDown
  of "home":
    keyHome
  of "end":
    keyEnd
  of "minus":
    keyMinus
  of "equal":
    keyEqual
  else:
    name.keyForText()

proc parseKeyStroke*(description: string): KeyStroke =
  ## Parse a shortcut such as `cmd-s`, `cmd-shift-p`, or `cmd-{`.
  ##
  ## Modifier names are `cmd`, `ctrl`, `option`/`alt`, and `shift`. Braces
  ## imply the Shift modifier for their corresponding bracket key.
  let normalized = description.strip().toLowerAscii()
  if normalized.len == 0:
    raise newException(ValueError, "Shortcut cannot be empty")
  let parts = normalized.split('-')
  if parts.len == 0 or parts[^1].len == 0:
    raise newException(ValueError, "Shortcut must end with a key: " & description)

  var modifiers: set[KeyModifier]
  for index in 0 ..< parts.high:
    case parts[index]
    of "cmd", "command":
      modifiers.incl kmCommand
    of "ctrl", "control":
      modifiers.incl kmControl
    of "option", "alt":
      modifiers.incl kmOption
    of "shift":
      modifiers.incl kmShift
    else:
      raise newException(ValueError, "Unknown shortcut modifier '" & parts[index] & "'")

  let key = shortcutKey(parts[^1], modifiers)
  if key == keyUnknown:
    raise newException(ValueError, "Unknown shortcut key '" & parts[^1] & "'")
  initKeyStroke(key, modifiers)

proc parseKeySequence*(description: string): KeySequence =
  ## Parse a key sequence such as `ctrl-w ctrl-s`.
  let descriptions = description.splitWhitespace()
  if descriptions.len == 0:
    raise newException(ValueError, "Key sequence cannot be empty")
  var strokes = newSeqOfCap[KeyStroke](descriptions.len)
  for strokeDescription in descriptions:
    strokes.add parseKeyStroke(strokeDescription)
  initKeySequence(strokes)

proc bindSequence*(
    table: var KeyBindingTable, description: string, selector: CommandSelector
) =
  table.add(parseKeySequence(description), selector)

proc defaultKeyBindingProfile*(): KeyBindingProfile =
  when defined(macosx) or defined(macos):
    kbpMacOS
  elif defined(windows):
    kbpWindows
  else:
    kbpLinuxBsd

proc bindCoreEditing(table: var KeyBindingTable) =
  table.bindKey(" ", {}, performClick())
  table.bindKey("\n", {}, insertNewline())
  table.bindKey(keyBackspace, {}, deleteBackward())
  table.bindKey(keyDelete, {}, deleteForward())
  table.bindKey(keyArrowLeft, {}, moveLeft())
  table.bindKey(keyArrowRight, {}, moveRight())
  table.bindKey(keyArrowUp, {}, moveUp())
  table.bindKey(keyArrowDown, {}, moveDown())
  table.bindKey(keyHome, {}, moveToBeginningOfLine())
  table.bindKey(keyEnd, {}, moveToEndOfLine())
  table.bindKey(keyArrowLeft, {kmShift}, moveLeftAndModifySelection())
  table.bindKey(keyArrowRight, {kmShift}, moveRightAndModifySelection())
  table.bindKey(keyArrowUp, {kmShift}, moveUpAndModifySelection())
  table.bindKey(keyArrowDown, {kmShift}, moveDownAndModifySelection())
  table.bindKey(keyHome, {kmShift}, moveToBeginningOfLineAndModifySelection())
  table.bindKey(keyEnd, {kmShift}, moveToEndOfLineAndModifySelection())
  table.bindKey(keyTab, {}, insertTab())
  table.bindKey(keyTab, {kmShift}, insertBacktab())
  table.bindKey(keyEscape, {}, cancelOperation())

proc bindWordEditing(table: var KeyBindingTable, modifiers: set[KeyModifier]) =
  table.bindKey(keyArrowLeft, modifiers, moveWordLeft())
  table.bindKey(keyArrowRight, modifiers, moveWordRight())
  table.bindKey(keyArrowLeft, modifiers + {kmShift}, moveWordLeftAndModifySelection())
  table.bindKey(keyArrowRight, modifiers + {kmShift}, moveWordRightAndModifySelection())

proc bindLineEditing(table: var KeyBindingTable, modifiers: set[KeyModifier]) =
  table.bindKey(keyArrowLeft, modifiers, moveToBeginningOfLine())
  table.bindKey(keyArrowRight, modifiers, moveToEndOfLine())
  table.bindKey(
    keyArrowLeft, modifiers + {kmShift}, moveToBeginningOfLineAndModifySelection()
  )
  table.bindKey(
    keyArrowRight, modifiers + {kmShift}, moveToEndOfLineAndModifySelection()
  )

proc bindDocumentEditing(table: var KeyBindingTable, modifiers: set[KeyModifier]) =
  table.bindKey(keyHome, modifiers, moveToBeginningOfDocument())
  table.bindKey(keyEnd, modifiers, moveToEndOfDocument())
  table.bindKey(
    keyHome, modifiers + {kmShift}, moveToBeginningOfDocumentAndModifySelection()
  )
  table.bindKey(keyEnd, modifiers + {kmShift}, moveToEndOfDocumentAndModifySelection())

proc bindMacOSEditing(table: var KeyBindingTable) =
  table.bindKey(keyA, {kmControl}, moveToBeginningOfLine())
  table.bindKey(keyE, {kmControl}, moveToEndOfLine())
  table.bindKey(keyB, {kmControl}, moveLeft())
  table.bindKey(keyF, {kmControl}, moveRight())
  table.bindKey(keyP, {kmControl}, moveUp())
  table.bindKey(keyN, {kmControl}, moveDown())
  table.bindKey(keyH, {kmControl}, deleteBackward())
  table.bindKey(keyD, {kmControl}, deleteForward())
  table.bindKey(keyK, {kmControl}, deleteToEndOfLine())
  table.bindWordEditing({kmOption})
  table.bindLineEditing({kmCommand})
  table.bindKey(keyArrowUp, {kmCommand}, moveToBeginningOfDocument())
  table.bindKey(keyArrowDown, {kmCommand}, moveToEndOfDocument())
  table.bindKey(
    keyArrowUp, {kmCommand, kmShift}, moveToBeginningOfDocumentAndModifySelection()
  )
  table.bindKey(
    keyArrowDown, {kmCommand, kmShift}, moveToEndOfDocumentAndModifySelection()
  )
  table.bindKey(keyBackspace, {kmOption}, deleteWordBackward())
  table.bindKey(keyDelete, {kmOption}, deleteWordForward())
  table.bindKey(keyBackspace, {kmCommand}, deleteToBeginningOfLine())
  table.bindKey(keyA, {kmCommand}, selectAll())
  table.bindKey(keyC, {kmCommand}, copy())
  table.bindKey(keyX, {kmCommand}, cut())
  table.bindKey(keyV, {kmCommand}, paste())
  table.bindKey(keyZ, {kmCommand}, undo())
  table.bindKey(keyZ, {kmCommand, kmShift}, redo())

proc bindWindowsEditing(table: var KeyBindingTable) =
  table.bindWordEditing({kmControl})
  table.bindDocumentEditing({kmControl})
  table.bindKey(keyBackspace, {kmControl}, deleteWordBackward())
  table.bindKey(keyDelete, {kmControl}, deleteWordForward())
  table.bindKey(keyA, {kmControl}, selectAll())
  table.bindKey(keyC, {kmControl}, copy())
  table.bindKey(keyX, {kmControl}, cut())
  table.bindKey(keyV, {kmControl}, paste())
  table.bindKey(keyZ, {kmControl}, undo())
  table.bindKey(keyY, {kmControl}, redo())

proc bindLinuxBsdEditing(table: var KeyBindingTable) =
  table.bindWordEditing({kmControl})
  table.bindWordEditing({kmOption})
  table.bindDocumentEditing({kmControl})
  table.bindKey(keyE, {kmControl}, moveToEndOfLine())
  table.bindKey(keyBackspace, {kmControl}, deleteWordBackward())
  table.bindKey(keyDelete, {kmControl}, deleteWordForward())
  table.bindKey(keyA, {kmControl}, selectAll())
  table.bindKey(keyC, {kmControl}, copy())
  table.bindKey(keyX, {kmControl}, cut())
  table.bindKey(keyV, {kmControl}, paste())
  table.bindKey(keyZ, {kmControl}, undo())
  table.bindKey(keyY, {kmControl}, redo())

proc initMacOSKeyBindings*(): KeyBindingTable =
  result.bindCoreEditing()
  result.bindMacOSEditing()

proc initWindowsKeyBindings*(): KeyBindingTable =
  result.bindCoreEditing()
  result.bindWindowsEditing()

proc initLinuxBsdKeyBindings*(): KeyBindingTable =
  result.bindCoreEditing()
  result.bindLinuxBsdEditing()

proc initDefaultKeyBindings*(profile: KeyBindingProfile): KeyBindingTable =
  case profile
  of kbpMacOS:
    initMacOSKeyBindings()
  of kbpWindows:
    initWindowsKeyBindings()
  of kbpLinuxBsd:
    initLinuxBsdKeyBindings()

proc initDefaultKeyBindings*(): KeyBindingTable =
  initDefaultKeyBindings(defaultKeyBindingProfile())
