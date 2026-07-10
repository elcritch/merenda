import std/[math, options, parseutils, strutils, times]

import sigils/selectors

import ../drawing/images
import ../text/textstorage
import ../text/texttypes
import ./types

type
  ObjectValueKind* = enum
    ovNil
    ovEmpty
    ovString
    ovInt
    ovFloat
    ovBool
    ovTemporal
    ovColor
    ovImage
    ovAttributedText
    ovLink
    ovAgent
    ovValidationFailure

  ObjectValueRole* = enum
    ovrDefault
    ovrLabel
    ovrTextField
    ovrTableCell
    ovrComboBox
    ovrMenu
    ovrSlider
    ovrStepper
    ovrFormRow

  ObjectTemporalKind* = enum
    otDate
    otTime
    otDateTime
    otTimestamp

  ObjectDateValue* = object
    year*: int
    month*: int
    day*: int

  ObjectTimeValue* = object
    hour*: int
    minute*: int
    second*: int
    nanosecond*: int

  ObjectTemporalValue* = object
    case kind*: ObjectTemporalKind
    of otDate:
      dateValue*: ObjectDateValue
    of otTime:
      timeValue*: ObjectTimeValue
    of otDateTime:
      dateTimeValue*: DateTime
    of otTimestamp:
      timestampValue*: Time

  ObjectImageValue* = object
    name*: string
    filePath*: string
    size*: Size
    resource*: ImageResource

  ObjectAttributedTextValue* = object
    stringValue*: string
    runs*: seq[TextAttributeRun]

  ObjectLinkValue* = object
    url*: string
    title*: string

  ObjectValidationErrorKind* = enum
    oveNone
    oveRequired
    oveTypeMismatch
    oveParseFailed
    oveOutOfRange
    oveRejected
    oveUnsupported
    oveCustom

  ObjectValidationError* = object
    kind*: ObjectValidationErrorKind
    message*: string
    field*: string
    code*: string
    input*: string
    expectedKind*: ObjectValueKind
    actualKind*: ObjectValueKind

  ObjectValue* = object
    case kind*: ObjectValueKind
    of ovNil, ovEmpty:
      discard
    of ovString:
      text*: string
    of ovInt:
      intValue*: int
    of ovFloat:
      floatValue*: float
    of ovBool:
      boolValue*: bool
    of ovTemporal:
      temporalValue*: ObjectTemporalValue
    of ovColor:
      colorValue*: Color
    of ovImage:
      imageValue*: ObjectImageValue
    of ovAttributedText:
      attributedTextValue*: ObjectAttributedTextValue
    of ovLink:
      linkValue*: ObjectLinkValue
    of ovAgent:
      agentValue*: DynamicAgent
    of ovValidationFailure:
      validationError*: ObjectValidationError

  ObjectEmptyPolicy* = enum
    oepEmptyValue
    oepNilValue
    oepInvalid

  ObjectFormatContext* = object
    role*: ObjectValueRole
    nilString*: string
    emptyString*: string
    trueString*: string
    falseString*: string
    dateFormat*: string
    timeFormat*: string
    dateTimeFormat*: string

  ObjectParseContext* = object
    role*: ObjectValueRole
    expectedKind*: ObjectValueKind
    temporalKind*: ObjectTemporalKind
    emptyPolicy*: ObjectEmptyPolicy
    trimsWhitespace*: bool
    field*: string

  ObjectParseResultKind* = enum
    oprValue
    oprInvalid

  ObjectParseResult* = object
    case kind*: ObjectParseResultKind
    of oprValue:
      value*: ObjectValue
    of oprInvalid:
      error*: ObjectValidationError

  ObjectValueError* = object of ValueError

protocol ObjectValueFormatting {.selectorScope: protocol.}:
  method formatValue*(
    value: ObjectValue, context: ObjectFormatContext
  ): string {.optional.}

  method parseValue*(
    text: string, context: ObjectParseContext
  ): ObjectParseResult {.optional.}

proc initObjectFormatContext*(
    role = ovrDefault,
    nilString = "",
    emptyString = "",
    trueString = "true",
    falseString = "false",
    dateFormat = "yyyy-MM-dd",
    timeFormat = "HH:mm:ss",
    dateTimeFormat = "yyyy-MM-dd'T'HH:mm:ss",
): ObjectFormatContext =
  ObjectFormatContext(
    role: role,
    nilString: nilString,
    emptyString: emptyString,
    trueString: trueString,
    falseString: falseString,
    dateFormat: dateFormat,
    timeFormat: timeFormat,
    dateTimeFormat: dateTimeFormat,
  )

proc initObjectParseContext*(
    expectedKind = ovString,
    role = ovrTextField,
    temporalKind = otDateTime,
    emptyPolicy = oepEmptyValue,
    trimsWhitespace = true,
    field = "",
): ObjectParseContext =
  ObjectParseContext(
    role: role,
    expectedKind: expectedKind,
    temporalKind: temporalKind,
    emptyPolicy: emptyPolicy,
    trimsWhitespace: trimsWhitespace,
    field: field,
  )

func initObjectDateValue*(year, month, day: int): ObjectDateValue =
  ObjectDateValue(year: year, month: month, day: day)

func initObjectTimeValue*(
    hour, minute: int, second = 0, nanosecond = 0
): ObjectTimeValue =
  ObjectTimeValue(hour: hour, minute: minute, second: second, nanosecond: nanosecond)

func initObjectTemporalValue*(date: ObjectDateValue): ObjectTemporalValue =
  ObjectTemporalValue(kind: otDate, dateValue: date)

func initObjectTemporalValue*(time: ObjectTimeValue): ObjectTemporalValue =
  ObjectTemporalValue(kind: otTime, timeValue: time)

func initObjectTemporalValue*(dateTime: DateTime): ObjectTemporalValue =
  ObjectTemporalValue(kind: otDateTime, dateTimeValue: dateTime)

func initObjectTemporalValue*(timestamp: Time): ObjectTemporalValue =
  ObjectTemporalValue(kind: otTimestamp, timestampValue: timestamp)

proc initObjectImageValue*(image: ImageResource): ObjectImageValue =
  ObjectImageValue(
    name: image.name(), filePath: image.filePath(), size: image.size(), resource: image
  )

proc initObjectImageValue*(
    name = "", filePath = "", size = initSize(0.0, 0.0), resource: ImageResource = nil
): ObjectImageValue =
  ObjectImageValue(name: name, filePath: filePath, size: size, resource: resource)

proc initObjectAttributedTextValue*(
    stringValue = "", runs: openArray[TextAttributeRun] = []
): ObjectAttributedTextValue =
  ObjectAttributedTextValue(stringValue: stringValue, runs: @runs)

proc initObjectAttributedTextValue*(storage: TextStorage): ObjectAttributedTextValue =
  initObjectAttributedTextValue(storage.stringValue(), storage.attributeRuns())

func initObjectLinkValue*(url: string, title = ""): ObjectLinkValue =
  ObjectLinkValue(url: url, title: title)

func initObjectValidationError*(
    kind = oveNone,
    message = "",
    field = "",
    code = "",
    input = "",
    expectedKind = ovNil,
    actualKind = ovNil,
): ObjectValidationError =
  ObjectValidationError(
    kind: kind,
    message: message,
    field: field,
    code: code,
    input: input,
    expectedKind: expectedKind,
    actualKind: actualKind,
  )

func valid*(error: ObjectValidationError): bool =
  error.kind == oveNone

func failed*(error: ObjectValidationError): bool =
  not error.valid()

func initObjectParseResult*(value: ObjectValue): ObjectParseResult =
  ObjectParseResult(kind: oprValue, value: value)

func initObjectParseResult*(error: ObjectValidationError): ObjectParseResult =
  ObjectParseResult(kind: oprInvalid, error: error)

func valid*(parseResult: ObjectParseResult): bool =
  parseResult.kind == oprValue

func failed*(parseResult: ObjectParseResult): bool =
  parseResult.kind == oprInvalid

func nilObjectValue*(): ObjectValue =
  ObjectValue(kind: ovNil)

func emptyObjectValue*(): ObjectValue =
  ObjectValue(kind: ovEmpty)

func validationFailureValue*(error: ObjectValidationError): ObjectValue =
  ObjectValue(kind: ovValidationFailure, validationError: error)

converter toObj*(value: string): ObjectValue =
  ObjectValue(kind: ovString, text: value)

converter toObj*(value: int): ObjectValue =
  ObjectValue(kind: ovInt, intValue: value)

converter toObj*(value: float): ObjectValue =
  ObjectValue(kind: ovFloat, floatValue: value)

converter toObj*(value: float32): ObjectValue =
  ObjectValue(kind: ovFloat, floatValue: value.float)

converter toObj*(value: bool): ObjectValue =
  ObjectValue(kind: ovBool, boolValue: value)

converter toObj*(value: ObjectTemporalValue): ObjectValue =
  ObjectValue(kind: ovTemporal, temporalValue: value)

converter toObj*(value: ObjectDateValue): ObjectValue =
  toObj(initObjectTemporalValue(value))

converter toObj*(value: ObjectTimeValue): ObjectValue =
  toObj(initObjectTemporalValue(value))

converter toObj*(value: DateTime): ObjectValue =
  toObj(initObjectTemporalValue(value))

converter toObj*(value: Time): ObjectValue =
  toObj(initObjectTemporalValue(value))

converter toObj*(value: Color): ObjectValue =
  ObjectValue(kind: ovColor, colorValue: value)

converter toObj*(value: ImageResource): ObjectValue =
  if value.isNil:
    return nilObjectValue()
  ObjectValue(kind: ovImage, imageValue: initObjectImageValue(value))

converter toObj*(value: ObjectImageValue): ObjectValue =
  ObjectValue(kind: ovImage, imageValue: value)

converter toObj*(value: ObjectAttributedTextValue): ObjectValue =
  ObjectValue(kind: ovAttributedText, attributedTextValue: value)

converter toObj*(value: TextStorage): ObjectValue =
  if value.isNil:
    return nilObjectValue()
  ObjectValue(
    kind: ovAttributedText, attributedTextValue: initObjectAttributedTextValue(value)
  )

converter toObj*(value: ObjectLinkValue): ObjectValue =
  ObjectValue(kind: ovLink, linkValue: value)

converter toObj*(value: DynamicAgent): ObjectValue =
  if value.isNil:
    nilObjectValue()
  else:
    ObjectValue(kind: ovAgent, agentValue: value)

converter toObj*(error: ObjectValidationError): ObjectValue =
  validationFailureValue(error)

func `==`*(a, b: ObjectDateValue): bool =
  a.year == b.year and a.month == b.month and a.day == b.day

func `==`*(a, b: ObjectTimeValue): bool =
  a.hour == b.hour and a.minute == b.minute and a.second == b.second and
    a.nanosecond == b.nanosecond

func `==`*(a, b: ObjectTemporalValue): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of otDate:
    a.dateValue == b.dateValue
  of otTime:
    a.timeValue == b.timeValue
  of otDateTime:
    a.dateTimeValue == b.dateTimeValue
  of otTimestamp:
    a.timestampValue == b.timestampValue

func `==`*(a, b: ObjectImageValue): bool =
  a.name == b.name and a.filePath == b.filePath and a.size == b.size and
    a.resource == b.resource

func `==`*(a, b: ObjectAttributedTextValue): bool =
  a.stringValue == b.stringValue and a.runs == b.runs

func `==`*(a, b: ObjectLinkValue): bool =
  a.url == b.url and a.title == b.title

func `==`*(a, b: ObjectValidationError): bool =
  a.kind == b.kind and a.message == b.message and a.field == b.field and a.code == b.code and
    a.input == b.input and a.expectedKind == b.expectedKind and
    a.actualKind == b.actualKind

func `==`*(a, b: ObjectValue): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of ovNil, ovEmpty:
    true
  of ovString:
    a.text == b.text
  of ovInt:
    a.intValue == b.intValue
  of ovFloat:
    a.floatValue == b.floatValue
  of ovBool:
    a.boolValue == b.boolValue
  of ovTemporal:
    a.temporalValue == b.temporalValue
  of ovColor:
    a.colorValue == b.colorValue
  of ovImage:
    a.imageValue == b.imageValue
  of ovAttributedText:
    a.attributedTextValue == b.attributedTextValue
  of ovLink:
    a.linkValue == b.linkValue
  of ovAgent:
    a.agentValue == b.agentValue
  of ovValidationFailure:
    a.validationError == b.validationError

func isNil*(value: ObjectValue): bool =
  value.kind == ovNil

func isEmpty*(value: ObjectValue): bool =
  value.kind == ovEmpty

func isNilOrEmpty*(value: ObjectValue): bool =
  value.kind in {ovNil, ovEmpty}

func hasValidationFailure*(value: ObjectValue): bool =
  value.kind == ovValidationFailure and value.validationError.failed()

proc raiseObjectValueError(
    expected: string, value: ObjectValue
) {.noinline, noreturn.} =
  let message = "object value is " & $value.kind & ", expected " & expected
  raise newException(ObjectValueError, message)

func getString*(value: ObjectValue): Option[string] =
  if value.kind == ovString:
    some(value.text)
  else:
    none(string)

proc requireString*(value: ObjectValue): string {.raises: [ObjectValueError].} =
  if value.kind == ovString:
    return value.text
  raiseObjectValueError("string", value)

func getInt*(value: ObjectValue): Option[int] =
  if value.kind == ovInt:
    some(value.intValue)
  else:
    none(int)

proc requireInt*(value: ObjectValue): int {.raises: [ObjectValueError].} =
  if value.kind == ovInt:
    return value.intValue
  raiseObjectValueError("int", value)

func getFloat*(value: ObjectValue): Option[float] =
  if value.kind == ovFloat:
    some(value.floatValue)
  else:
    none(float)

proc requireFloat*(value: ObjectValue): float {.raises: [ObjectValueError].} =
  if value.kind == ovFloat:
    return value.floatValue
  raiseObjectValueError("float", value)

func getNumber*(value: ObjectValue): Option[float] =
  case value.kind
  of ovInt:
    some(value.intValue.float)
  of ovFloat:
    some(value.floatValue)
  else:
    none(float)

proc requireNumber*(value: ObjectValue): float {.raises: [ObjectValueError].} =
  case value.kind
  of ovInt:
    value.intValue.float
  of ovFloat:
    value.floatValue
  else:
    raiseObjectValueError("number", value)

func getBool*(value: ObjectValue): Option[bool] =
  if value.kind == ovBool:
    some(value.boolValue)
  else:
    none(bool)

proc requireBool*(value: ObjectValue): bool {.raises: [ObjectValueError].} =
  if value.kind == ovBool:
    return value.boolValue
  raiseObjectValueError("bool", value)

func getTemporal*(value: ObjectValue): Option[ObjectTemporalValue] =
  if value.kind == ovTemporal:
    some(value.temporalValue)
  else:
    none(ObjectTemporalValue)

proc requireTemporal*(
    value: ObjectValue
): ObjectTemporalValue {.raises: [ObjectValueError].} =
  if value.kind == ovTemporal:
    return value.temporalValue
  raiseObjectValueError("temporal", value)

func getColor*(value: ObjectValue): Option[Color] =
  if value.kind == ovColor:
    some(value.colorValue)
  else:
    none(Color)

proc requireColor*(value: ObjectValue): Color {.raises: [ObjectValueError].} =
  if value.kind == ovColor:
    return value.colorValue
  raiseObjectValueError("color", value)

func getImage*(value: ObjectValue): Option[ObjectImageValue] =
  if value.kind == ovImage:
    some(value.imageValue)
  else:
    none(ObjectImageValue)

proc requireImage*(
    value: ObjectValue
): ObjectImageValue {.raises: [ObjectValueError].} =
  if value.kind == ovImage:
    return value.imageValue
  raiseObjectValueError("image", value)

func getAttributedText*(value: ObjectValue): Option[ObjectAttributedTextValue] =
  if value.kind == ovAttributedText:
    some(value.attributedTextValue)
  else:
    none(ObjectAttributedTextValue)

proc requireAttributedText*(
    value: ObjectValue
): ObjectAttributedTextValue {.raises: [ObjectValueError].} =
  if value.kind == ovAttributedText:
    return value.attributedTextValue
  raiseObjectValueError("attributed text", value)

func getLink*(value: ObjectValue): Option[ObjectLinkValue] =
  if value.kind == ovLink:
    some(value.linkValue)
  else:
    none(ObjectLinkValue)

proc requireLink*(value: ObjectValue): ObjectLinkValue {.raises: [ObjectValueError].} =
  if value.kind == ovLink:
    return value.linkValue
  raiseObjectValueError("link", value)

func getAgent*(value: ObjectValue): Option[DynamicAgent] =
  if value.kind == ovAgent and not value.agentValue.isNil:
    some(value.agentValue)
  else:
    none(DynamicAgent)

proc requireAgent*(value: ObjectValue): DynamicAgent {.raises: [ObjectValueError].} =
  if value.kind == ovAgent and not value.agentValue.isNil:
    return value.agentValue
  raiseObjectValueError("agent", value)

func getValidationFailure*(value: ObjectValue): Option[ObjectValidationError] =
  if value.kind == ovValidationFailure:
    some(value.validationError)
  else:
    none(ObjectValidationError)

proc requireValidationFailure*(
    value: ObjectValue
): ObjectValidationError {.raises: [ObjectValueError].} =
  if value.kind == ovValidationFailure:
    return value.validationError
  raiseObjectValueError("validation failure", value)

func displayMessage*(error: ObjectValidationError): string =
  if error.message.len > 0:
    return error.message
  case error.kind
  of oveNone: ""
  of oveRequired: "Value is required"
  of oveTypeMismatch: "Value has the wrong type"
  of oveParseFailed: "Value could not be parsed"
  of oveOutOfRange: "Value is out of range"
  of oveRejected: "Value was rejected"
  of oveUnsupported: "Value is unsupported"
  of oveCustom: "Value is invalid"

func withRole*(
    context: ObjectFormatContext, role: ObjectValueRole
): ObjectFormatContext =
  result = context
  result.role = role

func withRole*(context: ObjectParseContext, role: ObjectValueRole): ObjectParseContext =
  result = context
  result.role = role

func expecting*(
    context: ObjectParseContext,
    expectedKind: ObjectValueKind,
    temporalKind = otDateTime,
): ObjectParseContext =
  result = context
  result.expectedKind = expectedKind
  result.temporalKind = temporalKind

func withEmptyPolicy*(
    context: ObjectParseContext, emptyPolicy: ObjectEmptyPolicy
): ObjectParseContext =
  result = context
  result.emptyPolicy = emptyPolicy

func withField*(context: ObjectParseContext, field: string): ObjectParseContext =
  result = context
  result.field = field

func normalizedInput(text: string, context: ObjectParseContext): string =
  if context.trimsWhitespace:
    text.strip()
  else:
    text

func validationError(
    kind: ObjectValidationErrorKind,
    context: ObjectParseContext,
    input, message: string,
    actualKind = ovString,
): ObjectValidationError =
  initObjectValidationError(
    kind,
    message = message,
    field = context.field,
    input = input,
    expectedKind = context.expectedKind,
    actualKind = actualKind,
  )

func parseFailed(
    context: ObjectParseContext, input, message: string
): ObjectParseResult =
  initObjectParseResult(validationError(oveParseFailed, context, input, message))

func unsupportedParser(context: ObjectParseContext, input: string): ObjectParseResult =
  initObjectParseResult(
    validationError(
      oveUnsupported,
      context,
      input,
      "No default text parser is available for " & $context.expectedKind,
    )
  )

func hexDigit(value: char): int =
  case value
  of '0' .. '9':
    ord(value) - ord('0')
  of 'a' .. 'f':
    ord(value) - ord('a') + 10
  of 'A' .. 'F':
    ord(value) - ord('A') + 10
  else:
    -1

func parseHexByte(text: string, offset: int, value: var int): bool =
  if offset + 1 >= text.len:
    return false
  let
    hi = hexDigit(text[offset])
    lo = hexDigit(text[offset + 1])
  if hi < 0 or lo < 0:
    return false
  value = hi * 16 + lo
  true

func parseColorValue(input: string, color: var Color): bool =
  if input.len notin {7, 9} or input[0] != '#':
    return false
  var r, g, b, a: int
  if not parseHexByte(input, 1, r) or not parseHexByte(input, 3, g) or
      not parseHexByte(input, 5, b):
    return false
  a = 255
  if input.len == 9 and not parseHexByte(input, 7, a):
    return false
  color = color(
    r.float32 / 255.0'f32,
    g.float32 / 255.0'f32,
    b.float32 / 255.0'f32,
    a.float32 / 255.0'f32,
  )
  true

func componentByte(value: float32): int =
  int(round(min(max(value, 0.0'f32), 1.0'f32) * 255.0'f32))

func colorHex(color: Color): string =
  result = "#"
  result.add toHex(componentByte(color.r), 2)
  result.add toHex(componentByte(color.g), 2)
  result.add toHex(componentByte(color.b), 2)
  let alpha = componentByte(color.a)
  if alpha < 255:
    result.add toHex(alpha, 2)

func formatDate(date: ObjectDateValue): string =
  align($date.year, 4, '0') & "-" & align($date.month, 2, '0') & "-" &
    align($date.day, 2, '0')

func formatTime(time: ObjectTimeValue): string =
  align($time.hour, 2, '0') & ":" & align($time.minute, 2, '0') & ":" &
    align($time.second, 2, '0')

proc formatTemporal(value: ObjectTemporalValue, context: ObjectFormatContext): string =
  case value.kind
  of otDate:
    value.dateValue.formatDate()
  of otTime:
    value.timeValue.formatTime()
  of otDateTime:
    value.dateTimeValue.format(context.dateTimeFormat)
  of otTimestamp:
    value.timestampValue.format(context.dateTimeFormat)

proc defaultFormatObjectValue*(
    value: ObjectValue, context = initObjectFormatContext()
): string =
  case value.kind
  of ovNil:
    context.nilString
  of ovEmpty:
    context.emptyString
  of ovString:
    value.text
  of ovInt:
    $value.intValue
  of ovFloat:
    formatFloat(value.floatValue, ffDefault, -1)
  of ovBool:
    if value.boolValue: context.trueString else: context.falseString
  of ovTemporal:
    value.temporalValue.formatTemporal(context)
  of ovColor:
    value.colorValue.colorHex()
  of ovImage:
    if value.imageValue.name.len > 0:
      value.imageValue.name
    elif value.imageValue.filePath.len > 0:
      value.imageValue.filePath
    else:
      "image"
  of ovAttributedText:
    value.attributedTextValue.stringValue
  of ovLink:
    if value.linkValue.title.len > 0: value.linkValue.title else: value.linkValue.url
  of ovAgent:
    if value.agentValue.isNil: "" else: "agent"
  of ovValidationFailure:
    value.validationError.displayMessage()

proc formatObjectValue*(
    formatter: DynamicAgent, value: ObjectValue, context = initObjectFormatContext()
): string =
  if not formatter.isNil:
    let formatted =
      formatter.trySendLocal(formatValue(), (value: value, context: context))
    if formatted.isSome:
      return formatted.get()
  defaultFormatObjectValue(value, context)

proc formatObjectValue*(
    value: ObjectValue, context = initObjectFormatContext()
): string =
  defaultFormatObjectValue(value, context)

proc parseObjectDate(input: string, date: var ObjectDateValue): bool =
  let parts = input.split('-')
  if parts.len != 3:
    return false
  try:
    date =
      initObjectDateValue(parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2]))
    result = date.month in 1 .. 12 and date.day in 1 .. 31
  except ValueError:
    result = false

proc parseObjectTime(input: string, time: var ObjectTimeValue): bool =
  let parts = input.split(':')
  if parts.len notin {2, 3}:
    return false
  try:
    let
      hour = parseInt(parts[0])
      minute = parseInt(parts[1])
      second =
        if parts.len == 3:
          parseInt(parts[2])
        else:
          0
    if hour notin 0 .. 23 or minute notin 0 .. 59 or second notin 0 .. 60:
      return false
    time = initObjectTimeValue(hour, minute, second)
    result = true
  except ValueError:
    result = false

proc parseObjectDateTime(input: string, dateTime: var DateTime): bool =
  try:
    dateTime = parse(input, "yyyy-MM-dd'T'HH:mm:ss")
    return true
  except TimeParseError:
    discard
  try:
    dateTime = parse(input, "yyyy-MM-dd HH:mm:ss")
    return true
  except TimeParseError:
    false

proc parseTemporalValue(
    input: string, temporalKind: ObjectTemporalKind, value: var ObjectTemporalValue
): bool =
  case temporalKind
  of otDate:
    var date: ObjectDateValue
    result = parseObjectDate(input, date)
    if result:
      value = initObjectTemporalValue(date)
  of otTime:
    var time: ObjectTimeValue
    result = parseObjectTime(input, time)
    if result:
      value = initObjectTemporalValue(time)
  of otDateTime:
    var dateTime: DateTime
    result = parseObjectDateTime(input, dateTime)
    if result:
      value = initObjectTemporalValue(dateTime)
  of otTimestamp:
    var dateTime: DateTime
    result = parseObjectDateTime(input, dateTime)
    if result:
      value = initObjectTemporalValue(dateTime.toTime())

proc defaultParseObjectValue*(
    text: string, context = initObjectParseContext()
): ObjectParseResult =
  let input = text.normalizedInput(context)
  if input.len == 0:
    case context.emptyPolicy
    of oepEmptyValue:
      return initObjectParseResult(emptyObjectValue())
    of oepNilValue:
      return initObjectParseResult(nilObjectValue())
    of oepInvalid:
      return initObjectParseResult(
        validationError(oveRequired, context, input, "Value is required")
      )

  case context.expectedKind
  of ovNil:
    initObjectParseResult(
      validationError(oveTypeMismatch, context, input, "Expected an empty nil value")
    )
  of ovEmpty:
    initObjectParseResult(
      validationError(oveTypeMismatch, context, input, "Expected an empty value")
    )
  of ovString:
    initObjectParseResult(toObj(input))
  of ovInt:
    var value: int
    let parsed = parseutils.parseInt(input, value)
    if parsed == input.len:
      initObjectParseResult(toObj(value))
    else:
      parseFailed(context, input, "Expected an integer")
  of ovFloat:
    var value: float
    let parsed = parseutils.parseFloat(input, value)
    if parsed == input.len and value.classify notin {fcNan, fcInf, fcNegInf}:
      initObjectParseResult(toObj(value))
    else:
      parseFailed(context, input, "Expected a finite number")
  of ovBool:
    case input.normalize()
    of "true", "yes", "on", "1":
      initObjectParseResult(toObj(true))
    of "false", "no", "off", "0":
      initObjectParseResult(toObj(false))
    else:
      parseFailed(context, input, "Expected true or false")
  of ovTemporal:
    var value: ObjectTemporalValue
    if parseTemporalValue(input, context.temporalKind, value):
      initObjectParseResult(toObj(value))
    else:
      parseFailed(context, input, "Expected a date or time value")
  of ovColor:
    var color: Color
    if parseColorValue(input, color):
      initObjectParseResult(toObj(color))
    else:
      parseFailed(context, input, "Expected a color like #RRGGBB")
  of ovLink:
    initObjectParseResult(toObj(initObjectLinkValue(input)))
  of ovImage, ovAttributedText, ovAgent, ovValidationFailure:
    unsupportedParser(context, input)

proc parseObjectValue*(
    formatter: DynamicAgent, text: string, context = initObjectParseContext()
): ObjectParseResult =
  if not formatter.isNil:
    let parsed = formatter.trySendLocal(parseValue(), (text: text, context: context))
    if parsed.isSome:
      return parsed.get()
  defaultParseObjectValue(text, context)

proc parseObjectValue*(
    text: string, context = initObjectParseContext()
): ObjectParseResult =
  defaultParseObjectValue(text, context)
