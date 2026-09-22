import std/[strutils, unicode, unittest]
import merenda/nimkit
import merenda/nimkit/text/textsnapshots

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

  test "snapshots keep sparse rune and line checkpoints":
    let source = repeat("é😀\n", 130) & "終"
    let snapshot = newTextSnapshot(source)
    check snapshot.runeLength == 391
    check snapshot.byteLength == source.len
    check snapshot.runeCheckpointCount == 2
    check snapshot.lineCheckpointCount == 3
    check snapshot.byteOffset(0) == 0
    check snapshot.byteOffset(3 * 129) == source.len - "é😀\n終".len
    check snapshot.byteOffset(snapshot.runeLength) == source.len
    check snapshot.lineRange(64) == initTextRange(192, 3)
    check snapshot.lineRange(129) == initTextRange(387, 3)
    check snapshot.lineRange(130) == initTextRange(390, 1)
    check snapshot.lineRange(131) == initTextRange(391, 0)

  test "storage copies share a snapshot until characters change":
    let storage = newTextStorage("é😀z")
    let original = storage.textSnapshot()
    let copy = storage.copyTextStorage()
    check copy.textSnapshot() == original
    storage.setAttributes(
      initTextRange(0, 1), defaultTextAttributes(color(1.0, 0.0, 0.0))
    )
    check storage.textSnapshot() == original
    storage.replace(initTextRange(1, 1), "中")
    check storage.textSnapshot() != original
    check original.bytes == "é😀z"
    check copy.stringValue() == "é😀z"
    check storage.stringValue() == "é中z"

  test "gap storage reuses its snapshot until characters change":
    let storage = newTextGapStorage("é😀z")
    let original = storage.textSnapshot()
    check storage.textSnapshot() == original
    storage.setAttributes(
      initTextRange(0, 1), defaultTextAttributes(color(1.0, 0.0, 0.0))
    )
    check storage.textSnapshot() == original
    storage.replace(initTextRange(1, 1), "中")
    check storage.textSnapshot() != original
    check original.bytes == "é😀z"
    check storage.storageString() == "é中z"

  test "borrowed spans carry byte and rune ranges with shared style IDs":
    let
      red = defaultTextAttributes(color(1.0, 0.0, 0.0))
      blue = defaultTextAttributes(color(0.0, 0.0, 1.0))
      storage = newTextStorage(
        "é中😀",
        @[
          TextAttributeRun(range: initTextRange(0, 1), attributes: red),
          TextAttributeRun(range: initTextRange(1, 1), attributes: blue),
          TextAttributeRun(range: initTextRange(2, 1), attributes: red),
        ],
      )
      snapshot = storage.textSnapshot()
    var spans: seq[TextStyledSpan]
    for span in storage.styledSpans():
      spans.add span
    check spans.len == 3
    check spans[0].source == snapshot
    check spans[1].source == snapshot
    check spans[2].source == snapshot
    check spans[0].styleId == spans[2].styleId
    check spans[0].styleId != spans[1].styleId
    check spans[0].byteStart == 0
    check spans[0].byteEnd == 2
    check spans[1].byteStart == 2
    check spans[1].byteEnd == 5
    check spans[2].byteStart == 5
    check spans[2].byteEnd == 9
    check spans[2].runeStart == 2
    check spans[2].runeEnd == 3

  when not defined(useNativeDynlib):
    test "attributed layout retains the storage UTF-8 source":
      let
        red = defaultTextAttributes(color(1.0, 0.0, 0.0))
        blue = defaultTextAttributes(color(0.0, 0.0, 1.0))
        storage = newTextStorage(
          "éA\n中",
          @[
            TextAttributeRun(range: initTextRange(0, 1), attributes: red),
            TextAttributeRun(range: initTextRange(1, 3), attributes: blue),
          ],
        )
        snapshot = storage.textSnapshot()
        layout = textLayoutForMeasurement(rect(0.0, 0.0, 240.0, 80.0), storage)
      check cast[pointer](layout.sourceRunes) == cast[pointer](snapshot.sourceRunes)
      check layout.sourceRunes.len == snapshot.runeLength
