import std/[strutils, unittest]

import merenda/appkit
import merenda/objc

var parseCallCount = 0
var formatCallCount = 0

objcImpl:
  type TIntFormatter = object of NSFormatter

  method getObjectValue*(
      self: TIntFormatter,
      objectValue: ptr IDPtr,
      stringValue {.kw("forString").}: NSString,
      errorDescription {.kw("errorDescription").}: ptr IDPtr,
  ): bool =
    parseCallCount.inc
    if objectValue != nil:
      objectValue[] = nil
    if errorDescription != nil:
      errorDescription[] = nil
    if stringValue.isNil:
      return false
    try:
      let parsed = parseInt($stringValue)
      if objectValue != nil:
        var boxed = boxNSObject(parsed)
        objectValue[] = boxed.value
        boxed.value = nil
      true
    except ValueError:
      false

  method stringForObjectValue*(self: TIntFormatter, objectValue: NSObject): NSString =
    formatCallCount.inc
    @ns("fmt:" & $unboxNSObject[int](objectValue))

  method editingStringForObjectValue*(
      self: TIntFormatter, objectValue: NSObject
  ): NSString =
    @ns("edit:" & $self.stringForObjectValue(objectValue))

  method attributedStringForObjectValue*(
      self: TIntFormatter,
      objectValue: NSObject,
      attributes {.kw("withDefaultAttributes").}: NSDictionary[NSObject, NSObject],
  ): NSAttributedString =
    var allocated = NSAttributedString.alloc()
    let text = self.stringForObjectValue(objectValue)
    result = allocated.initWithString(text, attributes)
    allocated.value = nil

suite "appkit nsattributedstring and nsformatter":
  test "NSAttributedString preserves string attributes and word operations":
    check($NSFontAttributeName == "NSFontAttributeName")
    check($NSAttachmentAttributeName == "NSAttachmentAttributeName")

    var attributes = nsDictionary[NSObject, NSObject]()
    let foregroundKey = NSObject(NSForegroundColorAttributeName)
    attributes[foregroundKey] = boxNSObject(99)

    var allocated = NSAttributedString.alloc()
    var text = allocated.initWithString(@ns"alpha beta", attributes)
    allocated.value = nil

    check(text.length() == 10)
    check($text.string() == "alpha beta")

    var effective = NSMakeRange(0, 0)
    check(
      unboxNSObject[int](
        text.attribute(NSForegroundColorAttributeName, 3.NSUInteger, addr effective)
      ) == 99
    )
    check(effective.location == 0)
    check(effective.length == 10)

    var longest = NSMakeRange(0, 0)
    discard text.attributesAtIndex(
      3.NSUInteger, addr longest, NSMakeRange(1.NSUInteger, 4.NSUInteger)
    )
    check(longest.location == 1)
    check(longest.length == 4)

    let word = text.doubleClickAtIndex(1'u)
    check(word.location == 0)
    check(word.length == 5)

    let space = text.doubleClickAtIndex(5'u)
    check(space.location == 5)
    check(space.length == 1)

    check(text.nextWordFromIndex(0'u, true) == 5'u)
    check(text.nextWordFromIndex(5'u, true) == 10'u)
    check(text.nextWordFromIndex(10'u, false) == 6'u)

    let slice =
      text.attributedSubstringFromRange(NSMakeRange(6.NSUInteger, 4.NSUInteger))
    check($slice.string() == "beta")
    check(
      unboxNSObject[int](
        slice.attribute(
          NSForegroundColorAttributeName, 0.NSUInteger, cast[ptr NSRange](nil)
        )
      ) == 99
    )

    var copiedAlloc = NSAttributedString.alloc()
    let copied = copiedAlloc.initWithAttributedString(text)
    copiedAlloc.value = nil
    check(text.isEqualToAttributedString(copied))

  test "NSAttributedString attachment convenience constructor stores attachment attribute":
    let attachment = boxNSObject(123)
    let text = NSAttributedString.attributedStringWithAttachment(attachment)
    check(text.length() > 0)
    check(
      unboxNSObject[int](
        text.attribute(NSAttachmentAttributeName, 0.NSUInteger, cast[ptr NSRange](nil))
      ) == 123
    )
    check(text.containsAttachments())

  test "NSFormatter subclass overrides parse and format selectors":
    parseCallCount = 0
    formatCallCount = 0

    let formatter = TIntFormatter.new()

    var parsedObject: IDPtr = nil
    var parseError: IDPtr = nil
    check(formatter.getObjectValue(addr parsedObject, @ns"27", addr parseError))
    check(parseCallCount == 1)
    check(unboxNSObject[int](NSObject(value: parsedObject)) == 27)

    check(
      not formatter.getObjectValue(
        addr parsedObject, @ns"not-a-number", addr parseError
      )
    )
    check(parseCallCount == 2)

    check($formatter.stringForObjectValue(boxNSObject(7)) == "fmt:7")
    check($formatter.editingStringForObjectValue(boxNSObject(7)) == "edit:fmt:7")
    check(formatCallCount >= 2)

    let styled = formatter.attributedStringForObjectValue(
      boxNSObject(5), NSDictionary[NSObject, NSObject](value: nil)
    )
    check($styled.string() == "fmt:5")

  test "NSNumberFormatter formats and parses numeric values":
    let formatter = NSNumberFormatter.new()
    formatter.setFormat(@ns"##.000")
    check($formatter.stringForObjectValue(boxNSObject(12.5)) == "12.500")
    check($formatter.stringForObjectValue(boxNSObject(12.0)) == "12.000")

    formatter.setFormat(@ns"#####")
    check($formatter.stringForObjectValue(boxNSObject(12.5)) == "12.5")
    check($formatter.stringForObjectValue(boxNSObject(12.0)) == "12")

    var parsedValue: IDPtr = nil
    var parseError: IDPtr = nil
    check(formatter.getObjectValue(addr parsedValue, @ns"7.25", addr parseError))
    check(abs(unboxNSObject[float](NSObject(value: parsedValue)) - 7.25) < 1e-6)
    check(
      not formatter.getObjectValue(addr parsedValue, @ns"not-a-number", addr parseError)
    )
