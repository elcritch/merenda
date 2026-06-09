import std/[options, tables]

import sigils/selectors

import ./textstorage

type
  Pasteboard* = ref object
    xName: string
    xTypes: seq[string]
    xStrings: Table[string, string]
    xTextStorage: Table[string, TextStorage]
    xChangeCount: int
    xProvider: DynamicAgent

  PasteboardTypeRequest* = object
    pasteboard*: Pasteboard
    kind*: string

  PasteboardStringRequest* = object
    pasteboard*: Pasteboard
    kind*: string
    value*: string

const
  GeneralPasteboardName* = "NSGeneralPboard"
  DragPasteboardName* = "NSDragPboard"
  FindPasteboardName* = "NSFindPboard"
  FontPasteboardName* = "NSFontPboard"
  RulerPasteboardName* = "NSRulerPboard"

  PasteboardTypeString* = "public.utf8-plain-text"
  PasteboardTypeTextStorage* = "nimkit.text-storage"

protocol PasteboardProviderProtocol:
  method pasteboardTypes*(pasteboard: Pasteboard): seq[string] {.optional.}
  method stringForPasteboardType*(request: PasteboardTypeRequest): string {.optional.}
  method setStringForPasteboardType*(
    request: PasteboardStringRequest
  ): bool {.optional.}

  method clearPasteboardContents*(pasteboard: Pasteboard): bool {.optional.}

var
  namedPasteboards: Table[string, Pasteboard]
  namedPasteboardsReady: bool

proc ensureNamedPasteboards() =
  if not namedPasteboardsReady:
    namedPasteboards = initTable[string, Pasteboard]()
    namedPasteboardsReady = true

proc newPasteboard*(name = ""): Pasteboard =
  result = Pasteboard(xName: name)
  result.xStrings = initTable[string, string]()
  result.xTextStorage = initTable[string, TextStorage]()

proc pasteboardName*(pasteboard: Pasteboard): string =
  if pasteboard.isNil: "" else: pasteboard.xName

proc provider*(pasteboard: Pasteboard): DynamicAgent =
  if pasteboard.isNil: nil else: pasteboard.xProvider

proc `provider=`*(pasteboard: Pasteboard, provider: DynamicAgent) =
  if pasteboard.isNil:
    return
  pasteboard.xProvider = provider

proc providerTypes(pasteboard: Pasteboard): seq[string] =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return @[]
  let types = pasteboard.xProvider.trySendLocal(pasteboardTypes(), pasteboard)
  if types.isSome:
    return types.get()

proc providerString(pasteboard: Pasteboard, kind: string): string =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return ""
  let value = pasteboard.xProvider.trySendLocal(
    stringForPasteboardType(), PasteboardTypeRequest(pasteboard: pasteboard, kind: kind)
  )
  if value.isSome:
    return value.get()

proc clearProviderContents(pasteboard: Pasteboard): bool =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return false
  let cleared = pasteboard.xProvider.trySendLocal(clearPasteboardContents(), pasteboard)
  cleared.isSome and cleared.get()

proc setProviderString(pasteboard: Pasteboard, kind, value: string): bool =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return false
  let written = pasteboard.xProvider.trySendLocal(
    setStringForPasteboardType(),
    PasteboardStringRequest(pasteboard: pasteboard, kind: kind, value: value),
  )
  written.isSome and written.get()

proc syncProviderString(pasteboard: Pasteboard) =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return

  let providerTypes = pasteboard.providerTypes()
  if PasteboardTypeString notin providerTypes:
    return

  let providerString = pasteboard.providerString(PasteboardTypeString)
  if providerString.len == 0:
    return

  let currentString = pasteboard.xStrings.getOrDefault(PasteboardTypeString, "")
  if PasteboardTypeString in pasteboard.xTypes and providerString == currentString:
    return

  pasteboard.xTypes.setLen(0)
  pasteboard.xStrings.clear()
  pasteboard.xTextStorage.clear()
  pasteboard.xTypes.add PasteboardTypeString
  pasteboard.xStrings[PasteboardTypeString] = providerString
  inc pasteboard.xChangeCount

proc changeCount*(pasteboard: Pasteboard): int =
  if pasteboard.isNil: 0 else: pasteboard.xChangeCount

proc types*(pasteboard: Pasteboard): seq[string] =
  if pasteboard.isNil:
    @[]
  else:
    pasteboard.syncProviderString()
    pasteboard.xTypes

proc clearContents*(pasteboard: Pasteboard) =
  if pasteboard.isNil:
    return
  pasteboard.xTypes.setLen(0)
  pasteboard.xStrings.clear()
  pasteboard.xTextStorage.clear()
  inc pasteboard.xChangeCount
  discard pasteboard.clearProviderContents()

proc declareTypes*(pasteboard: Pasteboard, types: openArray[string]) =
  if pasteboard.isNil:
    return
  pasteboard.clearContents()
  for kind in types:
    if kind notin pasteboard.xTypes:
      pasteboard.xTypes.add kind

proc addType(pasteboard: Pasteboard, kind: string) =
  if not pasteboard.isNil and kind notin pasteboard.xTypes:
    pasteboard.xTypes.add kind

proc setString*(pasteboard: Pasteboard, kind, value: string): bool =
  if pasteboard.isNil:
    return false
  pasteboard.addType(kind)
  pasteboard.xStrings[kind] = value
  inc pasteboard.xChangeCount
  if kind == PasteboardTypeString:
    discard pasteboard.setProviderString(kind, value)
  true

proc stringForType*(pasteboard: Pasteboard, kind: string): string =
  if pasteboard.isNil:
    return ""
  if kind == PasteboardTypeString:
    pasteboard.syncProviderString()
  pasteboard.xStrings.getOrDefault(kind, "")

proc setTextStorage*(pasteboard: Pasteboard, kind: string, storage: TextStorage): bool =
  if pasteboard.isNil:
    return false
  pasteboard.addType(kind)
  pasteboard.xTextStorage[kind] =
    if storage.isNil:
      newTextStorage()
    else:
      storage.copyTextStorage()
  inc pasteboard.xChangeCount
  true

proc textStorageForType*(pasteboard: Pasteboard, kind: string): TextStorage =
  if pasteboard.isNil or kind notin pasteboard.xTextStorage:
    return nil
  pasteboard.xTextStorage[kind].copyTextStorage()

proc availableTypeFromArray*(
    pasteboard: Pasteboard, preferredTypes: openArray[string]
): string =
  if pasteboard.isNil:
    return ""
  pasteboard.syncProviderString()
  for kind in preferredTypes:
    if kind in pasteboard.xTypes:
      return kind

proc pasteboardWithName*(name: string): Pasteboard =
  ensureNamedPasteboards()
  let resolvedName = if name.len == 0: GeneralPasteboardName else: name
  if resolvedName notin namedPasteboards:
    namedPasteboards[resolvedName] = newPasteboard(resolvedName)
  namedPasteboards[resolvedName]

proc pasteboardWithUniqueName*(): Pasteboard =
  ensureNamedPasteboards()
  var index = namedPasteboards.len
  var name = "NimKitPasteboard" & $index
  while name in namedPasteboards:
    inc index
    name = "NimKitPasteboard" & $index
  result = newPasteboard(name)
  namedPasteboards[name] = result

proc generalPasteboard*(): Pasteboard =
  pasteboardWithName(GeneralPasteboardName)
