import std/[strutils, unicode, unittest]
import merenda/nimkit

suite "Styled text run extraction":
  test "Unicode runs match substring for string and gap storage":
    let source = "Aé中😀é\r\nZ"
    var runs: seq[TextAttributeRun]
    for index in 0 ..< source.runeLen:
      var attributes = defaultTextAttributes()
      attributes.fontSize = 12 + index.float32
      runs.add TextAttributeRun(range: initTextRange(index, 1), attributes: attributes)
    let gap = newTextGapStorage(source)
    for run in runs:
      gap.setAttributes(run.range, run.attributes)
    for storage in [newTextStorage(source, runs), TextStorage(gap)]:
      var index = 0
      for attributes, text in storage.styledRuns():
        check text == storage.substring(runs[index].range)
        check attributes == runs[index].attributes
        inc index
      check index == runs.len

  test "sparse overlapping and empty ranges preserve normalized run semantics":
    var first = defaultTextAttributes()
    var second = first
    second.fontSize += 1
    let storage = newTextStorage(
      "aé中😀xyz",
      @[
        TextAttributeRun(range: initTextRange(1, 3), attributes: first),
        TextAttributeRun(range: initTextRange(2, 2), attributes: second),
        TextAttributeRun(range: initTextRange(6, 9), attributes: first),
        TextAttributeRun(range: initTextRange(0, 0), attributes: first),
      ],
    )
    var expected: seq[string]
    for run in storage.runs():
      expected.add storage.substring(run.range)
    var actual: seq[string]
    for _, text in storage.styledRuns():
      actual.add text
    check actual == expected
    var emptyCount = 0
    for _, text in newTextStorage("").styledRuns():
      inc emptyCount
    check emptyCount == 0

  test "many highlighted Unicode runs reconstruct the source":
    const count = 4096
    let source = repeat("é😀", count)
    var runs: seq[TextAttributeRun]
    for index in 0 ..< count * 2:
      var attributes = defaultTextAttributes()
      attributes.fontSize = 12 + (index mod 2).float32
      runs.add TextAttributeRun(range: initTextRange(index, 1), attributes: attributes)
    let storage = newTextStorage(source, runs)
    var reconstructed: string
    var runCount = 0
    for _, text in storage.styledRuns():
      reconstructed.add text
      inc runCount
    check reconstructed == source
    check runCount == count * 2
