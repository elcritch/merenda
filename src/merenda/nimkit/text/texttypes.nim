import ../foundation/types

type
  TextIndex* = distinct Natural

  TextRange* = object
    location*: Natural
    length*: Natural

  TextSelection* = object
    anchor*: Natural
    cursor*: Natural

  TextAffinity* = enum
    taUpstream
    taDownstream

  TextEditReason* = enum
    terCommit
    terCancel
    terFocusChange
    terProgrammatic

  TextEditMovement* = enum
    temNone
    temTab
    temBacktab
    temReturn

  TextWritingDirection* = enum
    twdNatural
    twdLeftToRight
    twdRightToLeft

  TextLineBreakMode* = enum
    tlbmWordWrapping
    tlbmCharWrapping
    tlbmClipping
    tlbmTruncatingHead
    tlbmTruncatingTail
    tlbmTruncatingMiddle

  TextLineDecorationStyle* = enum
    tldsNone
    tldsSingle
    tldsThick
    tldsDouble

  TextLigatureLevel* = enum
    tllDefault
    tllNone
    tllStandard
    tllAll

  TextTransferFormat* = enum
    ttfPlainText
    ttfAttributedText
    ttfRTF
    ttfRTFD
    ttfHTML
    ttfURL
    ttfFilePromise

  TextTransferContract* = object
    format*: TextTransferFormat
    name*: string
    mimeType*: string
    fileExtensions*: seq[string]
    preservesAttributes*: bool
    allowsAttachments*: bool

  TextMetadataItem* = object
    key*: string
    value*: string

  TextTabStop* = object
    location*: float32
    alignment*: TextAlignment

  TextParagraphStyle* = object
    alignment*: TextAlignment
    firstLineHeadIndent*: float32
    headIndent*: float32
    tailIndent*: float32
    lineSpacing*: float32
    paragraphSpacingBefore*: float32
    paragraphSpacingAfter*: float32
    minimumLineHeight*: float32
    maximumLineHeight*: float32
    defaultTabInterval*: float32
    tabStops*: seq[TextTabStop]
    lineBreakMode*: TextLineBreakMode
    baseWritingDirection*: TextWritingDirection

  TextShadow* = object
    color*: Color
    offset*: Size
    blurRadius*: float32

  TextAttachment* = object
    identifier*: string
    contentType*: string
    fileName*: string
    fileUrl*: string
    size*: Size
    metadata*: seq[TextMetadataItem]

  TextAttributes* = object
    foregroundColor*: Color
    fontSize*: float32
    paragraphStyle*: TextParagraphStyle
    baselineOffset*: float32
    kerning*: float32
    ligatureLevel*: TextLigatureLevel
    expansion*: float32
    backgroundColor*: Color
    shadow*: TextShadow
    link*: string
    underlineStyle*: TextLineDecorationStyle
    strikethroughStyle*: TextLineDecorationStyle
    attachment*: TextAttachment
    underline*: bool
    strikethrough*: bool

  TextAttributeRun* = object
    range*: TextRange
    attributes*: TextAttributes

func initTextIndex*(value: int): TextIndex =
  TextIndex(max(value, 0).Natural)

func toInt*(index: TextIndex): int =
  system.int(Natural(index))

func initTextRange*(location, length: int): TextRange =
  TextRange(location: max(location, 0).Natural, length: max(length, 0).Natural)

func maxIndex*(range: TextRange): int =
  int(range.location) + int(range.length)

func isEmpty*(range: TextRange): bool =
  range.length == 0

func initTextSelection*(anchor, cursor: int): TextSelection =
  TextSelection(anchor: max(anchor, 0).Natural, cursor: max(cursor, 0).Natural)

func textRange*(selection: TextSelection): TextRange =
  let
    start = min(int(selection.anchor), int(selection.cursor))
    stop = max(int(selection.anchor), int(selection.cursor))
  initTextRange(start, stop - start)

proc initTextTransferContract*(
    format: TextTransferFormat,
    name: string,
    mimeType = "",
    fileExtensions: openArray[string] = [],
    preservesAttributes = false,
    allowsAttachments = false,
): TextTransferContract =
  TextTransferContract(
    format: format,
    name: name,
    mimeType: mimeType,
    fileExtensions: @fileExtensions,
    preservesAttributes: preservesAttributes,
    allowsAttachments: allowsAttachments,
  )

proc textTransferContract*(format: TextTransferFormat): TextTransferContract =
  case format
  of ttfPlainText:
    initTextTransferContract(ttfPlainText, "plain text", "text/plain", ["txt"])
  of ttfAttributedText:
    initTextTransferContract(
      ttfAttributedText, "attributed text", preservesAttributes = true
    )
  of ttfRTF:
    initTextTransferContract(
      ttfRTF, "rich text", "application/rtf", ["rtf"], preservesAttributes = true
    )
  of ttfRTFD:
    initTextTransferContract(
      ttfRTFD,
      "rich text package",
      "application/x-rtfd",
      ["rtfd"],
      preservesAttributes = true,
      allowsAttachments = true,
    )
  of ttfHTML:
    initTextTransferContract(
      ttfHTML, "HTML fragment", "text/html", ["html", "htm"], preservesAttributes = true
    )
  of ttfURL:
    initTextTransferContract(ttfURL, "URL", "text/uri-list", ["url"])
  of ttfFilePromise:
    initTextTransferContract(ttfFilePromise, "file promise", allowsAttachments = true)

proc textTransferContracts*(): seq[TextTransferContract] =
  for format in TextTransferFormat:
    result.add textTransferContract(format)

func initTextMetadataItem*(key, value: string): TextMetadataItem =
  TextMetadataItem(key: key, value: value)

func initTextTabStop*(location: float32, alignment = taLeft): TextTabStop =
  TextTabStop(location: max(location, 0.0'f32), alignment: alignment)

proc initTextParagraphStyle*(
    alignment = taLeft,
    firstLineHeadIndent = 0.0'f32,
    headIndent = 0.0'f32,
    tailIndent = 0.0'f32,
    lineSpacing = 0.0'f32,
    paragraphSpacingBefore = 0.0'f32,
    paragraphSpacingAfter = 0.0'f32,
    minimumLineHeight = 0.0'f32,
    maximumLineHeight = 0.0'f32,
    defaultTabInterval = 0.0'f32,
    tabStops: openArray[TextTabStop] = [],
    lineBreakMode = tlbmWordWrapping,
    baseWritingDirection = twdNatural,
): TextParagraphStyle =
  TextParagraphStyle(
    alignment: alignment,
    firstLineHeadIndent: firstLineHeadIndent,
    headIndent: headIndent,
    tailIndent: tailIndent,
    lineSpacing: lineSpacing,
    paragraphSpacingBefore: paragraphSpacingBefore,
    paragraphSpacingAfter: paragraphSpacingAfter,
    minimumLineHeight: max(minimumLineHeight, 0.0'f32),
    maximumLineHeight: max(maximumLineHeight, 0.0'f32),
    defaultTabInterval: max(defaultTabInterval, 0.0'f32),
    tabStops: @tabStops,
    lineBreakMode: lineBreakMode,
    baseWritingDirection: baseWritingDirection,
  )

func initTextShadow*(
    color = color(0.0, 0.0, 0.0, 0.0), offset = initSize(0.0, 0.0), blurRadius = 0.0'f32
): TextShadow =
  TextShadow(color: color, offset: offset, blurRadius: max(blurRadius, 0.0'f32))

proc initTextAttachment*(
    identifier = "",
    contentType = "",
    fileName = "",
    fileUrl = "",
    size = initSize(0.0, 0.0),
    metadata: openArray[TextMetadataItem] = [],
): TextAttachment =
  TextAttachment(
    identifier: identifier,
    contentType: contentType,
    fileName: fileName,
    fileUrl: fileUrl,
    size: size,
    metadata: @metadata,
  )

proc defaultTextAttributes*(
    color = color(0.08, 0.09, 0.11, 1.0), fontSize = AutoMetric
): TextAttributes =
  let resolvedFontSize =
    if fontSize.isAutoMetric:
      defaultFontSize()
    else:
      fontSize
  TextAttributes(
    foregroundColor: color,
    fontSize: max(resolvedFontSize, 1.0'f32),
    paragraphStyle: initTextParagraphStyle(),
    ligatureLevel: tllDefault,
  )

func hasUnderline*(attributes: TextAttributes): bool =
  attributes.underline or attributes.underlineStyle != tldsNone

func hasStrikethrough*(attributes: TextAttributes): bool =
  attributes.strikethrough or attributes.strikethroughStyle != tldsNone

func hasBackgroundColor*(attributes: TextAttributes): bool =
  attributes.backgroundColor.a > 0.0

func hasShadow*(attributes: TextAttributes): bool =
  attributes.shadow.color.a > 0.0 or attributes.shadow.blurRadius > 0.0 or
    attributes.shadow.offset.width != 0.0 or attributes.shadow.offset.height != 0.0

func hasLink*(attributes: TextAttributes): bool =
  attributes.link.len > 0

func hasAttachment*(attributes: TextAttributes): bool =
  attributes.attachment.identifier.len > 0 or attributes.attachment.contentType.len > 0 or
    attributes.attachment.fileName.len > 0 or attributes.attachment.fileUrl.len > 0
