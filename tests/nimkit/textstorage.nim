import std/unittest

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

  test "process editing coalesces batched changes through signals":
    let
      storage = newTextStorage("abcdef")
      spy = newStorageEventSpy()
      accent = defaultTextAttributes(initColor(0.3, 0.4, 0.9), 15.0)

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
    var attributes = defaultTextAttributes(initColor(0.5, 0.1, 0.1), 13.0)
    attributes.fontSize = 0.0

    storage.delegate = DynamicAgent(delegate)
    storage.setAttributes(initTextRange(5, 1), attributes)

    check delegate.shouldFixCount == 1
    check delegate.fallbackCount == 3
    check storage.attributesAt(5).fontSize == 17.0
    check storage.paragraphRangeForRange(initTextRange(5, 1)) == initTextRange(4, 4)

  test "lazy text storage materializes through provider on first query":
    let
      accent = defaultTextAttributes(initColor(0.2, 0.6, 0.4), 14.0)
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
