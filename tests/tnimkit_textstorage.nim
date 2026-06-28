import std/unittest

import merenda/nimkit

suite "nimkit text storage":
  test "text storage replaces text and preserves surrounding attribute runs":
    let
      storage = newTextStorage("abcdef")
      red = defaultTextAttributes(initColor(1.0, 0.0, 0.0))
      blue = defaultTextAttributes(initColor(0.0, 0.0, 1.0))

    storage.setAttributes(initTextRange(0, 3), red)
    storage.replace(initTextRange(2, 2), "XYZ", blue)

    check storage.stringValue == "abXYZef"
    check storage.len == 7
    check storage.substring(initTextRange(2, 3)) == "XYZ"
    check storage.attributesAt(0) == red
    check storage.attributesAt(2) == blue
    check storage.attributesAt(5) == defaultTextAttributes()

  test "text storage uses rune ranges for unicode text":
    let storage = newTextStorage("ałpha")

    storage.replace(initTextRange(1, 1), "L")

    check storage.stringValue == "aLpha"
    check storage.len == 5
    check storage.substring(initTextRange(1, 2)) == "Lp"

  test "adjacent equal attribute runs are normalized":
    let
      storage = newTextStorage("abcd")
      accent = defaultTextAttributes(initColor(0.2, 0.4, 0.8))

    storage.setAttributes(initTextRange(0, 2), accent)
    storage.setAttributes(initTextRange(2, 2), accent)

    var count = 0
    for run in storage.runs:
      inc count
      check run.range == initTextRange(0, 4)
      check run.attributes == accent
    check count == 1

  test "rich text attributes preserve TextKit-style value fields":
    var attributes = defaultTextAttributes(initColor(0.1, 0.2, 0.3), 14.0)
    attributes.paragraphStyle = initTextParagraphStyle(
      alignment = taRight,
      firstLineHeadIndent = 8.0,
      headIndent = 4.0,
      tailIndent = -12.0,
      lineSpacing = 2.0,
      defaultTabInterval = 28.0,
      tabStops = [initTextTabStop(24.0, taCenter)],
      lineBreakMode = tlbmTruncatingTail,
      baseWritingDirection = twdRightToLeft,
    )
    attributes.baselineOffset = 1.5
    attributes.kerning = 0.75
    attributes.ligatureLevel = tllAll
    attributes.expansion = 0.2
    attributes.backgroundColor = initColor(1.0, 0.9, 0.2, 1.0)
    attributes.shadow =
      initTextShadow(initColor(0.0, 0.0, 0.0, 0.35), initSize(1.0, 2.0), 3.0)
    attributes.link = "https://example.com"
    attributes.underlineStyle = tldsSingle
    attributes.strikethroughStyle = tldsDouble
    attributes.attachment = initTextAttachment(
      identifier = "attachment-1",
      contentType = "image/png",
      fileName = "image.png",
      size = initSize(32.0, 24.0),
      metadata = [initTextMetadataItem("role", "preview")],
    )

    let storage = newAttributedString("rich", attributes)

    check storage.attributesAtIndex(0) == attributes
    check storage.attributeRuns.len == 1
    check storage.attributeRuns[0].range == initTextRange(0, 4)
    check attributes.hasBackgroundColor
    check attributes.hasShadow
    check attributes.hasLink
    check attributes.hasAttachment
    check attributes.hasUnderline
    check attributes.hasStrikethrough

  test "mutable attributed string APIs use rune-indexed ranges":
    let
      storage = newAttributedString("ałpha")
      accent = defaultTextAttributes(initColor(0.8, 0.1, 0.2), 16.0)
      blue = defaultTextAttributes(initColor(0.0, 0.2, 1.0), 12.0)

    storage.replaceCharacters(initTextRange(1, 1), "L", accent)
    storage.insertAttributedString(2, newAttributedString("ZZ", blue))

    check storage.stringValue == "aLZZpha"
    check storage.len == 7
    check storage.attributesAtIndex(1) == accent
    check storage.attributesAtIndex(2) == blue

    let sub = storage.attributedSubstring(initTextRange(1, 3))
    check sub.stringValue == "LZZ"
    check sub.attributesAtIndex(0) == accent
    check sub.attributesAtIndex(1) == blue

    let copy = storage.mutableCopy()
    copy.removeAttributes(initTextRange(0, copy.len))
    check copy.attributesAtIndex(1) == defaultTextAttributes()
    check storage.attributesAtIndex(1) == accent
