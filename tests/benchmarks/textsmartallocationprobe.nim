## Matched TextView smart insertion allocation workload. The exact TextView
## version is copied to textviews_profile_baseline.nim when building each probe.
import std/[os, strutils]
import merenda/nimkit/text/[textviews_profile_baseline, textsnapshots]

if paramCount() != 3 or paramStr(1) notin ["small", "large"] or
    paramStr(2) notin ["begin", "middle", "end", "selected"] or
    paramStr(3) notin ["enabled", "disabled"]:
  quit "usage: textsmartallocationprobe small|large begin|middle|end|selected enabled|disabled"
let
  source = repeat("a", 8 * 1024 * 1024)
  insertion =
    if paramStr(1) == "small":
      "word"
    else:
      repeat("b", 1024 * 1024)
  position =
    case paramStr(2)
    of "begin":
      1
    of "end":
      source.len - 1
    else:
      source.len div 2
  selectionLength = if paramStr(2) == "selected": 5 else: 0
  view = newTextView(source)
view.allowsUndo = false
view.smartInsertDeleteEnabled = paramStr(3) == "enabled"
view.selectedRange = initTextRange(position, selectionLength)
view.insertTextValue(insertion)
var checksum = 14695981039346656037'u64
for rune in view.textStorage().textSnapshot():
  checksum = (checksum xor uint64(rune.int)) * 1099511628211'u64
echo "checkpoint smart=",
  paramStr(3),
  " size=",
  paramStr(1),
  " position=",
  paramStr(2),
  " sourceBytes=",
  source.len,
  " insertionBytes=",
  insertion.len,
  " length=",
  view.textStorage().len,
  " checksum=",
  checksum
stdout.flushFile()
discard readLine(stdin)
doAssert source.len > 0 and view.textStorage().len > 0
