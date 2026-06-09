import std/tables

import ./textstorage

type Pasteboard* = ref object
  xTypes: seq[string]
  xStrings: Table[string, string]
  xTextStorage: Table[string, TextStorage]
  xChangeCount: int

const
  PasteboardTypeString* = "public.utf8-plain-text"
  PasteboardTypeTextStorage* = "nimkit.text-storage"

var sharedGeneralPasteboard: Pasteboard

proc newPasteboard*(): Pasteboard =
  result = Pasteboard()
  result.xStrings = initTable[string, string]()
  result.xTextStorage = initTable[string, TextStorage]()

proc changeCount*(pasteboard: Pasteboard): int =
  if pasteboard.isNil: 0 else: pasteboard.xChangeCount

proc types*(pasteboard: Pasteboard): seq[string] =
  if pasteboard.isNil:
    @[]
  else:
    pasteboard.xTypes

proc clearContents*(pasteboard: Pasteboard) =
  if pasteboard.isNil:
    return
  pasteboard.xTypes.setLen(0)
  pasteboard.xStrings.clear()
  pasteboard.xTextStorage.clear()
  inc pasteboard.xChangeCount

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
  true

proc stringForType*(pasteboard: Pasteboard, kind: string): string =
  if pasteboard.isNil:
    return ""
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
  for kind in preferredTypes:
    if kind in pasteboard.xTypes:
      return kind

proc generalPasteboard*(): Pasteboard =
  if sharedGeneralPasteboard.isNil:
    sharedGeneralPasteboard = newPasteboard()
  sharedGeneralPasteboard
