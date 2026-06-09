import ./types

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

  TextAttributes* = object
    foregroundColor*: Color
    fontSize*: float32
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

func defaultTextAttributes*(
    color = initColor(0.08, 0.09, 0.11, 1.0), fontSize = DefaultFontSize
): TextAttributes =
  TextAttributes(foregroundColor: color, fontSize: max(fontSize, 1.0'f32))
