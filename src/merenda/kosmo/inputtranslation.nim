## Translation between NimKit input/rendering values and Moe's backend types.

import std/strutils

import moepkg/celina_backend as celina

import ../nimkit as nimkit
import ./moe

func toMoeModifiers*(modifiers: set[nimkit.KeyModifier]): set[moe.KeyModifier] =
  if nimkit.kmControl in modifiers:
    result.incl moe.kmControl
  if nimkit.kmOption in modifiers:
    result.incl moe.kmAlt
  if nimkit.kmShift in modifiers:
    result.incl moe.kmShift
  if nimkit.kmCommand in modifiers:
    result.incl moe.kmMeta

func toPointerButton*(button: nimkit.MouseButton): PointerButton =
  case button
  of nimkit.mbPrimary: pbPrimary
  of nimkit.mbSecondary: pbSecondary
  of nimkit.mbOther: pbOther

func keyName(event: nimkit.KeyEvent): string =
  if event.key >= nimkit.keyA and event.key <= nimkit.keyZ:
    return $char(ord('a') + ord(event.key) - ord(nimkit.keyA))
  if event.key >= nimkit.key0 and event.key <= nimkit.key9:
    return $char(ord('0') + ord(event.key) - ord(nimkit.key0))
  case event.key
  of nimkit.keySpace: "Space"
  of nimkit.keyEscape: "Esc"
  of nimkit.keyEnter: "Enter"
  of nimkit.keyTab: "Tab"
  of nimkit.keyBackspace: "Backspace"
  of nimkit.keyDelete: "Delete"
  of nimkit.keyArrowUp: "Up"
  of nimkit.keyArrowDown: "Down"
  of nimkit.keyArrowLeft: "Left"
  of nimkit.keyArrowRight: "Right"
  of nimkit.keyPageUp: "PageUp"
  of nimkit.keyPageDown: "PageDown"
  of nimkit.keyHome: "Home"
  of nimkit.keyEnd: "End"
  of nimkit.keyMinus: "-"
  of nimkit.keyEqual: "="
  of nimkit.keySlash: "/"
  of nimkit.keyDot: "."
  of nimkit.keyComma: ","
  of nimkit.keySemicolon: ";"
  of nimkit.keyQuote: "'"
  of nimkit.keyBackslash: "\\"
  else: event.text

func keyNotation*(event: nimkit.KeyEvent): string =
  let key = event.keyName()
  if key.len == 0:
    return
  var parts: seq[string]
  if nimkit.kmControl in event.modifiers:
    parts.add "C"
  if nimkit.kmOption in event.modifiers or nimkit.kmCommand in event.modifiers:
    parts.add "M"
  if nimkit.kmShift in event.modifiers:
    parts.add "S"
  parts.add key
  parts.join("-")

func awaitsCommittedText*(event: nimkit.KeyEvent): bool =
  if event.modifiers - {nimkit.kmShift} != {}:
    return false
  case event.key
  of nimkit.keyA .. nimkit.keyZ,
      nimkit.keyTilde,
      nimkit.key1 .. nimkit.key0,
      nimkit.keyMinus,
      nimkit.keyEqual,
      nimkit.keyLeftBracket,
      nimkit.keyRightBracket,
      nimkit.keySpace,
      nimkit.keySlash,
      nimkit.keyDot,
      nimkit.keyComma,
      nimkit.keySemicolon,
      nimkit.keyQuote,
      nimkit.keyBackslash,
      nimkit.keyNumpad0 .. nimkit.keyNumpad9,
      nimkit.keyNumpadDot,
      nimkit.keyAdd,
      nimkit.keySubtract,
      nimkit.keyMultiply,
      nimkit.keyDivide:
    true
  else:
    false

func toNimkitColor(color: celina.ColorValue): nimkit.Color =
  let rgb = celina.toRgb(color)
  nimkit.color(
    float32(rgb.r) / 255.0'f32,
    float32(rgb.g) / 255.0'f32,
    float32(rgb.b) / 255.0'f32,
    1.0'f32,
  )

func toMonoTextCell*(cell: RenderCell): nimkit.MonoTextCell =
  var
    foreground = cell.style.fg
    background = cell.style.bg
  if celina.Reversed in cell.style.modifiers:
    swap foreground, background
  nimkit.initMonoTextCell(
    cell.symbol,
    foreground.toNimkitColor,
    background.toNimkitColor,
    foreground.kind != celina.Default,
    background.kind != celina.Default,
  )
