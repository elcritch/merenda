import ./runtime

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
    discard self
    discard partial
    discard editing
    discard errorDescription
    raiseInvalidAbstract("isPartialStringValid:newEditingString:errorDescription:")

  method getObjectValue*(
      self: NSFormatter,
      objectValue: ptr IDPtr,
      stringValue {.kw("forString").}: NSString,
      errorDescription {.kw("errorDescription").}: ptr IDPtr,
  ): bool =
    discard self
    discard objectValue
    discard stringValue
    discard errorDescription
    raiseInvalidAbstract("getObjectValue:forString:errorDescription:")

  method stringForObjectValue*(self: NSFormatter, objectValue: NSObject): NSString =
    discard self
    discard objectValue
    raiseInvalidAbstract("stringForObjectValue:")

  method editingStringForObjectValue*(
      self: NSFormatter, objectValue: NSObject
  ): NSString =
    discard self
    discard objectValue
    raiseInvalidAbstract("editingStringForObjectValue:")

  method attributedStringForObjectValue*(
      self: NSFormatter,
      objectValue: NSObject,
      attributes {.kw("withDefaultAttributes").}: NSDictionary[NSObject, NSObject],
  ): NSAttributedString =
    discard self
    discard objectValue
    discard attributes
    raiseInvalidAbstract("attributedStringForObjectValue:withDefaultAttributes:")

  method isPartialStringValid*(
      self: NSFormatter,
      partialStringp: ptr IDPtr,
      proposedRangep {.kw("proposedSelectedRange").}: ptr NSRange,
      originalString {.kw("originalString").}: NSString,
      originalRange {.kw("originalSelectedRange").}: NSRange,
      errorStringp {.kw("errorDescription").}: ptr IDPtr,
  ): bool =
    discard self
    discard partialStringp
    discard proposedRangep
    discard originalString
    discard originalRange
    discard errorStringp
    raiseInvalidAbstract(
      "isPartialStringValid:proposedSelectedRange:originalString:originalSelectedRange:errorDescription:"
    )

  method initWithCoder*(self: var NSFormatter, coder: ID): NSFormatter =
    discard coder
    result = self

  method encodeWithCoder*(self: NSFormatter, coder: ID) =
    discard self
    discard coder

proc new*(t: typedesc[NSFormatter]): NSFormatter =
  var allocated = NSFormatter.alloc()
  result = initOwned(move(allocated))
