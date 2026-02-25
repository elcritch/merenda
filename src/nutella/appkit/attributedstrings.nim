import std/[hashes, strutils, unicode]

import ./runtime

type NSAttributeRun = object
  location: int
  length: int
  attributes: NSDictionary[NSObject, NSObject]

const NSAttachmentCharacter* = 0xFFFC'u16

var NSFontAttributeName* {.threadvar.}: NSString
var NSParagraphStyleAttributeName* {.threadvar.}: NSString
var NSForegroundColorAttributeName* {.threadvar.}: NSString
var NSBackgroundColorAttributeName* {.threadvar.}: NSString
var NSUnderlineStyleAttributeName* {.threadvar.}: NSString
var NSUnderlineColorAttributeName* {.threadvar.}: NSString
var NSAttachmentAttributeName* {.threadvar.}: NSString
var NSKernAttributeName* {.threadvar.}: NSString
var NSLigatureAttributeName* {.threadvar.}: NSString
var NSStrikethroughStyleAttributeName* {.threadvar.}: NSString
var NSStrikethroughColorAttributeName* {.threadvar.}: NSString
var NSObliquenessAttributeName* {.threadvar.}: NSString
var NSStrokeWidthAttributeName* {.threadvar.}: NSString
var NSStrokeColorAttributeName* {.threadvar.}: NSString
var NSBaselineOffsetAttributeName* {.threadvar.}: NSString
var NSSuperscriptAttributeName* {.threadvar.}: NSString
var NSLinkAttributeName* {.threadvar.}: NSString
var NSShadowAttributeName* {.threadvar.}: NSString
var NSExpansionAttributeName* {.threadvar.}: NSString
var NSCursorAttributeName* {.threadvar.}: NSString
var NSToolTipAttributeName* {.threadvar.}: NSString
var NSBackgroundColorDocumentAttribute* {.threadvar.}: NSString
var NSSpellingStateAttributeName* {.threadvar.}: NSString

var attributedStringConstantsReady {.threadvar.}: bool

proc ensureAttributedStringConstants() =
  if attributedStringConstantsReady:
    return
  NSFontAttributeName = @ns"NSFontAttributeName"
  NSParagraphStyleAttributeName = @ns"NSParagraphStyleAttributeName"
  NSForegroundColorAttributeName = @ns"NSForegroundColorAttributeName"
  NSBackgroundColorAttributeName = @ns"NSBackgroundColorAttributeName"
  NSUnderlineStyleAttributeName = @ns"NSUnderlineStyleAttributeName"
  NSUnderlineColorAttributeName = @ns"NSUnderlineColorAttributeName"
  NSAttachmentAttributeName = @ns"NSAttachmentAttributeName"
  NSKernAttributeName = @ns"NSKernAttributeName"
  NSLigatureAttributeName = @ns"NSLigatureAttributeName"
  NSStrikethroughStyleAttributeName = @ns"NSStrikethroughStyleAttributeName"
  NSStrikethroughColorAttributeName = @ns"NSStrikethroughColorAttributeName"
  NSObliquenessAttributeName = @ns"NSObliquenessAttributeName"
  NSStrokeWidthAttributeName = @ns"NSStrokeWidthAttributeName"
  NSStrokeColorAttributeName = @ns"NSStrokeColorAttributeName"
  NSBaselineOffsetAttributeName = @ns"NSBaselineOffsetAttributeName"
  NSSuperscriptAttributeName = @ns"NSSuperscriptAttributeName"
  NSLinkAttributeName = @ns"NSLinkAttributeName"
  NSShadowAttributeName = @ns"NSShadowAttributeName"
  NSExpansionAttributeName = @ns"NSExpansionAttributeName"
  NSCursorAttributeName = @ns"NSCursorAttributeName"
  NSToolTipAttributeName = @ns"NSToolTipAttributeName"
  NSBackgroundColorDocumentAttribute = @ns"NSBackgroundColorDocumentAttribute"
  NSSpellingStateAttributeName = @ns"NSSpellingStateAttributeName"
  attributedStringConstantsReady = true

proc idIsEqual(lhs, rhs: IDPtr): bool {.inline.} =
  if lhs == rhs:
    return true
  if lhs.isNil or rhs.isNil:
    return false
  cast[proc(self: IDPtr, op: SEL, other: IDPtr): bool {.cdecl, varargs.}](objc_msgSend)(
    lhs, getSelector("isEqual:"), rhs
  )

proc emptyAttributesDict(): NSDictionary[NSObject, NSObject] =
  nsDictionary[NSObject, NSObject]()

proc normalizeAttributesId(
    attributes: NSDictionary[NSObject, NSObject]
): NSDictionary[NSObject, NSObject] =
  if not attributes.isNil:
    return ownFromId[NSDictionary[NSObject, NSObject]](attributes.value)
  emptyAttributesDict()

proc compressRuns(runs: openArray[NSAttributeRun], totalLen: int): seq[NSAttributeRun] =
  result = @[]
  if totalLen <= 0:
    return
  for raw in runs:
    if raw.length <= 0:
      continue
    var start = max(raw.location, 0)
    var stop = min(start + raw.length, totalLen)
    if stop <= start:
      continue
    let attrs = normalizeAttributesId(raw.attributes)
    if result.len > 0:
      let prev = result[^1]
      if prev.location + prev.length == start and
          idIsEqual(prev.attributes.value, attrs.value):
        result[^1].length = (stop - prev.location)
        continue
    result.add(NSAttributeRun(location: start, length: stop - start, attributes: attrs))
  if result.len == 0:
    result.add(
      NSAttributeRun(
        location: 0,
        length: totalLen,
        attributes: normalizeAttributesId(NSDictionary[NSObject, NSObject](value: nil)),
      )
    )

proc findRunIndex(runs: openArray[NSAttributeRun], location: int): int =
  for i, run in runs:
    let start = run.location
    let stop = start + run.length
    if location >= start and location < stop:
      return i
  -1

proc asInt(value: NSUInteger): int {.inline.} =
  if value > high(int).NSUInteger:
    return high(int)
  value.int

proc attachmentMarkerString(): NSString =
  ns($Rune(NSAttachmentCharacter.int))

proc isAlnumAscii(ch: char): bool {.inline.} =
  (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z')

objcImpl:
  type NSAttributedString* = object of NSObject
    xString {.set: setStorageString, get: storageString.}: NSString
    xRuns {.set: setStorageRuns, get: storageRuns.}: seq[NSAttributeRun]

  method initWithString*(
      self: var NSAttributedString,
      string: NSString,
      attributes {.kw("attributes").}: NSDictionary[NSObject, NSObject],
  ): NSAttributedString =
    ensureAttributedStringConstants()
    result = callSuperAs[NSAttributedString](self, getSelector("init"))
    if result.isNil:
      return
    let copiedString = ns(
      if string.isNil:
        ""
      else:
        $string
    )
    result.xString = copiedString
    let attrs = normalizeAttributesId(attributes)
    if copiedString.len > 0:
      result.xRuns =
        @[NSAttributeRun(location: 0, length: copiedString.len, attributes: attrs)]
    else:
      result.xRuns = @[]

  method initWithString*(
      self: var NSAttributedString, string: NSString
  ): NSAttributedString =
    result = self.initWithString(string, NSDictionary[NSObject, NSObject](value: nil))

  method init*(self: var NSAttributedString): NSAttributedString =
    ensureAttributedStringConstants()
    result = self.initWithString(@ns"")

  method initWithAttributedString*(
      self: var NSAttributedString, other: NSAttributedString
  ): NSAttributedString =
    if other.isNil:
      return self.initWithString(@ns"")
    let sourceString =
      if other.xString().isNil:
        @ns""
      else:
        ns($other.xString())
    result = self.initWithString(sourceString)
    if result.isNil:
      return
    let totalLen = sourceString.len
    if totalLen <= 0:
      result.xRuns = @[]
      return
    var runs: seq[NSAttributeRun] = @[]
    for run in other.xRuns():
      runs.add(
        NSAttributeRun(
          location: run.location,
          length: run.length,
          attributes: normalizeAttributesId(run.attributes),
        )
      )
    result.xRuns = compressRuns(runs, totalLen)

  method dealloc*(self: NSAttributedString) =
    destroyIvarFields(self)
    discard callSuperAs[IDPtr](self, getSelector("dealloc"))

  method copyWithZone*(self: NSAttributedString, zone: pointer): NSAttributedString =
    discard zone
    retain(self)

  method mutableCopyWithZone*(
      self: NSAttributedString, zone: pointer
  ): NSAttributedString =
    discard zone
    var allocated = NSAttributedString.alloc()
    result = allocated.initWithAttributedString(self)
    allocated.value = nil

  method isEqualToAttributedString*(
      self: NSAttributedString, other: NSAttributedString
  ): bool =
    if other.isNil:
      return false
    if self.length() != other.length():
      return false
    if self.string() != other.string():
      return false
    let totalLen = self.length().asInt
    var idx = 0
    while idx < totalLen:
      var thisRange = NSMakeRange(0, 0)
      var otherRange = NSMakeRange(0, 0)
      let thisAttrs = self.attributesAtIndex(idx.NSUInteger, addr thisRange)
      let otherAttrs = other.attributesAtIndex(idx.NSUInteger, addr otherRange)
      if not idIsEqual(thisAttrs.value, otherAttrs.value):
        return false
      idx = min(asInt(NSMaxRange(thisRange)), asInt(NSMaxRange(otherRange)))
    true

  method isEqual*(self: NSAttributedString, other: NSObject): bool =
    if self.value == other.value:
      return true
    if other.isNil or not other.isKindOfClass(NSAttributedString):
      return false
    let otherAttributed = ownFromId[NSAttributedString](other.value)
    self.isEqualToAttributedString(otherAttributed)

  method hash*(self: NSAttributedString): NSUInteger =
    hash(self.string()).NSUInteger

  method length*(self: NSAttributedString): NSUInteger =
    if self.xString.isNil:
      return 0
    self.xString.len.NSUInteger

  method string*(self: NSAttributedString): NSString =
    if self.xString.isNil:
      return @ns""
    ownFromId[NSString](self.xString.value)

  method attributesAtIndex*(
      self: NSAttributedString,
      location: NSUInteger,
      effectiveRange {.kw("effectiveRange").}: ptr NSRange,
  ): NSDictionary[NSObject, NSObject] =
    let totalLen = self.length().asInt
    let idx = location.asInt
    if idx < 0 or idx >= totalLen:
      raise newException(IndexDefect, "index out of bounds in NSAttributedString")

    let runs = self.xRuns()
    let runIndex = findRunIndex(runs, idx)
    if runIndex < 0:
      if effectiveRange != nil:
        effectiveRange[] = NSMakeRange(0, totalLen.NSUInteger)
      return emptyAttributesDict()

    let run = runs[runIndex]
    if effectiveRange != nil:
      effectiveRange[] = NSMakeRange(run.location.NSUInteger, run.length.NSUInteger)

    if run.attributes.isNil:
      return emptyAttributesDict()
    ownFromId[NSDictionary[NSObject, NSObject]](run.attributes.value)

  method attributesAtIndex*(
      self: NSAttributedString,
      location: NSUInteger,
      longestEffectiveRange {.kw("longestEffectiveRange").}: ptr NSRange,
      inRange {.kw("inRange").}: NSRange,
  ): NSDictionary[NSObject, NSObject] =
    result = self.attributesAtIndex(location, longestEffectiveRange)
    if longestEffectiveRange == nil:
      return
    let lower = asInt(inRange.location)
    let upper = asInt(NSMaxRange(inRange))
    var start = asInt(longestEffectiveRange[].location)
    var stop = asInt(NSMaxRange(longestEffectiveRange[]))
    start = max(start, lower)
    stop = min(stop, upper)
    if stop < start:
      stop = start
    longestEffectiveRange[] = NSMakeRange(start.NSUInteger, (stop - start).NSUInteger)

  method attribute*(
      self: NSAttributedString,
      name: NSString,
      location {.kw("atIndex").}: NSUInteger,
      effectiveRange {.kw("effectiveRange").}: ptr NSRange,
  ): NSObject =
    if name.isNil:
      return NSObject(value: nil)
    let attrs = self.attributesAtIndex(location, effectiveRange)
    let key = ownFromId[NSObject](name.value)
    if attrs.hasKey(key):
      let value = attrs[key]
      return ownFromId[NSObject](value.value)
    NSObject(value: nil)

  method attribute*(
      self: NSAttributedString,
      name: NSString,
      location {.kw("atIndex").}: NSUInteger,
      longestEffectiveRange {.kw("longestEffectiveRange").}: ptr NSRange,
      inRange {.kw("inRange").}: NSRange,
  ): NSObject =
    if name.isNil:
      return NSObject(value: nil)
    let attrs = self.attributesAtIndex(location, longestEffectiveRange, inRange)
    let key = ownFromId[NSObject](name.value)
    if attrs.hasKey(key):
      let value = attrs[key]
      return ownFromId[NSObject](value.value)
    NSObject(value: nil)

  method attributedSubstringFromRange*(
      self: NSAttributedString, range: NSRange
  ): NSAttributedString =
    let totalLen = self.length().asInt
    let start = min(max(asInt(range.location), 0), totalLen)
    let stop = min(max(asInt(NSMaxRange(range)), start), totalLen)
    let text = $self.string()
    let sliced =
      if start >= stop:
        ""
      else:
        text[start ..< stop]

    var allocated = NSAttributedString.alloc()
    result = allocated.initWithString(ns(sliced))
    allocated.value = nil
    if result.isNil or stop <= start:
      return

    var runs: seq[NSAttributeRun] = @[]
    for run in self.xRuns():
      let runStart = run.location
      let runStop = run.location + run.length
      let overlapStart = max(runStart, start)
      let overlapStop = min(runStop, stop)
      if overlapStop <= overlapStart:
        continue
      runs.add(
        NSAttributeRun(
          location: overlapStart - start,
          length: overlapStop - overlapStart,
          attributes: normalizeAttributesId(run.attributes),
        )
      )
    result.xRuns = compressRuns(runs, stop - start)

  method attributedStringWithAttachment*(
      self: typedesc[NSAttributedString], attachment: NSObject
  ): NSAttributedString =
    ensureAttributedStringConstants()
    var attrs = nsDictionary[NSObject, NSObject]()
    let key = ownFromId[NSObject](NSAttachmentAttributeName.value)
    attrs[key] = attachment
    var allocated = self.alloc()
    result = allocated.initWithString(attachmentMarkerString(), attrs)
    allocated.value = nil

  method initWithData*(
      self: var NSAttributedString,
      data: NSObject,
      options {.kw("options").}: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
      error {.kw("error").}: ptr IDPtr,
  ): NSAttributedString =
    discard data
    discard options
    if documentAttributes != nil:
      documentAttributes[] = nil
    if error != nil:
      error[] = nil
    self.initWithString(@ns"")

  method initWithDocFormat*(
      self: var NSAttributedString,
      docFormat: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    discard docFormat
    if documentAttributes != nil:
      documentAttributes[] = nil
    self.initWithString(@ns"")

  method initWithHTML*(
      self: var NSAttributedString,
      html: NSObject,
      baseURL {.kw("baseURL").}: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    discard html
    discard baseURL
    if documentAttributes != nil:
      documentAttributes[] = nil
    self.initWithString(@ns"")

  method initWithHTML*(
      self: var NSAttributedString,
      html: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    discard html
    if documentAttributes != nil:
      documentAttributes[] = nil
    self.initWithString(@ns"")

  method initWithHTML*(
      self: var NSAttributedString,
      html: NSObject,
      options {.kw("options").}: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    discard html
    discard options
    if documentAttributes != nil:
      documentAttributes[] = nil
    self.initWithString(@ns"")

  method initWithPath*(
      self: var NSAttributedString,
      path: NSString,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    if documentAttributes != nil:
      documentAttributes[] = nil
    if path.isNil:
      return NSAttributedString(value: nil)
    try:
      self.initWithString(ns(readFile($path)))
    except IOError:
      NSAttributedString(value: nil)

  method initWithRTF*(
      self: var NSAttributedString,
      rtf: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    if documentAttributes != nil:
      documentAttributes[] = nil
    if rtf.isNil:
      return NSAttributedString(value: nil)
    if rtf.isKindOfClass(NSString):
      let text = ownFromId[NSString](rtf.value)
      return self.initWithString(text)
    self.initWithString(@ns"")

  method initWithRTFD*(
      self: var NSAttributedString,
      rtfd: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    discard rtfd
    if documentAttributes != nil:
      documentAttributes[] = nil
    self.initWithString(@ns"")

  method initWithRTFDFileWrapper*(
      self: var NSAttributedString,
      wrapper: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    discard wrapper
    if documentAttributes != nil:
      documentAttributes[] = nil
    self.initWithString(@ns"")

  method initWithURL*(
      self: var NSAttributedString,
      url: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
  ): NSAttributedString =
    discard url
    if documentAttributes != nil:
      documentAttributes[] = nil
    self.initWithString(@ns"")

  method initWithURL*(
      self: var NSAttributedString,
      url: NSObject,
      options {.kw("options").}: NSObject,
      documentAttributes {.kw("documentAttributes").}: ptr IDPtr,
      error {.kw("error").}: ptr IDPtr,
  ): NSAttributedString =
    discard url
    discard options
    if documentAttributes != nil:
      documentAttributes[] = nil
    if error != nil:
      error[] = nil
    self.initWithString(@ns"")

  method containsAttachments*(self: NSAttributedString): bool =
    let marker = NSAttachmentAttributeName
    if marker.isNil:
      return false
    let totalLen = self.length().asInt
    for i in 0 ..< totalLen:
      if not self.attribute(marker, i.NSUInteger, nil).isNil:
        return true
    false

  method fontAttributesInRange*(
      self: NSAttributedString, range: NSRange
  ): NSDictionary[NSObject, NSObject] =
    if self.length() == 0 or range.length == 0:
      return emptyAttributesDict()
    let idx = min(asInt(range.location), self.length().asInt - 1)
    var effective = NSMakeRange(0, 0)
    self.attributesAtIndex(idx.NSUInteger, addr effective)

  method rulerAttributesInRange*(
      self: NSAttributedString, range: NSRange
  ): NSDictionary[NSObject, NSObject] =
    self.fontAttributesInRange(range)

  method doubleClickAtIndex*(self: NSAttributedString, location: uint): NSRange =
    let text = $self.string()
    let length = text.len
    let idx = location.int
    if idx < 0 or idx >= length:
      return NSMakeRange(min(max(idx, 0), length).NSUInteger, 0)
    var start = idx
    var stop = idx
    let ch = text[idx]
    let expandWithWhitespace = ch.isSpaceAscii()
    let expandWithAlnum = isAlnumAscii(ch)
    if expandWithWhitespace or expandWithAlnum:
      while start > 0:
        let prev = text[start - 1]
        if expandWithWhitespace:
          if not prev.isSpaceAscii():
            break
        elif not isAlnumAscii(prev):
          break
        dec start
      while stop + 1 < length:
        let next = text[stop + 1]
        if expandWithWhitespace:
          if not next.isSpaceAscii():
            break
        elif not isAlnumAscii(next):
          break
        inc stop
      return NSMakeRange(start.NSUInteger, (stop - start + 1).NSUInteger)
    NSMakeRange(idx.NSUInteger, 1)

  method lineBreakBeforeIndex*(
      self: NSAttributedString, index: uint, withinRange {.kw("withinRange").}: NSRange
  ): uint =
    discard self
    discard index
    discard withinRange
    0'u

  method lineBreakByHyphenatingBeforeIndex*(
      self: NSAttributedString, index: uint, withinRange {.kw("withinRange").}: NSRange
  ): uint =
    discard self
    discard index
    discard withinRange
    0'u

  method nextWordFromIndex*(
      self: NSAttributedString, location: uint, forward {.kw("forward").}: bool
  ): uint =
    let text = $self.string()
    let length = text.len
    if length == 0:
      return 0'u
    var i = location.int
    if i <= 0 and not forward:
      return 0'u
    if i >= length:
      if forward:
        return length.uint
      i = length - 1

    if forward:
      var state = if isAlnumAscii(text[i]): 1 else: 0
      while i < length:
        let ch = text[i]
        case state
        of 0:
          if not isAlnumAscii(ch):
            state = 1
        of 1:
          if isAlnumAscii(ch):
            state = 2
        else:
          if not isAlnumAscii(ch):
            return i.uint
        inc i
      return length.uint

    dec i
    let anchor = min(max(location.int, 0), length - 1)
    var state = if isAlnumAscii(text[anchor]): 1 else: 0
    while i >= 0:
      let ch = text[i]
      case state
      of 0:
        if not isAlnumAscii(ch):
          state = 1
      of 1:
        if isAlnumAscii(ch):
          state = 2
      else:
        if not isAlnumAscii(ch):
          return (i + 1).uint
      dec i
    0'u

  method itemNumberInTextList*(
      self: NSAttributedString, list: NSObject, atIndex {.kw("atIndex").}: uint
  ): int =
    discard self
    discard list
    discard atIndex
    0

  method rangeOfTextBlock*(
      self: NSAttributedString, blockObj: NSObject, atIndex {.kw("atIndex").}: uint
  ): NSRange =
    discard self
    discard blockObj
    discard atIndex
    NSMakeRange(0, 0)

  method rangeOfTextList*(
      self: NSAttributedString, list: NSObject, atIndex {.kw("atIndex").}: uint
  ): NSRange =
    discard self
    discard list
    discard atIndex
    NSMakeRange(0, 0)

  method rangeOfTextTable*(
      self: NSAttributedString, table: NSObject, atIndex {.kw("atIndex").}: uint
  ): NSRange =
    discard self
    discard table
    discard atIndex
    NSMakeRange(0, 0)

  method RTFDFileWrapperFromRange*(
      self: NSAttributedString,
      range: NSRange,
      documentAttributes {.kw("documentAttributes").}: NSDictionary[NSObject, NSObject],
  ): NSObject =
    discard self
    discard range
    discard documentAttributes
    NSObject(value: nil)

  method RTFDFromRange*(
      self: NSAttributedString,
      range: NSRange,
      documentAttributes {.kw("documentAttributes").}: NSDictionary[NSObject, NSObject],
  ): NSObject =
    discard self
    discard range
    discard documentAttributes
    NSObject(value: nil)

  method RTFFromRange*(
      self: NSAttributedString,
      range: NSRange,
      documentAttributes {.kw("documentAttributes").}: NSDictionary[NSObject, NSObject],
  ): NSObject =
    discard self
    discard range
    discard documentAttributes
    NSObject(value: nil)

  method dataFromRange*(
      self: NSAttributedString,
      range: NSRange,
      documentAttributes {.kw("documentAttributes").}: NSDictionary[NSObject, NSObject],
      error {.kw("error").}: ptr IDPtr,
  ): NSObject =
    discard self
    discard range
    discard documentAttributes
    if error != nil:
      error[] = nil
    NSObject(value: nil)

  method docFormatFromRange*(
      self: NSAttributedString,
      range: NSRange,
      documentAttributes {.kw("documentAttributes").}: NSDictionary[NSObject, NSObject],
  ): NSObject =
    discard self
    discard range
    discard documentAttributes
    NSObject(value: nil)

  method fileWrapperFromRange*(
      self: NSAttributedString,
      range: NSRange,
      documentAttributes {.kw("documentAttributes").}: NSDictionary[NSObject, NSObject],
      error {.kw("error").}: ptr IDPtr,
  ): NSObject =
    discard self
    discard range
    discard documentAttributes
    if error != nil:
      error[] = nil
    NSObject(value: nil)

  method drawAtPoint*(self: NSAttributedString, point: NSPoint) =
    discard self
    discard point

  method drawInRect*(self: NSAttributedString, rect: NSRect) =
    discard self
    discard rect

  method drawWithRect*(
      self: NSAttributedString, rect: NSRect, options {.kw("options").}: int
  ) =
    discard self
    discard rect
    discard options

  method size*(self: NSAttributedString): NSSize =
    nsSize(self.length().float32, 1.0)

  method boundingRectWithSize*(
      self: NSAttributedString, size: NSSize, options {.kw("options").}: int
  ): NSRect =
    discard self
    discard options
    nsRect(0, 0, size.width, size.height)

  method textTypes*(self: typedesc[NSAttributedString]): NSArray[NSObject] =
    nsArray[NSObject]()

  method textUnfilteredTypes*(self: typedesc[NSAttributedString]): NSArray[NSObject] =
    nsArray[NSObject]()

  method textFileTypes*(self: typedesc[NSAttributedString]): NSArray[NSObject] =
    nsArray[NSObject]()

  method textPasteboardTypes*(self: typedesc[NSAttributedString]): NSArray[NSObject] =
    nsArray[NSObject]()

  method textUnfilteredFileTypes*(
      self: typedesc[NSAttributedString]
  ): NSArray[NSObject] =
    nsArray[NSObject]()

  method textUnfilteredPasteboardTypes*(
      self: typedesc[NSAttributedString]
  ): NSArray[NSObject] =
    nsArray[NSObject]()

proc NSFontAttributeInDictionary*(
    dictionary: NSDictionary[NSObject, NSObject]
): NSObject =
  ensureAttributedStringConstants()
  if dictionary.isNil or NSFontAttributeName.isNil:
    return NSObject(value: nil)
  let key = ownFromId[NSObject](NSFontAttributeName.value)
  if dictionary.hasKey(key):
    return dictionary[key]
  NSObject(value: nil)

proc NSForegroundColorAttributeInDictionary*(
    dictionary: NSDictionary[NSObject, NSObject]
): NSObject =
  ensureAttributedStringConstants()
  if dictionary.isNil or NSForegroundColorAttributeName.isNil:
    return NSObject(value: nil)
  let key = ownFromId[NSObject](NSForegroundColorAttributeName.value)
  if dictionary.hasKey(key):
    return dictionary[key]
  NSObject(value: nil)

proc NSParagraphStyleAttributeInDictionary*(
    dictionary: NSDictionary[NSObject, NSObject]
): NSObject =
  ensureAttributedStringConstants()
  if dictionary.isNil or NSParagraphStyleAttributeName.isNil:
    return NSObject(value: nil)
  let key = ownFromId[NSObject](NSParagraphStyleAttributeName.value)
  if dictionary.hasKey(key):
    return dictionary[key]
  NSObject(value: nil)

proc new*(t: typedesc[NSAttributedString]): NSAttributedString =
  var allocated = NSAttributedString.alloc()
  result = initOwned(move(allocated))

ensureAttributedStringConstants()
