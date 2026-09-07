## Value-only text layout data shared by the UI manager and background workers.

import std/[hashes, options]
import ../foundation/types
import ./texttypes
from ../themes/themecore import EdgeInsets

type
  GlyphIndex* = distinct Natural
  TextLineIndex* = distinct Natural
  TextContainerIndex* = distinct Natural

  GlyphRange* = object
    location*: GlyphIndex
    length*: Natural

  TextLineRange* = object
    location*: TextLineIndex
    length*: Natural

  GlyphProperty* = enum
    gpControl
    gpElastic
    gpAttachment
    gpNull

  GlyphProperties* = set[GlyphProperty]

  TextGlyphPropertyRun* = object
    range*: GlyphRange
    properties*: GlyphProperties

  TextLayoutInvalidationKind* = enum
    tlikCharacters
    tlikGlyphs
    tlikLayout
    tlikDisplay
    tlikContainer

  TextLayoutInvalidation* = object
    kind*: TextLayoutInvalidationKind
    textRange*: TextRange
    glyphRange*: GlyphRange
    containerIndex*: Option[TextContainerIndex]

  TextCaretPositionKind* = enum
    tcpLeading
    tcpInside
    tcpTrailing

  TextCaretPosition* = object
    textIndex*: TextIndex
    glyphIndex*: Option[GlyphIndex]
    lineIndex*: TextLineIndex
    containerIndex*: TextContainerIndex
    kind*: TextCaretPositionKind
    rect*: Rect

  TextLineFragment* = object
    lineIndex*: TextLineIndex
    containerIndex*: TextContainerIndex
    glyphRange*: GlyphRange
    textRange*: TextRange
    fragmentRect*: Rect
    usedRect*: Rect
    baseline*: float32
    ascent*: float32
    descent*: float32
    leading*: float32
    hardBreak*: bool
    wrapped*: bool

  TextLineFragmentMetrics* = object
    fragment*: TextLineFragment
    lineSpacing*: float32
    paragraphSpacingBefore*: float32
    paragraphSpacingAfter*: float32
    extraLineFragment*: bool

  TextGlyph* = object
    index*: GlyphIndex
    textRange*: TextRange
    properties*: GlyphProperties
    bounds*: Rect
    lineIndex*: TextLineIndex
    containerIndex*: TextContainerIndex

  TextLayoutSnapshot* = object
    textHash*: Hash
    layoutHash*: Hash
    containerRect*: Rect
    containers*: seq[TextContainer]
    containerRects*: seq[Rect]
    lineFragments*: seq[TextLineFragment]
    glyphCount*: Natural
    usedRect*: Rect
    contentSize*: Size

  TextContainer* = object
    origin*: Point
    size*: Size
    insets*: EdgeInsets
    lineFragmentPadding*: float32
    widthTracksTextView*: bool
    heightTracksTextView*: bool
    maximumNumberOfLines*: Natural
    lineBreakMode*: TextLineBreakMode
    wraps*: bool
    exclusionPaths*: seq[Rect]

  TextHitTestResult* = object
    point*: Point
    textIndex*: TextIndex
    textRange*: TextRange
    glyphIndex*: Option[GlyphIndex]
    lineIndex*: Option[TextLineIndex]
    containerIndex*: Option[TextContainerIndex]
