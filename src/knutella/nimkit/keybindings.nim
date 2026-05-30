import std/[options, strutils]

import ./selectors
import ./types

type
  ShortcutModifier* = enum
    smShift
    smControl
    smOption
    smCommand
    smShortcut

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

proc initDefaultKeyBindings*(): KeyBindingTable =
  result.bindKey(" ", {}, performClick())
  result.bindKey(keyBackspace, {}, deleteBackward())
  result.bindKey(keyDelete, {}, deleteForward())
  result.bindKey(keyArrowLeft, {}, moveLeft())
  result.bindKey(keyArrowRight, {}, moveRight())
  result.bindKey(keyHome, {}, moveToBeginningOfLine())
  result.bindKey(keyEnd, {}, moveToEndOfLine())
  result.bindKey(keyArrowLeft, {kmShift}, moveLeftAndModifySelection())
  result.bindKey(keyArrowRight, {kmShift}, moveRightAndModifySelection())
  result.bindKey(keyHome, {kmShift}, moveToBeginningOfLineAndModifySelection())
  result.bindKey(keyEnd, {kmShift}, moveToEndOfLineAndModifySelection())
  result.bindShortcut(keyA, {smShortcut}, selectAll())
