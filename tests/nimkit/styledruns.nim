import std/[strutils, unicode, unittest]
import merenda/nimkit
import merenda/nimkit/text/textbytecursors
import merenda/nimkit/text/textsnapshots

when defined(linux):
  proc rssKb(): int64 =
    for line in lines("/proc/self/status"):
      if line.startsWith("VmRSS:"):
        let fields = line.splitWhitespace()
        if fields.len >= 2:
          return parseInt(fields[1]).int64
    raise newException(IOError, "unable to read VmRSS from /proc/self/status")

elif defined(macosx):
  type
    MachPort = uint32
    MachMsgTypeNumber = uint32
    TimeValue = object
      seconds: int32
      microseconds: int32

    MachTaskBasicInfo = object
      virtualSize: uint64
      residentSize: uint64
      residentSizeMax: uint64
      userTime: TimeValue
      systemTime: TimeValue
      policy: int32
      suspendCount: int32

  const machTaskBasicInfoFlavor = 20

  var machTaskSelf {.importc: "mach_task_self_", header: "<mach/mach_init.h>".}:
    MachPort

  proc taskInfo(
    task: MachPort,
    flavor: cint,
    taskInfoOut: ptr MachTaskBasicInfo,
    taskInfoOutCount: ptr MachMsgTypeNumber,
  ): cint {.importc: "task_info", header: "<mach/task.h>".}

  proc rssKb(): int64 =
    var info: MachTaskBasicInfo
    var count = MachMsgTypeNumber(sizeof(MachTaskBasicInfo) div sizeof(cuint))
    let status = taskInfo(machTaskSelf, machTaskBasicInfoFlavor, addr info, addr count)
    doAssert status == 0, "task_info failed with kern_return_t " & $status
    int64(info.residentSize div 1024)

suite "Styled text run extraction":
  test "snapshots expose rune views and explicit UTF-8 byte ranges":
    let
      storage = newTextStorage("aé😀\xffz")
      snapshot = storage.textSnapshot()
      byteRange = snapshot.byteRange(initTextRange(1, 2))
    check snapshot.len == 5
    check snapshot.byteLength == 9
    check snapshot[1] == Rune(0xE9)
    check byteRange == initTextByteRange(1, 6)
    check snapshot.runeRange(byteRange) == initTextRange(1, 2)
    for span in storage.styledSpans():
      check span.byteRange == initTextByteRange(0, 9)
    var runes: seq[Rune]
    for rune in snapshot:
      runes.add rune
    check runes == snapshot.toRunes()
    expect ValueError:
      discard snapshot.runeRange(initTextByteRange(2, 1))

  test "endpoint cursors handle multibyte and malformed UTF-8":
    let source = "é\xff😀\r\n"
    var byteCursor, runeCursor: TextByteCursor
    check source.runeIndexAtByte(byteCursor, 1) == 0
    check source.runeIndexAtByte(byteCursor, 2) == 1
    check source.runeIndexAtByte(byteCursor, 3) == 2
    check source.runeIndexAtByte(byteCursor, 7) == 3
    check source.byteOffsetAtRune(runeCursor, 2) == 3
    check source.byteOffsetAtRune(runeCursor, 3) == 7

  test "bulk attributes preserve outside styles and ordered overlaps":
    let
      red = defaultTextAttributes(color(1.0, 0.0, 0.0))
      blue = defaultTextAttributes(color(0.0, 0.0, 1.0))
      green = defaultTextAttributes(color(0.0, 1.0, 0.0))
    for storage in [
      newTextStorage("aé中😀xyz"), TextStorage(newTextGapStorage("aé中😀xyz"))
    ]:
      let original = storage.textSnapshot()
      storage.setAttributes(initTextRange(0, 1), green)
      let manager = newUndoManager()
      storage.undoManager = manager
      storage.setAttributeRanges(
        initTextRange(1, 5),
        defaultTextAttributes(),
        [
          TextAttributeRun(range: initTextRange(2, 3), attributes: red),
          TextAttributeRun(range: initTextRange(3, 2), attributes: blue),
        ],
      )
      check storage.textSnapshot() == original
      check storage.attributesAt(0) == green
      check storage.attributesAt(1) == defaultTextAttributes()
      check storage.attributesAt(2) == red
      check storage.attributesAt(3) == blue
      check storage.attributesAt(4) == blue
      check storage.attributesAt(5) == defaultTextAttributes()
      check storage.attributesAt(6) == defaultTextAttributes()
      check manager.undoCount == 1
      check manager.performUndo()
      check storage.attributesAt(2) == defaultTextAttributes()
      check manager.performRedo()
      check storage.attributesAt(3) == blue

  test "attributed replacement registers one storage undo operation":
    let
      red = defaultTextAttributes(color(1.0, 0.0, 0.0))
      blue = defaultTextAttributes(color(0.0, 0.0, 1.0))
      insertion = newTextStorage(
        "é😀",
        @[
          TextAttributeRun(range: initTextRange(0, 1), attributes: red),
          TextAttributeRun(range: initTextRange(1, 1), attributes: blue),
        ],
      )
    for storage in [newTextStorage("abc"), TextStorage(newTextGapStorage("abc"))]:
      let manager = newUndoManager()
      storage.undoManager = manager
      storage.replace(initTextRange(1, 1), insertion)
      check storage.stringValue() == "aé😀c"
      check storage.attributesAt(1) == red
      check storage.attributesAt(2) == blue
      check manager.undoCount == 1
      check manager.performUndo()
      check storage.stringValue() == "abc"
      check manager.performRedo()
      check storage.stringValue() == "aé😀c"

  when defined(linux) or defined(macosx):
    test "large storage edits report RSS with undo disabled and enabled":
      const sourceBytes = 2 * 1024 * 1024
      for useGap in [false, true]:
        for enabled in [false, true]:
          let
            manager = newUndoManager()
            storage: TextStorage =
              if useGap:
                newTextGapStorage(repeat("abcdefgh", sourceBytes div 8))
              else:
                newTextStorage(repeat("abcdefgh", sourceBytes div 8))
          storage.undoManager = manager
          if not enabled:
            manager.disableUndoRegistration()
          let beforeKb = rssKb()
          storage.replace(initTextRange(1024, 1), "X")
          let afterKb = rssKb()
          echo "NimKit storage undo RSS: gap=",
            useGap, " enabled=", enabled, " delta_kib=", afterKb - beforeKb
          check manager.undoCount == (if enabled: 1 else: 0)
          if enabled:
            check manager.performUndo()
            check storage.substring(initTextRange(1024, 1)) == "a"
          else:
            manager.enableUndoRegistration()

    test "grouped and marked text report RSS for both storage types":
      for useGap in [false, true]:
        for enabled in [false, true]:
          let view = newTextView("abcd")
          if useGap:
            view.textStorage = newTextGapStorage("abcd")
          view.allowsUndo = enabled
          let beforeGroupKb = rssKb()
          view.beginUndoGrouping()
          for _ in 0 ..< 16:
            view.selectedRange = initTextRange(1, 0)
            view.insertTextValue("x")
          view.endUndoGrouping()
          let afterGroupKb = rssKb()
          check view.stringValue.len == 20
          if enabled:
            check view.undoText()
            check view.stringValue == "abcd"
          else:
            check not view.undoText()
          view.selectedRange = initTextRange(1, 1)
          let beforeMarkKb = rssKb()
          for _ in 0 ..< 16:
            view.setMarkedTextValue("é😀", initTextRange(1, 0), initTextRange(0, 0))
          view.insertTextValue("z")
          let afterMarkKb = rssKb()
          echo "NimKit TextView undo RSS: gap=",
            useGap,
            " enabled=",
            enabled,
            " grouped_delta_kib=",
            afterGroupKb - beforeGroupKb,
            " marked_delta_kib=",
            afterMarkKb - beforeMarkKb
          if enabled:
            check view.undoText()
            check view.stringValue == "abcd"
          else:
            check not view.undoText()

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

  when defined(linux) or defined(macosx):
    test "large styled document reports borrowed and owned run RSS":
      const
        sourceBytes = 8 * 1024 * 1024
        runBytes = 1024
        runCount = sourceBytes div runBytes
      let first = defaultTextAttributes()
      var second = first
      second.fontSize += 1
      # Run this file alone for RSS deltas without earlier suites reusing pages.
      let baselineKb = rssKb()
      var runs = newSeqOfCap[TextAttributeRun](runCount)
      for index in 0 ..< runCount:
        runs.add TextAttributeRun(
          range: initTextRange(index * runBytes, runBytes),
          attributes: (if index mod 2 == 0: first else: second),
        )
      let storage = newTextStorage(repeat("abcdefgh", sourceBytes div 8), runs)
      let storageKb = rssKb()

      var borrowed = newSeqOfCap[TextStyledSpan](runCount)
      for span in storage.styledSpans():
        borrowed.add span
      let borrowedKb = rssKb()

      var owned = newSeqOfCap[(TextAttributes, string)](runCount)
      for attributes, text in storage.styledRuns():
        owned.add((attributes, text))
      let ownedKb = rssKb()

      check storage.len == sourceBytes
      check borrowed.len == runCount
      check owned.len == runCount
      check owned[0][1] == repeat("abcdefgh", runBytes div 8)
      check owned[^1][1] == owned[0][1]
      echo "NimKit styled text RSS: source_mib=",
        sourceBytes div (1024 * 1024),
        " runs=",
        runCount,
        " baseline_kib=",
        baselineKb,
        " storage_kib=",
        storageKb,
        " borrowed_kib=",
        borrowedKb,
        " owned_kib=",
        ownedKb,
        " storage_delta_kib=",
        storageKb - baselineKb,
        " borrowed_delta_kib=",
        borrowedKb - storageKb,
        " owned_delta_kib=",
        ownedKb - borrowedKb

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
    let copy = storage.copyTextStorage()
    check copy.textSnapshot() == original
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
