import std/[random, strutils, unittest]

import sigils/core

import merenda/nimkit

type
  StorageEventSpy = ref object of DynamicAgent
    events: seq[string]
    lastEdit: TextStorageEdit
    willEdits: int
    didEdits: int
    willProcess: int
    didProcess: int
    valueChanges: int
    attributeChanges: int

  StorageDelegateSpy = ref object of DynamicAgent
    shouldFixCount: int
    fallbackCount: int
    lastRange: TextRange
    fallbackSize: float32

  LazyStorageProvider = ref object of DynamicAgent
    text: string
    runs: seq[TextAttributeRun]
    stringRequests: int
    runRequests: int

  DispatchRecorder = ref object of DynamicAgent
    dispatches: seq[string]

protocol StorageEventSpySlots from StorageEventSpy:
  includes TextStorageEditingEvents

  proc willEdit(spy: StorageEventSpy, edit: TextStorageEdit) {.slot.} =
    inc spy.willEdits
    spy.lastEdit = edit
    spy.events.add "willEdit"

  proc didEdit(spy: StorageEventSpy, edit: TextStorageEdit) {.slot.} =
    inc spy.didEdits
    spy.lastEdit = edit
    spy.events.add "didEdit"

  proc storageWillProcessEditing(spy: StorageEventSpy, edit: TextStorageEdit) {.slot.} =
    inc spy.willProcess
    spy.lastEdit = edit
    spy.events.add "willProcess"

  proc storageDidProcessEditing(spy: StorageEventSpy, edit: TextStorageEdit) {.slot.} =
    inc spy.didProcess
    spy.lastEdit = edit
    spy.events.add "didProcess"

  proc storageValueDidChange(spy: StorageEventSpy, edit: TextStorageEdit) {.slot.} =
    inc spy.valueChanges
    spy.lastEdit = edit
    spy.events.add "value"

  proc storageAttributesDidChange(
      spy: StorageEventSpy, edit: TextStorageEdit
  ) {.slot.} =
    inc spy.attributeChanges
    spy.lastEdit = edit
    spy.events.add "attributes"

protocol StorageDelegateSpyProtocol of TextStorageDelegateProtocol:
  method textStorageShouldFixAttributes(
      spy: StorageDelegateSpy, storage: TextStorage, range: TextRange
  ): bool =
    discard storage
    inc spy.shouldFixCount
    spy.lastRange = range
    true

  method textStorageResolveFontFallback(
      spy: StorageDelegateSpy,
      storage: TextStorage,
      range: TextRange,
      attributes: TextAttributes,
  ): TextAttributes =
    discard storage
    inc spy.fallbackCount
    spy.lastRange = range
    result = attributes
    result.fontSize = spy.fallbackSize

protocol LazyStorageProviderProtocol of TextStorageLazyProviderProtocol:
  method lazyTextStorageString(
      provider: LazyStorageProvider, storage: TextStorage
  ): string =
    discard storage
    inc provider.stringRequests
    provider.text

  method lazyTextStorageRuns(
      provider: LazyStorageProvider, storage: TextStorage
  ): seq[TextAttributeRun] =
    discard storage
    inc provider.runRequests
    provider.runs

protocol DispatchRecorderProtocol from DispatchRecorder:
  method recordDispatch*(recorder: DispatchRecorder, name: string) =
    recorder.dispatches.add name

protocol RecordingTextStorageDispatchProtocol of TextStorageEditDispatchProtocol:
  method dispatchWillEdit(storage: TextStorage, edit: TextStorageEdit) =
    if not storage.delegate.isNil:
      discard storage.delegate.trySendLocal(recordDispatch(), "dispatchWillEdit")
    emit storage.willEdit(edit)

  method dispatchDidEdit(storage: TextStorage, edit: TextStorageEdit) =
    if not storage.delegate.isNil:
      discard storage.delegate.trySendLocal(recordDispatch(), "dispatchDidEdit")
    emit storage.didEdit(edit)

proc newStorageEventSpy(): StorageEventSpy =
  result = StorageEventSpy()
  discard result.withProto()

proc newStorageDelegateSpy(fallbackSize: float32): StorageDelegateSpy =
  result = StorageDelegateSpy(fallbackSize: fallbackSize)
  discard result.withProtocol(StorageDelegateSpyProtocol)

proc newLazyStorageProvider(
    text: string, runs: openArray[TextAttributeRun] = []
): LazyStorageProvider =
  result = LazyStorageProvider(text: text, runs: @runs)
  discard result.withProtocol(LazyStorageProviderProtocol)

proc newDispatchRecorder(): DispatchRecorder =
  result = DispatchRecorder()
  discard result.withProto()

proc newDispatchingTextStorage(value: string, recorder: DispatchRecorder): TextStorage =
  result = newTextStorage(value)
  result.delegate = DynamicAgent(recorder)
  discard result.withProtocol(RecordingTextStorageDispatchProtocol)

suite "nimkit text storage":
  test "text storage revisions advance once per committed editing batch":
    let storage = newTextStorage("abcd")

    check storage.revision == 0
    storage.replace(initTextRange(0, 1), "A")
    check storage.revision == 1

    storage.beginEditing()
    storage.setAttributes(
      initTextRange(0, 1), defaultTextAttributes(color(1.0, 0.0, 0.0))
    )
    storage.setAttributes(
      initTextRange(1, 1), defaultTextAttributes(color(0.0, 0.0, 1.0))
    )
    check storage.revision == 1
    storage.endEditing()
    check storage.revision == 2

  test "text storage replaces text and preserves surrounding attribute runs":
    let
      storage = newTextStorage("abcdef")
      red = defaultTextAttributes(color(1.0, 0.0, 0.0))
      blue = defaultTextAttributes(color(0.0, 0.0, 1.0))

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

  test "base storage scans UTF-8 lines and paragraphs in rune coordinates":
    let storage = newTextStorage("α\nβeta\n終")

    check storage.lineRange(0) == initTextRange(0, 2)
    check storage.lineRange(1) == initTextRange(2, 5)
    check storage.lineRange(2) == initTextRange(7, 1)
    check storage.substring(storage.lineRange(1)) == "βeta\n"
    check storage.paragraphRangeForRange(initTextRange(3, 0)) == initTextRange(2, 5)

  test "adjacent equal attribute runs are normalized":
    let
      storage = newTextStorage("abcd")
      accent = defaultTextAttributes(color(0.2, 0.4, 0.8))

    storage.setAttributes(initTextRange(0, 2), accent)
    storage.setAttributes(initTextRange(2, 2), accent)

    var count = 0
    for run in storage.runs:
      inc count
      check run.range == initTextRange(0, 4)
      check run.attributes == accent
    check count == 1

  test "attribute run lookups preserve Unicode ranges and default gaps":
    let
      accent = defaultTextAttributes(color(0.2, 0.6, 0.4), 14.0)
      storage = newTextStorage(
        "αβγδε",
        @[TextAttributeRun(range: initTextRange(1, 2), attributes: accent)],
      )
    check storage.attributeRunAt(-1).range == initTextRange(0, 1)
    check storage.attributeRunAt(0).attributes == defaultTextAttributes()
    check storage.attributeRunAt(1).range == initTextRange(1, 2)
    check storage.attributeRunAt(2).attributes == accent
    check storage.attributeRunAt(3).range == initTextRange(3, 2)
    check storage.attributeRunAt(100).attributes == defaultTextAttributes()

  test "effective color overlays report display edits and metric changes reflow":
    let storage = newTextStorage("abcdef")
    var red = storage.attributesAt(0)
    red.foregroundColor = color(0.9, 0.1, 0.2)
    var large = red
    large.fontSize += 4
    # The larger base style is completely overridden, so it cannot affect layout.
    storage.setAttributeRanges(
      initTextRange(0, 3),
      large,
      [TextAttributeRun(range: initTextRange(0, 3), attributes: red)],
    )
    check storage.currentEdit.displayOnly
    check storage.currentEdit.kinds == {tseAttributes}

    storage.beginEditing()
    storage.setAttributes(initTextRange(3, 1), red)
    storage.setAttributes(initTextRange(4, 1), red)
    storage.endEditing()
    check storage.currentEdit.displayOnly

    storage.beginEditing()
    storage.setAttributes(initTextRange(0, 1), large)
    storage.setAttributes(initTextRange(5, 1), red)
    storage.endEditing()
    check not storage.currentEdit.displayOnly

    storage.beginEditing()
    storage.setAttributes(initTextRange(1, 1), red)
    storage.replace(initTextRange(5, 1), "z")
    storage.endEditing()
    check not storage.currentEdit.displayOnly

  test "attribute run lookups retain precedence for overlapping precomputed runs":
    let
      red = defaultTextAttributes(color(0.9, 0.1, 0.2))
      blue = defaultTextAttributes(color(0.1, 0.2, 0.9))
      storage = newTextStorage(
        "abcdef",
        @[
          TextAttributeRun(range: initTextRange(0, 4), attributes: red),
          TextAttributeRun(range: initTextRange(1, 1), attributes: blue),
          TextAttributeRun(range: initTextRange(3, 3), attributes: blue),
        ],
      )
    check storage.attributesAt(3) == red
    check storage.attributeRunAt(4).range == initTextRange(4, 2)
    check storage.attributeRunAt(4).attributes == blue
    check storage.copyTextStorage().attributesAt(3) == red

  test "range iteration retains original runs across sparse and overlapping storage":
    let
      red = defaultTextAttributes(color(0.9, 0.1, 0.2))
      blue = defaultTextAttributes(color(0.1, 0.2, 0.9))
      source =
        @[
          TextAttributeRun(range: initTextRange(1, 4), attributes: red),
          TextAttributeRun(range: initTextRange(2, 1), attributes: blue),
          TextAttributeRun(range: initTextRange(4, 3), attributes: blue),
          TextAttributeRun(range: initTextRange(8, 1), attributes: red),
        ]
      storage = newTextStorage("aé中😀xyz!w", source)
    var found: seq[TextAttributeRun]
    for run in storage.runs(initTextRange(3, 2)):
      found.add run
    check found == @[source[0], source[2]]
    found.setLen(0)
    for run in storage.runs(initTextRange(7, 1)):
      found.add run
    check found.len == 0
    for run in storage.runs(initTextRange(1, 0)):
      found.add run
    for run in storage.runs(initTextRange(99, 1)):
      found.add run
    for run in TextStorage(nil).runs(initTextRange(0, 1)):
      found.add run
    check found.len == 0

  test "unordered overlays retain sparse gaps and precomputed overlap precedence":
    let
      red = defaultTextAttributes(color(0.9, 0.1, 0.2))
      blue = defaultTextAttributes(color(0.1, 0.2, 0.9))
      green = defaultTextAttributes(color(0.1, 0.8, 0.2))
      storage = newTextStorage(
        "aé中😀xyz!w",
        @[
          TextAttributeRun(range: initTextRange(1, 4), attributes: red),
          TextAttributeRun(range: initTextRange(2, 1), attributes: blue),
          TextAttributeRun(range: initTextRange(4, 2), attributes: blue),
        ],
      )
    storage.overlayAttributeRanges(
      [
        TextAttributeRun(range: initTextRange(8, 20), attributes: green),
        TextAttributeRun(range: initTextRange(1, 1), attributes: blue),
        TextAttributeRun(range: initTextRange(5, 1), attributes: green),
        TextAttributeRun(range: initTextRange(5, 1), attributes: red),
        TextAttributeRun(range: initTextRange(2, 0), attributes: green),
      ]
    )
    let expected = [
      defaultTextAttributes(),
      blue,
      red,
      red,
      red,
      red,
      defaultTextAttributes(),
      defaultTextAttributes(),
      green,
    ]
    for index, attributes in expected:
      check storage.attributesAt(index) == attributes
    check storage.currentEdit.range == initTextRange(1, 8)
    check storage.currentEdit.displayOnly
    let revision = storage.revision
    storage.overlayAttributeRanges([])
    storage.overlayAttributeRanges(
      [
        TextAttributeRun(range: initTextRange(2, 0), attributes: green),
        TextAttributeRun(range: initTextRange(99, 20), attributes: green),
      ]
    )
    check storage.revision == revision

  test "local range updates match per-rune styles across forward and backward edits":
    let palette = [
      defaultTextAttributes(),
      defaultTextAttributes(color(0.9, 0.1, 0.2)),
      defaultTextAttributes(color(0.1, 0.2, 0.9)),
    ]
    for storage in [
      newTextStorage("é😀".repeat(32)),
      TextStorage(newTextGapStorage("é😀".repeat(32))),
    ]:
      var
        rng = initRand(19317)
        expected = newSeq[TextAttributes](64)
      for attributes in expected.mitems:
        attributes = palette[0]
      for edit in 0 ..< 120:
        let
          first = rng.rand(63)
          stop = min(first + rng.rand(20) + 1, expected.len)
          base = palette[rng.rand(palette.high)]
        var overlays: seq[TextAttributeRun]
        for _ in 0 ..< 4:
          overlays.add TextAttributeRun(
            range: initTextRange(rng.rand(70), rng.rand(12)),
            attributes: palette[rng.rand(palette.high)],
          )
        if edit mod 2 == 0:
          storage.setAttributeRanges(initTextRange(first, stop - first), base, overlays)
          for index in first ..< stop:
            expected[index] = base
        else:
          storage.overlayAttributeRanges(overlays)
        for overlay in overlays:
          let
            overlayFirst =
              max(int(overlay.range.location), if edit mod 2 == 0: first else: 0)
            overlayStop =
              min(overlay.range.maxIndex, if edit mod 2 == 0: stop else: expected.len)
          for index in overlayFirst ..< overlayStop:
            expected[index] = overlay.attributes
        for index, attributes in expected:
          check storage.attributesAt(index) == attributes
        var
          previous: TextAttributeRun
          count = 0
        for run in storage.runs:
          check int(run.range.location) == previous.range.maxIndex
          if count > 0:
            check run.attributes != previous.attributes
          previous = run
          inc count
        check previous.range.maxIndex == expected.len
        check storage.currentEdit.displayOnly

  test "incremental restyling reuses released style IDs and keeps copies independent":
    for storage in [newTextStorage("abcdef"), TextStorage(newTextGapStorage("abcdef"))]:
      let original = storage.copyTextStorage()
      for iteration in 0 ..< 256:
        var attributes = defaultTextAttributes()
        attributes.foregroundColor = color(iteration.float32 / 256, 0.2, 0.5)
        storage.setAttributes(initTextRange(1, 4), attributes)
        for span in storage.styledSpans():
          check span.styleId <= 2
        check storage.attributesAt(1) == attributes
      check original.attributeRuns ==
        @[
          TextAttributeRun(
            range: initTextRange(0, 6), attributes: defaultTextAttributes()
          )
        ]
      let copy = storage.copyTextStorage()
      let copiedRuns = copy.attributeRuns
      storage.setAttributes(initTextRange(0, 6), defaultTextAttributes())
      check storage.attributeRuns.len == 1
      check copy.attributeRuns == copiedRuns

  test "overlays send one edit and undo restores a run table with a moved gap":
    for storage in [
      newTextStorage("aé中😀xyz"), TextStorage(newTextGapStorage("aé中😀xyz"))
    ]:
      let
        red = defaultTextAttributes(color(0.9, 0.1, 0.2))
        blue = defaultTextAttributes(color(0.1, 0.2, 0.9))
        manager = newUndoManager()
        spy = newStorageEventSpy()
      # Undo closures retain their storage; release history at this lifetime boundary.
      defer:
        manager.clearAll()
      storage.setAttributes(initTextRange(5, 1), blue)
      storage.setAttributes(initTextRange(1, 2), red)
      let originalRuns = storage.attributeRuns
      storage.undoManager = manager
      spy.observeProtocol(storage, TextStorageEditingEvents)
      storage.overlayAttributeRanges(
        [
          TextAttributeRun(range: initTextRange(0, 1), attributes: blue),
          TextAttributeRun(range: initTextRange(4, 2), attributes: red),
        ]
      )
      let overlaidRuns = storage.attributeRuns
      check spy.events ==
        @["willEdit", "didEdit", "willProcess", "didProcess", "attributes"]
      check spy.lastEdit.range == initTextRange(0, 6)
      check spy.lastEdit.displayOnly
      check manager.undoCount == 1
      check manager.performUndo()
      check storage.attributeRuns == originalRuns
      check manager.performRedo()
      check storage.attributeRuns == overlaidRuns

  test "rich text attributes preserve TextKit-style value fields":
    var attributes = defaultTextAttributes(color(0.1, 0.2, 0.3), 14.0)
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
    attributes.backgroundColor = color(1.0, 0.9, 0.2, 1.0)
    attributes.shadow =
      initTextShadow(color(0.0, 0.0, 0.0, 0.35), initSize(1.0, 2.0), 3.0)
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
      accent = defaultTextAttributes(color(0.8, 0.1, 0.2), 16.0)
      blue = defaultTextAttributes(color(0.0, 0.2, 1.0), 12.0)

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

  test "process editing coalesces batched changes through signals":
    let
      storage = newTextStorage("abcdef")
      spy = newStorageEventSpy()
      accent = defaultTextAttributes(color(0.3, 0.4, 0.9), 15.0)

    spy.observeProtocol(storage, TextStorageEditingEvents)
    storage.beginEditing()
    storage.replace(initTextRange(1, 2), "XYZ")
    storage.setAttributes(initTextRange(2, 2), accent)

    check spy.willEdits == 2
    check spy.didEdits == 2
    check spy.didProcess == 0
    check spy.valueChanges == 0
    check spy.attributeChanges == 0
    check storage.hasPendingEdit

    storage.endEditing()

    check spy.willProcess == 1
    check spy.didProcess == 1
    check spy.valueChanges == 1
    check spy.attributeChanges == 1
    check not storage.hasPendingEdit
    check storage.editedMask == {tseCharacters, tseAttributes}
    check storage.changeInLength == 1
    check spy.events[^4 .. ^1] == @["willProcess", "didProcess", "value", "attributes"]

  test "edit dispatch protocol can intercept delivery before signals":
    let
      recorder = newDispatchRecorder()
      storage = newDispatchingTextStorage("abc", recorder)
      spy = newStorageEventSpy()

    spy.observeProtocol(storage, TextStorageEditingEvents)
    check storage.conformsTo(TextStorageEditDispatchProtocol)

    storage.replace(initTextRange(1, 1), "Z")

    check storage.stringValue == "aZc"
    check recorder.dispatches[0] == "dispatchWillEdit"
    check recorder.dispatches[1] == "dispatchDidEdit"
    check spy.events[0] == "willEdit"
    check spy.events[1] == "didEdit"

  test "attribute fixing expands to paragraph ranges and resolves fallback fonts":
    let
      storage = newTextStorage("one\ntwo\nthree")
      delegate = newStorageDelegateSpy(17.0)
    var attributes = defaultTextAttributes(color(0.5, 0.1, 0.1), 13.0)
    attributes.fontSize = 0.0

    storage.delegate = DynamicAgent(delegate)
    storage.setAttributes(initTextRange(5, 1), attributes)

    check delegate.shouldFixCount == 1
    check delegate.fallbackCount == 3
    check not storage.currentEdit.displayOnly
    check storage.attributesAt(5).fontSize == 17.0
    check storage.paragraphRangeForRange(initTextRange(5, 1)) == initTextRange(4, 4)

  test "lazy text storage materializes through provider on first query":
    let
      accent = defaultTextAttributes(color(0.2, 0.6, 0.4), 14.0)
      provider = newLazyStorageProvider(
        "lazy", [TextAttributeRun(range: initTextRange(0, 4), attributes: accent)]
      )
      storage = newLazyTextStorage(DynamicAgent(provider))

    check not storage.isMaterialized()
    check provider.stringRequests == 0
    check storage.len == 4
    check storage.isMaterialized()
    check provider.stringRequests == 1
    check provider.runRequests == 1
    check storage.stringValue == "lazy"
    check storage.attributesAt(0) == accent
