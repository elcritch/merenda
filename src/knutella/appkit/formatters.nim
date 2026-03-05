import std/strutils

import ./runtime
import ./valueproviders

proc trimTrailingFraction(text: string): string =
  result = text
  if result.contains('.'):
    while result.len > 0 and result[^1] == '0':
      result.setLen(result.len - 1)
    if result.len > 0 and result[^1] == '.':
      result.setLen(result.len - 1)
  if result == "-0":
    result = "0"

proc raiseInvalidAbstract(selectorName: string) {.noreturn.} =
  raise newException(
    CatchableError, "NSInvalidAbstractInvocation: -[NSFormatter " & selectorName & "]"
  )

objcImpl:
  type NSFormatter* = object of NSObject

  method isPartialStringValid*(
      self: NSFormatter,
      partial: NSString,
      editing {.kw("newEditingString").}: ptr IDPtr,
      errorDescription {.kw("errorDescription").}: ptr IDPtr,
  ): bool =
    raiseInvalidAbstract("isPartialStringValid:newEditingString:errorDescription:")

  method getObjectValue*(
      self: NSFormatter,
      objectValue: ptr IDPtr,
      stringValue {.kw("forString").}: NSString,
      errorDescription {.kw("errorDescription").}: ptr IDPtr,
  ): bool =
    raiseInvalidAbstract("getObjectValue:forString:errorDescription:")

  method stringForObjectValue*(self: NSFormatter, objectValue: NSObject): NSString =
    raiseInvalidAbstract("stringForObjectValue:")

  method editingStringForObjectValue*(
      self: NSFormatter, objectValue: NSObject
  ): NSString =
    raiseInvalidAbstract("editingStringForObjectValue:")

  method attributedStringForObjectValue*(
      self: NSFormatter,
      objectValue: NSObject,
      attributes {.kw("withDefaultAttributes").}: NSDictionary[NSObject, NSObject],
  ): NSAttributedString =
    raiseInvalidAbstract("attributedStringForObjectValue:withDefaultAttributes:")

  method isPartialStringValid*(
      self: NSFormatter,
      partialStringp: ptr IDPtr,
      proposedRangep {.kw("proposedSelectedRange").}: ptr NSRange,
      originalString {.kw("originalString").}: NSString,
      originalRange {.kw("originalSelectedRange").}: NSRange,
      errorStringp {.kw("errorDescription").}: ptr IDPtr,
  ): bool =
    raiseInvalidAbstract(
      "isPartialStringValid:proposedSelectedRange:originalString:originalSelectedRange:errorDescription:"
    )

  method initWithCoder*(self: var NSFormatter, coder: ID): NSFormatter =
    result = self

  method encodeWithCoder*(self: NSFormatter, coder: ID) =
    discard

proc new*(t: typedesc[NSFormatter]): NSFormatter =
  var allocated = NSFormatter.alloc()
  result = initOwned(move(allocated))

objcImpl:
  type NSNumberFormatter* = object of NSFormatter
    xFormat {.set: setFormat, get: format.}: NSString

  method stringForObjectValue*(
      self: NSNumberFormatter, objectValue: NSObject
  ): NSString =
    if objectValue.isNil:
      return @ns""

    let formatText =
      if self.xFormat.isNil:
        ""
      else:
        $self.xFormat
    let decimalPos = formatText.find('.')
    let rawValue = objectFloatValue(objectValue).float
    if decimalPos < 0:
      return @ns(trimTrailingFraction(formatFloat(rawValue, ffDecimal, 15)))

    let fractionDigits = max(formatText.len - decimalPos - 1, 0)
    @ns(formatFloat(rawValue, ffDecimal, fractionDigits))

  method getObjectValue*(
      self: NSNumberFormatter,
      objectValue: ptr IDPtr,
      stringValue {.kw("forString").}: NSString,
      errorDescription {.kw("errorDescription").}: ptr IDPtr,
  ): bool =
    if objectValue != nil:
      objectValue[] = nil
    if errorDescription != nil:
      errorDescription[] = nil
    if stringValue.isNil:
      return false
    try:
      let parsed = parseFloat(($stringValue).strip())
      if objectValue != nil:
        var boxed = boxNSObject(parsed)
        objectValue[] = boxed.value
        boxed.value = nil
      true
    except ValueError:
      false

proc new*(t: typedesc[NSNumberFormatter]): NSNumberFormatter =
  var allocated = NSNumberFormatter.alloc()
  result = initOwned(move(allocated))
