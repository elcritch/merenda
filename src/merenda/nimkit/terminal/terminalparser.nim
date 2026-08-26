## Incremental ECMA-48/VT parser that applies terminal output to a screen.

import std/[base64, parseutils, strutils]

import ./terminalscreen

const
  MaxTerminalCsiBytes* = 1024
  MaxTerminalStringBytes* = 64 * 1024
  ReplacementCharacter = "\xef\xbf\xbd"

type
  TerminalParserState* = enum
    tpsGround
    tpsEscape
    tpsCsi
    tpsOsc
    tpsOscEscape
    tpsString
    tpsStringEscape
    tpsCharset

  TerminalParser* = object
    state*: TerminalParserState
    sequence: string
    incompleteUtf8: string

func initTerminalParser*(): TerminalParser =
  TerminalParser(state: tpsGround)

func parameterValue(
    parameters: openArray[int], index, fallback: int, zeroIsFallback = true
): int =
  if index >= parameters.len:
    return fallback
  if zeroIsFallback and parameters[index] == 0:
    fallback
  else:
    parameters[index]

proc parseParameters(value: string): seq[int] =
  if value.len == 0:
    return @[0]
  var parameter = ""
  for character in value:
    if character in {';', ':'}:
      if parameter.len == 0:
        result.add 0
      else:
        result.add parseInt(parameter)
      parameter.setLen(0)
    elif character in {'0' .. '9'}:
      parameter.add character
  if parameter.len == 0:
    result.add 0
  else:
    result.add parseInt(parameter)

proc applyExtendedColor(
    color: var TerminalColor, parameters: openArray[int], index: var int
) =
  if index + 1 >= parameters.len:
    inc index
    return
  case parameters[index + 1]
  of 5:
    if index + 2 < parameters.len:
      color = indexedTerminalColor(uint8(clamp(parameters[index + 2], 0, 255)))
      inc index, 3
    else:
      inc index, 2
  of 2:
    if index + 4 < parameters.len:
      color = rgbTerminalColor(
        uint8(clamp(parameters[index + 2], 0, 255)),
        uint8(clamp(parameters[index + 3], 0, 255)),
        uint8(clamp(parameters[index + 4], 0, 255)),
      )
      inc index, 5
    else:
      index = parameters.len
  else:
    inc index, 2

proc applyGraphicRendition(screen: var TerminalScreen, parameters: seq[int]) =
  var index = 0
  while index < parameters.len:
    let code = parameters[index]
    case code
    of 0:
      screen.style = initTerminalStyle()
      inc index
    of 1:
      screen.style.attributes.incl taBold
      inc index
    of 2:
      screen.style.attributes.incl taFaint
      inc index
    of 3:
      screen.style.attributes.incl taItalic
      inc index
    of 4:
      screen.style.attributes.excl taDoubleUnderline
      screen.style.attributes.incl taUnderline
      inc index
    of 5, 6:
      screen.style.attributes.incl taBlink
      inc index
    of 7:
      screen.style.attributes.incl taInverse
      inc index
    of 8:
      screen.style.attributes.incl taHidden
      inc index
    of 9:
      screen.style.attributes.incl taStrikethrough
      inc index
    of 21:
      screen.style.attributes.excl taUnderline
      screen.style.attributes.incl taDoubleUnderline
      inc index
    of 22:
      screen.style.attributes.excl taBold
      screen.style.attributes.excl taFaint
      inc index
    of 23:
      screen.style.attributes.excl taItalic
      inc index
    of 24:
      screen.style.attributes.excl taUnderline
      screen.style.attributes.excl taDoubleUnderline
      inc index
    of 25:
      screen.style.attributes.excl taBlink
      inc index
    of 27:
      screen.style.attributes.excl taInverse
      inc index
    of 28:
      screen.style.attributes.excl taHidden
      inc index
    of 29:
      screen.style.attributes.excl taStrikethrough
      inc index
    of 30 .. 37:
      screen.style.foreground = indexedTerminalColor(uint8(code - 30))
      inc index
    of 38:
      applyExtendedColor(screen.style.foreground, parameters, index)
    of 39:
      screen.style.foreground = defaultTerminalColor()
      inc index
    of 40 .. 47:
      screen.style.background = indexedTerminalColor(uint8(code - 40))
      inc index
    of 48:
      applyExtendedColor(screen.style.background, parameters, index)
    of 49:
      screen.style.background = defaultTerminalColor()
      inc index
    of 53:
      screen.style.attributes.incl taOverline
      inc index
    of 55:
      screen.style.attributes.excl taOverline
      inc index
    of 58:
      applyExtendedColor(screen.style.underlineColor, parameters, index)
    of 59:
      screen.style.underlineColor = defaultTerminalColor()
      inc index
    of 90 .. 97:
      screen.style.foreground = indexedTerminalColor(uint8(code - 90 + 8))
      inc index
    of 100 .. 107:
      screen.style.background = indexedTerminalColor(uint8(code - 100 + 8))
      inc index
    else:
      inc index

proc setPrivateMode(screen: var TerminalScreen, mode: int, enabled: bool) =
  case mode
  of 1:
    screen.modes.applicationCursorKeys = enabled
  of 6:
    screen.modes.origin = enabled
    screen.moveCursor(0, 0)
  of 7:
    screen.modes.autoWrap = enabled
  of 12:
    screen.cursor.blinking = enabled
  of 25:
    screen.cursor.visible = enabled
  of 47, 1047:
    screen.useAlternateScreen(enabled, saveRestore = false)
  of 1048:
    if enabled:
      screen.saveCursor()
    else:
      screen.restoreCursor()
  of 1049:
    screen.useAlternateScreen(enabled, saveRestore = true)
  of 9:
    screen.modes.mouseTracking = if enabled: tmtX10 else: tmtNone
  of 1000, 1002:
    screen.modes.mouseTracking = if enabled: tmtButton else: tmtNone
  of 1003:
    screen.modes.mouseTracking = if enabled: tmtAny else: tmtNone
  of 1004:
    screen.modes.focusReporting = enabled
  of 1005:
    screen.modes.mouseEncoding = if enabled: tmeUtf8 else: tmeX10
  of 1006:
    screen.modes.mouseEncoding = if enabled: tmeSgr else: tmeX10
  of 1015:
    screen.modes.mouseEncoding = if enabled: tmeUrxvt else: tmeX10
  of 2004:
    screen.modes.bracketedPaste = enabled
  else:
    discard

proc applyMode(
    screen: var TerminalScreen, parameters: seq[int], privateMode, enabled: bool
) =
  for mode in parameters:
    if privateMode:
      screen.setPrivateMode(mode, enabled)
    elif mode == 4:
      screen.modes.insert = enabled

proc setCursorStyle(screen: var TerminalScreen, value: int) =
  case value
  of 0, 1:
    screen.cursor.shape = tcsBlock
    screen.cursor.blinking = true
  of 2:
    screen.cursor.shape = tcsBlock
    screen.cursor.blinking = false
  of 3:
    screen.cursor.shape = tcsUnderline
    screen.cursor.blinking = true
  of 4:
    screen.cursor.shape = tcsUnderline
    screen.cursor.blinking = false
  of 5:
    screen.cursor.shape = tcsBar
    screen.cursor.blinking = true
  of 6:
    screen.cursor.shape = tcsBar
    screen.cursor.blinking = false
  else:
    discard

proc processCsi(screen: var TerminalScreen, sequence: string) =
  if sequence.len == 0:
    return
  let
    finalByte = sequence[^1]
    body = sequence[0 ..^ 2]
    privateMode = body.len > 0 and body[0] == '?'
    secondary = body.len > 0 and body[0] == '>'
    parameterStart = if privateMode or secondary: 1 else: 0
  var
    parameterEnd = body.len
    intermediate = ""
  while parameterEnd > parameterStart and body[parameterEnd - 1] in {' ' .. '/'}:
    dec parameterEnd
  if parameterEnd < body.len:
    intermediate = body[parameterEnd ..< body.len]
  let parameters = parseParameters(body[parameterStart ..< parameterEnd])
  let first = parameterValue(parameters, 0, 1)

  case finalByte
  of 'A':
    screen.moveCursorRelative(-first, 0)
  of 'B', 'e':
    screen.moveCursorRelative(first, 0)
  of 'C', 'a':
    screen.moveCursorRelative(0, first)
  of 'D':
    screen.moveCursorRelative(0, -first)
  of 'E':
    screen.moveCursorRelative(first, 0)
    screen.carriageReturn()
  of 'F':
    screen.moveCursorRelative(-first, 0)
    screen.carriageReturn()
  of 'G', '`':
    screen.moveCursor(screen.cursor.position.row, first - 1)
  of 'H', 'f':
    screen.moveCursor(
      parameterValue(parameters, 0, 1) - 1, parameterValue(parameters, 1, 1) - 1
    )
  of 'd':
    screen.moveCursor(first - 1, screen.cursor.position.column)
  of 'J':
    screen.eraseInDisplay(parameterValue(parameters, 0, 0, zeroIsFallback = false))
  of 'K':
    screen.eraseInLine(parameterValue(parameters, 0, 0, zeroIsFallback = false))
  of 'L':
    screen.insertLines(first)
  of 'M':
    screen.deleteLines(first)
  of '@':
    screen.insertCells(first)
  of 'P':
    screen.deleteCells(first)
  of 'X':
    screen.eraseCells(first)
  of 'S':
    screen.scrollUp(first)
  of 'T':
    screen.scrollDown(first)
  of 'b':
    screen.repeatLastText(first)
  of 'c':
    if secondary:
      screen.queueReply("\x1b[>0;1;0c")
    else:
      screen.queueReply("\x1b[?62;22c")
  of 'g':
    let mode = parameterValue(parameters, 0, 0, zeroIsFallback = false)
    screen.clearTabStop(all = mode == 3)
  of 'h':
    screen.applyMode(parameters, privateMode, true)
  of 'l':
    screen.applyMode(parameters, privateMode, false)
  of 'm':
    screen.applyGraphicRendition(parameters)
  of 'n':
    let mode = parameterValue(parameters, 0, 0, zeroIsFallback = false)
    if privateMode and mode == 6:
      screen.queueReply(
        "\x1b[?" & $(screen.cursor.position.row + 1) & ";" &
          $(screen.cursor.position.column + 1) & "R"
      )
    elif not privateMode and mode == 5:
      screen.queueReply("\x1b[0n")
    elif not privateMode and mode == 6:
      screen.queueReply(
        "\x1b[" & $(screen.cursor.position.row + 1) & ";" &
          $(screen.cursor.position.column + 1) & "R"
      )
  of 'r':
    screen.setScrollRegion(
      parameterValue(parameters, 0, 1) - 1,
      parameterValue(parameters, 1, screen.rows) - 1,
    )
  of 's':
    screen.saveCursor()
  of 'u':
    screen.restoreCursor()
  of 'q':
    if intermediate == " ":
      screen.setCursorStyle(parameterValue(parameters, 0, 0, zeroIsFallback = false))
  else:
    discard

proc processOsc(screen: var TerminalScreen, sequence: string) =
  let separator = sequence.find(';')
  if separator < 0:
    return
  var command = 0
  if parseInt(sequence, command, 0) != separator:
    return
  let payload = sequence[separator + 1 ..< sequence.len]
  case command
  of 0:
    screen.iconName = payload
    screen.title = payload
  of 1:
    screen.iconName = payload
  of 2:
    screen.title = payload
  of 7:
    screen.currentDirectory = payload
  of 8:
    let uriSeparator = payload.find(';')
    screen.style.hyperlink =
      if uriSeparator >= 0:
        payload[uriSeparator + 1 ..< payload.len]
      else:
        ""
  of 52:
    let dataSeparator = payload.find(';')
    if dataSeparator >= 0:
      let encoded = payload[dataSeparator + 1 ..< payload.len]
      if encoded == "?":
        screen.queueReply("\x1b]52;c;" & encode(screen.clipboardText) & "\x1b\\")
      else:
        try:
          screen.clipboardText = decode(encoded)
          screen.clipboardRequestPending = true
        except ValueError:
          discard
  else:
    discard

proc processControl(screen: var TerminalScreen, character: char) =
  case character
  of '\x07':
    discard
  of '\x08':
    screen.backspace()
  of '\x09':
    screen.horizontalTab()
  of '\x0a', '\x0b', '\x0c':
    screen.lineFeed()
  of '\x0d':
    screen.carriageReturn()
  else:
    discard

proc processEscape(screen: var TerminalScreen, character: char) =
  case character
  of '7':
    screen.saveCursor()
  of '8':
    screen.restoreCursor()
  of 'D':
    screen.lineFeed()
  of 'E':
    screen.nextLine()
  of 'H':
    screen.setTabStop()
  of 'M':
    screen.reverseIndex()
  of 'c':
    screen.reset()
  of '=':
    screen.modes.applicationKeypad = true
  of '>':
    screen.modes.applicationKeypad = false
  else:
    discard

func utf8Length(character: char): int =
  let value = character.uint8
  if value <= 0x7f'u8:
    1
  elif value in 0xc2'u8 .. 0xdf'u8:
    2
  elif value in 0xe0'u8 .. 0xef'u8:
    3
  elif value in 0xf0'u8 .. 0xf4'u8:
    4
  else:
    0

func validContinuation(character: char): bool =
  character.uint8 in 0x80'u8 .. 0xbf'u8

func validUtf8Sequence(value: string): bool =
  if value.len < 2:
    return value.len == 1 and value[0].uint8 <= 0x7f'u8
  for index in 1 ..< value.len:
    if not value[index].validContinuation():
      return false
  let first = value[0].uint8
  if value.len == 3:
    let second = value[1].uint8
    if (first == 0xe0'u8 and second < 0xa0'u8) or
        (first == 0xed'u8 and second >= 0xa0'u8):
      return false
  elif value.len == 4:
    let second = value[1].uint8
    if (first == 0xf0'u8 and second < 0x90'u8) or (
      first == 0xf4'u8 and second > 0x8f'u8
    ):
      return false
  true

proc finishOsc(parser: var TerminalParser, screen: var TerminalScreen) =
  screen.processOsc(parser.sequence)
  parser.sequence.setLen(0)
  parser.state = tpsGround

proc feed*(parser: var TerminalParser, screen: var TerminalScreen, data: string) =
  var input =
    if parser.incompleteUtf8.len > 0:
      parser.incompleteUtf8 & data
    else:
      data
  parser.incompleteUtf8.setLen(0)
  var index = 0
  while index < input.len:
    let character = input[index]
    case parser.state
    of tpsGround:
      if character == '\x1b':
        parser.state = tpsEscape
      elif character < '\x20' or character == '\x7f':
        screen.processControl(character)
      elif character < '\x80':
        screen.writeText($character)
      else:
        let length = character.utf8Length()
        if length == 0:
          screen.writeText(ReplacementCharacter)
        elif index + length > input.len:
          parser.incompleteUtf8 = input[index ..< input.len]
          return
        else:
          let candidate = input[index ..< index + length]
          if candidate.validUtf8Sequence():
            screen.writeText(candidate)
            inc index, length - 1
          else:
            screen.writeText(ReplacementCharacter)
    of tpsEscape:
      case character
      of '[':
        parser.sequence.setLen(0)
        parser.state = tpsCsi
      of ']':
        parser.sequence.setLen(0)
        parser.state = tpsOsc
      of 'P', 'X', '^', '_':
        parser.sequence.setLen(0)
        parser.state = tpsString
      of '(', ')', '*', '+', '#':
        parser.state = tpsCharset
      of '\\':
        parser.state = tpsGround
      else:
        screen.processEscape(character)
        parser.state = tpsGround
    of tpsCsi:
      if character in {'\x40' .. '\x7e'}:
        parser.sequence.add character
        screen.processCsi(parser.sequence)
        parser.sequence.setLen(0)
        parser.state = tpsGround
      elif character in {'\x20' .. '\x3f'}:
        if parser.sequence.len < MaxTerminalCsiBytes:
          parser.sequence.add character
        else:
          parser.sequence.setLen(0)
          parser.state = tpsGround
      elif character == '\x1b':
        parser.sequence.setLen(0)
        parser.state = tpsEscape
      elif character in {'\x18', '\x1a'}:
        parser.sequence.setLen(0)
        parser.state = tpsGround
      elif character < '\x20':
        screen.processControl(character)
      else:
        parser.sequence.setLen(0)
        parser.state = tpsGround
    of tpsOsc:
      if character == '\x07':
        parser.finishOsc(screen)
      elif character == '\x1b':
        parser.state = tpsOscEscape
      elif character in {'\x18', '\x1a'}:
        parser.sequence.setLen(0)
        parser.state = tpsGround
      elif parser.sequence.len < MaxTerminalStringBytes:
        parser.sequence.add character
      else:
        parser.sequence.setLen(0)
        parser.state = tpsGround
    of tpsOscEscape:
      if character == '\\':
        parser.finishOsc(screen)
      else:
        if parser.sequence.len + 2 < MaxTerminalStringBytes:
          parser.sequence.add '\x1b'
          parser.sequence.add character
          parser.state = tpsOsc
        else:
          parser.sequence.setLen(0)
          parser.state = tpsGround
    of tpsString:
      if character == '\x1b':
        parser.state = tpsStringEscape
      elif character == '\x07' or character in {'\x18', '\x1a'}:
        parser.state = tpsGround
      elif parser.sequence.len < MaxTerminalStringBytes:
        parser.sequence.add character
      else:
        parser.sequence.setLen(0)
        parser.state = tpsGround
    of tpsStringEscape:
      if character == '\\':
        parser.sequence.setLen(0)
        parser.state = tpsGround
      else:
        parser.state = tpsString
    of tpsCharset:
      parser.state = tpsGround
    inc index

proc reset*(parser: var TerminalParser) =
  parser = initTerminalParser()
