import std/[options, strutils]

import ./selectors
import ./events

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

  KeyBinding* = object
    stroke*: KeyStroke
    selector*: CommandSelector

  KeyBindingTable* = object
    bindings*: seq[KeyBinding]

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

proc initKeyBinding*(stroke: KeyStroke, selector: CommandSelector): KeyBinding =
  KeyBinding(stroke: stroke, selector: selector)

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

proc add*(table: var KeyBindingTable, stroke: KeyStroke, selector: CommandSelector) =
  for binding in table.bindings.mitems:
    if binding.stroke == stroke:
      binding.selector = selector
      return
  table.bindings.add initKeyBinding(stroke, selector)

proc remove*(table: var KeyBindingTable, stroke: KeyStroke): bool {.discardable.} =
  for idx, binding in table.bindings:
    if binding.stroke == stroke:
      table.bindings.delete(idx)
      return true

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

proc commandFor*(table: KeyBindingTable, event: KeyEvent): Option[CommandSelector] =
  for binding in table.bindings:
    if binding.stroke.matches(event):
      return some(binding.selector)
  none(CommandSelector)

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
  table.bindKey(keyHome, {}, moveToBeginningOfLine())
  table.bindKey(keyEnd, {}, moveToEndOfLine())
  table.bindKey(keyArrowLeft, {kmShift}, moveLeftAndModifySelection())
  table.bindKey(keyArrowRight, {kmShift}, moveRightAndModifySelection())
  table.bindKey(keyHome, {kmShift}, moveToBeginningOfLineAndModifySelection())
  table.bindKey(keyEnd, {kmShift}, moveToEndOfLineAndModifySelection())
  table.bindKey(keyTab, {}, insertTab())
  table.bindKey(keyTab, {kmShift}, insertBacktab())

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

proc bindMacOSEditing(table: var KeyBindingTable) =
  table.bindKey(keyA, {kmControl}, moveToBeginningOfLine())
  table.bindKey(keyE, {kmControl}, moveToEndOfLine())
  table.bindKey(keyB, {kmControl}, moveLeft())
  table.bindKey(keyF, {kmControl}, moveRight())
  table.bindKey(keyH, {kmControl}, deleteBackward())
  table.bindKey(keyD, {kmControl}, deleteForward())
  table.bindWordEditing({kmOption})
  table.bindLineEditing({kmCommand})
  table.bindKey(keyBackspace, {kmOption}, deleteWordBackward())
  table.bindKey(keyDelete, {kmOption}, deleteWordForward())
  table.bindKey(keyA, {kmCommand}, selectAll())
  table.bindKey(keyC, {kmCommand}, copy())
  table.bindKey(keyX, {kmCommand}, cut())
  table.bindKey(keyV, {kmCommand}, paste())
  table.bindKey(keyZ, {kmCommand}, undo())
  table.bindKey(keyZ, {kmCommand, kmShift}, redo())

proc bindWindowsEditing(table: var KeyBindingTable) =
  table.bindWordEditing({kmControl})
  table.bindKey(keyHome, {kmControl}, moveToBeginningOfLine())
  table.bindKey(keyEnd, {kmControl}, moveToEndOfLine())
  table.bindKey(
    keyHome, {kmShift, kmControl}, moveToBeginningOfLineAndModifySelection()
  )
  table.bindKey(keyEnd, {kmShift, kmControl}, moveToEndOfLineAndModifySelection())
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
