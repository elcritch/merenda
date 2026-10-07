## Reni matches converted from UTF-8 byte offsets to NimKit's rune ranges.

import ../foundation/textsearch
import ./[textbytecursors, texttypes]

export textsearch

proc searchRanges*(pattern: TextSearchPattern, text: string): seq[TextRange] =
  ## Separate cursors also handle overlapping spans reported by Reni's \K.
  var firstCursor, lastCursor: TextByteCursor
  for match in pattern.findMatches(text):
    let first = text.runeIndexAtByte(firstCursor, match.first)
    let last = text.runeIndexAtByte(lastCursor, match.last)
    result.add initTextRange(first, last - first)
