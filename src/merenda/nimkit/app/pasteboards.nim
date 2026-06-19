import std/[options, tables]

import sigils/selectors

import ../drawing/images
import ../foundation/types
import ../text/textstorage

type
  PasteboardItemKind* = enum
    pikNone
    pikString
    pikTextStorage
    pikData
    pikPropertyList
    pikUrl
    pikFile
    pikColor
    pikFont
    pikImage

  PasteboardPropertyValueKind* = enum
    ppvString
    ppvInteger
    ppvFloat
    ppvBool

  PasteboardPropertyValue* = object
    case kind*: PasteboardPropertyValueKind
    of ppvString:
      stringValue*: string
    of ppvInteger:
      integerValue*: int
    of ppvFloat:
      floatValue*: float
    of ppvBool:
      boolValue*: bool

  PasteboardProperty* = object
    key*: string
    value*: PasteboardPropertyValue

  PasteboardPropertyList* = seq[PasteboardProperty]

  PasteboardFontDescriptor* = object
    name*: string
    family*: string
    size*: float32
    traits*: seq[string]

  PasteboardItem* = object
    case kind*: PasteboardItemKind
    of pikNone:
      discard
    of pikString:
      stringValue*: string
    of pikTextStorage:
      textStorage*: TextStorage
    of pikData:
      data*: string
    of pikPropertyList:
      propertyList*: PasteboardPropertyList
    of pikUrl:
      url*: string
    of pikFile:
      filePath*: string
    of pikColor:
      color*: Color
    of pikFont:
      font*: PasteboardFontDescriptor
    of pikImage:
      image*: ImageResource

  Pasteboard* = ref object
    xName: string
    xTypes: seq[string]
    xItems: Table[string, PasteboardItem]
    xChangeCount: int
    xProvider: DynamicAgent
    xOwner: DynamicAgent

  PasteboardTypeRequest* = object
    pasteboard*: Pasteboard
    kind*: string

  PasteboardStringRequest* = object
    pasteboard*: Pasteboard
    kind*: string
    value*: string

  PasteboardItemRequest* = object
    pasteboard*: Pasteboard
    kind*: string
    item*: PasteboardItem

const
  GeneralPasteboardName* = "NSGeneralPboard"
  DragPasteboardName* = "NSDragPboard"
  FindPasteboardName* = "NSFindPboard"
  FontPasteboardName* = "NSFontPboard"
  RulerPasteboardName* = "NSRulerPboard"

  PasteboardTypeString* = "public.utf8-plain-text"
  PasteboardTypeTextStorage* = "nimkit.text-storage"
  PasteboardTypeData* = "public.data"
  PasteboardTypePropertyList* = "com.apple.property-list"
  PasteboardTypeUrl* = "public.url"
  PasteboardTypeFile* = "public.file-url"
  PasteboardTypeColor* = "public.color"
  PasteboardTypeFont* = "public.font"
  PasteboardTypeImage* = "public.image"
  PasteboardTypePromisedFile* = "com.apple.pasteboard.promised-file-url"

protocol PasteboardProviderProtocol:
  method pasteboardTypes*(pasteboard: Pasteboard): seq[string] {.optional.}
  method pasteboardChangeCount*(pasteboard: Pasteboard): int {.optional.}
  method pasteboardItemForType*(
    request: PasteboardTypeRequest
  ): PasteboardItem {.optional.}

  method setPasteboardItemForType*(request: PasteboardItemRequest): bool {.optional.}
  method stringForPasteboardType*(request: PasteboardTypeRequest): string {.optional.}
  method setStringForPasteboardType*(
    request: PasteboardStringRequest
  ): bool {.optional.}

  method clearPasteboardContents*(pasteboard: Pasteboard): bool {.optional.}
  method releasePasteboard*(pasteboard: Pasteboard): bool {.optional.}

protocol PasteboardOwnerProtocol:
  method providePasteboardItemForType*(
    request: PasteboardTypeRequest
  ): PasteboardItem {.optional.}

var
  namedPasteboards: Table[string, Pasteboard]
  namedPasteboardsReady: bool

proc ensureNamedPasteboards() =
  if not namedPasteboardsReady:
    namedPasteboards = initTable[string, Pasteboard]()
    namedPasteboardsReady = true

proc initPasteboardPropertyValue*(value: string): PasteboardPropertyValue =
  PasteboardPropertyValue(kind: ppvString, stringValue: value)

proc initPasteboardPropertyValue*(value: int): PasteboardPropertyValue =
  PasteboardPropertyValue(kind: ppvInteger, integerValue: value)

proc initPasteboardPropertyValue*(value: float): PasteboardPropertyValue =
  PasteboardPropertyValue(kind: ppvFloat, floatValue: value)

proc initPasteboardPropertyValue*(value: bool): PasteboardPropertyValue =
  PasteboardPropertyValue(kind: ppvBool, boolValue: value)

proc initPasteboardProperty*(key, value: string): PasteboardProperty =
  PasteboardProperty(key: key, value: initPasteboardPropertyValue(value))

proc initPasteboardProperty*(key: string, value: int): PasteboardProperty =
  PasteboardProperty(key: key, value: initPasteboardPropertyValue(value))

proc initPasteboardProperty*(key: string, value: float): PasteboardProperty =
  PasteboardProperty(key: key, value: initPasteboardPropertyValue(value))

proc initPasteboardProperty*(key: string, value: bool): PasteboardProperty =
  PasteboardProperty(key: key, value: initPasteboardPropertyValue(value))

proc initPasteboardFontDescriptor*(
    name = "", family = "", size = 0.0'f32, traits: openArray[string] = []
): PasteboardFontDescriptor =
  PasteboardFontDescriptor(name: name, family: family, size: size, traits: @traits)

proc initPasteboardStringItem*(value: string): PasteboardItem =
  PasteboardItem(kind: pikString, stringValue: value)

proc initPasteboardTextStorageItem*(storage: TextStorage): PasteboardItem =
  PasteboardItem(
    kind: pikTextStorage,
    textStorage:
      if storage.isNil:
        newTextStorage()
      else:
        storage.copyTextStorage(),
  )

proc initPasteboardDataItem*(data: string): PasteboardItem =
  PasteboardItem(kind: pikData, data: data)

proc initPasteboardPropertyListItem*(
    propertyList: openArray[PasteboardProperty]
): PasteboardItem =
  PasteboardItem(kind: pikPropertyList, propertyList: @propertyList)

proc initPasteboardUrlItem*(url: string): PasteboardItem =
  PasteboardItem(kind: pikUrl, url: url)

proc initPasteboardFileItem*(filePath: string): PasteboardItem =
  PasteboardItem(kind: pikFile, filePath: filePath)

proc initPasteboardColorItem*(color: Color): PasteboardItem =
  PasteboardItem(kind: pikColor, color: color)

proc initPasteboardFontItem*(font: PasteboardFontDescriptor): PasteboardItem =
  PasteboardItem(kind: pikFont, font: font)

proc initPasteboardImageItem*(image: ImageResource): PasteboardItem =
  PasteboardItem(
    kind: pikImage,
    image:
      if image.isNil:
        nil
      else:
        image.copyImageResource(),
  )

proc copyPasteboardItem*(item: PasteboardItem): PasteboardItem =
  case item.kind
  of pikNone:
    PasteboardItem(kind: pikNone)
  of pikString:
    initPasteboardStringItem(item.stringValue)
  of pikTextStorage:
    initPasteboardTextStorageItem(item.textStorage)
  of pikData:
    initPasteboardDataItem(item.data)
  of pikPropertyList:
    initPasteboardPropertyListItem(item.propertyList)
  of pikUrl:
    initPasteboardUrlItem(item.url)
  of pikFile:
    initPasteboardFileItem(item.filePath)
  of pikColor:
    initPasteboardColorItem(item.color)
  of pikFont:
    initPasteboardFontItem(item.font)
  of pikImage:
    initPasteboardImageItem(item.image)

proc newPasteboard*(name = ""): Pasteboard =
  result = Pasteboard(xName: name)
  result.xItems = initTable[string, PasteboardItem]()

proc pasteboardName*(pasteboard: Pasteboard): string =
  if pasteboard.isNil: "" else: pasteboard.xName

proc provider*(pasteboard: Pasteboard): DynamicAgent =
  if pasteboard.isNil: nil else: pasteboard.xProvider

proc `provider=`*(pasteboard: Pasteboard, provider: DynamicAgent) =
  if pasteboard.isNil:
    return
  pasteboard.xProvider = provider

proc owner*(pasteboard: Pasteboard): DynamicAgent =
  if pasteboard.isNil: nil else: pasteboard.xOwner

proc `owner=`*(pasteboard: Pasteboard, owner: DynamicAgent) =
  if pasteboard.isNil:
    return
  pasteboard.xOwner = owner

proc providerTypes(pasteboard: Pasteboard): seq[string] =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return @[]
  let types = pasteboard.xProvider.trySendLocal(pasteboardTypes(), pasteboard)
  if types.isSome:
    return types.get()

proc providerChangeCount(pasteboard: Pasteboard): Option[int] =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return none(int)
  let count = pasteboard.xProvider.trySendLocal(pasteboardChangeCount(), pasteboard)
  if count.isSome:
    return some(count.get())

proc providerItem(pasteboard: Pasteboard, kind: string): PasteboardItem =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return PasteboardItem(kind: pikNone)
  let item = pasteboard.xProvider.trySendLocal(
    pasteboardItemForType(), PasteboardTypeRequest(pasteboard: pasteboard, kind: kind)
  )
  if item.isSome:
    return item.get().copyPasteboardItem()

proc providerString(pasteboard: Pasteboard, kind: string): string =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return ""
  let value = pasteboard.xProvider.trySendLocal(
    stringForPasteboardType(), PasteboardTypeRequest(pasteboard: pasteboard, kind: kind)
  )
  if value.isSome:
    return value.get()

proc ownerItem(pasteboard: Pasteboard, kind: string): PasteboardItem =
  if pasteboard.isNil or pasteboard.xOwner.isNil:
    return PasteboardItem(kind: pikNone)
  let item = pasteboard.xOwner.trySendLocal(
    providePasteboardItemForType(),
    PasteboardTypeRequest(pasteboard: pasteboard, kind: kind),
  )
  if item.isSome:
    return item.get().copyPasteboardItem()

proc clearProviderContents(pasteboard: Pasteboard): bool =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return false
  let cleared = pasteboard.xProvider.trySendLocal(clearPasteboardContents(), pasteboard)
  cleared.isSome and cleared.get()

proc releaseProviderPasteboard(pasteboard: Pasteboard): bool =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return false
  let released = pasteboard.xProvider.trySendLocal(releasePasteboard(), pasteboard)
  released.isSome and released.get()

proc setProviderString(pasteboard: Pasteboard, kind, value: string): bool =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return false
  let written = pasteboard.xProvider.trySendLocal(
    setStringForPasteboardType(),
    PasteboardStringRequest(pasteboard: pasteboard, kind: kind, value: value),
  )
  written.isSome and written.get()

proc setProviderItem(pasteboard: Pasteboard, kind: string, item: PasteboardItem): bool =
  if pasteboard.isNil or pasteboard.xProvider.isNil:
    return false
  let written = pasteboard.xProvider.trySendLocal(
    setPasteboardItemForType(),
    PasteboardItemRequest(pasteboard: pasteboard, kind: kind, item: item),
  )
  if written.isSome:
    return written.get()
  if kind == PasteboardTypeString and item.kind == pikString:
    return pasteboard.setProviderString(kind, item.stringValue)

proc addType(pasteboard: Pasteboard, kind: string) =
  if not pasteboard.isNil and kind.len > 0 and kind notin pasteboard.xTypes:
    pasteboard.xTypes.add kind

proc syncProviderTypes(pasteboard: Pasteboard) =
  if pasteboard.isNil:
    return
  for kind in pasteboard.providerTypes():
    pasteboard.addType(kind)

proc storeMaterializedItem(
    pasteboard: Pasteboard, kind: string, item: PasteboardItem
): bool =
  if pasteboard.isNil or kind.len == 0 or item.kind == pikNone:
    return false
  pasteboard.addType(kind)
  pasteboard.xItems[kind] = item.copyPasteboardItem()
  true

proc materializeItem(pasteboard: Pasteboard, kind: string): bool =
  if pasteboard.isNil or kind.len == 0:
    return false
  if kind in pasteboard.xItems:
    return true

  var item = pasteboard.ownerItem(kind)
  if item.kind == pikNone:
    item = pasteboard.providerItem(kind)
  if item.kind == pikNone and kind == PasteboardTypeString:
    let value = pasteboard.providerString(kind)
    if value.len > 0:
      item = initPasteboardStringItem(value)
  pasteboard.storeMaterializedItem(kind, item)

proc changeCount*(pasteboard: Pasteboard): int =
  if pasteboard.isNil:
    return 0
  let providerCount = pasteboard.providerChangeCount()
  if providerCount.isSome:
    max(pasteboard.xChangeCount, providerCount.get())
  else:
    pasteboard.xChangeCount

proc types*(pasteboard: Pasteboard): seq[string] =
  if pasteboard.isNil:
    @[]
  else:
    pasteboard.syncProviderTypes()
    pasteboard.xTypes

proc clearLocalContents(pasteboard: Pasteboard) =
  pasteboard.xTypes.setLen(0)
  pasteboard.xItems.clear()

proc clearContents*(pasteboard: Pasteboard) =
  if pasteboard.isNil:
    return
  pasteboard.clearLocalContents()
  pasteboard.xOwner = nil
  inc pasteboard.xChangeCount
  discard pasteboard.clearProviderContents()

proc declareTypes*(
    pasteboard: Pasteboard, types: openArray[string], owner: DynamicAgent = nil
) =
  if pasteboard.isNil:
    return
  pasteboard.clearLocalContents()
  pasteboard.xOwner = owner
  for kind in types:
    pasteboard.addType(kind)
  inc pasteboard.xChangeCount
  discard pasteboard.clearProviderContents()

proc setItem*(pasteboard: Pasteboard, kind: string, item: PasteboardItem): bool =
  if pasteboard.isNil or kind.len == 0 or item.kind == pikNone:
    return false
  pasteboard.addType(kind)
  pasteboard.xItems[kind] = item.copyPasteboardItem()
  inc pasteboard.xChangeCount
  discard pasteboard.setProviderItem(kind, item)
  true

proc itemForType*(pasteboard: Pasteboard, kind: string): PasteboardItem =
  if pasteboard.isNil or kind.len == 0:
    return PasteboardItem(kind: pikNone)
  discard pasteboard.materializeItem(kind)
  if kind in pasteboard.xItems:
    return pasteboard.xItems[kind].copyPasteboardItem()
  PasteboardItem(kind: pikNone)

proc setString*(pasteboard: Pasteboard, kind, value: string): bool =
  pasteboard.setItem(kind, initPasteboardStringItem(value))

proc stringForType*(pasteboard: Pasteboard, kind: string): string =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikString:
    return item.stringValue

proc setTextStorage*(pasteboard: Pasteboard, kind: string, storage: TextStorage): bool =
  pasteboard.setItem(kind, initPasteboardTextStorageItem(storage))

proc textStorageForType*(pasteboard: Pasteboard, kind: string): TextStorage =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikTextStorage:
    return item.textStorage.copyTextStorage()

proc setData*(pasteboard: Pasteboard, kind, data: string): bool =
  pasteboard.setItem(kind, initPasteboardDataItem(data))

proc dataForType*(pasteboard: Pasteboard, kind: string): string =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikData:
    return item.data

proc setPropertyList*(
    pasteboard: Pasteboard, kind: string, propertyList: openArray[PasteboardProperty]
): bool =
  pasteboard.setItem(kind, initPasteboardPropertyListItem(propertyList))

proc propertyListForType*(
    pasteboard: Pasteboard, kind: string
): PasteboardPropertyList =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikPropertyList:
    return item.propertyList
  @[]

proc setUrl*(pasteboard: Pasteboard, kind, url: string): bool =
  pasteboard.setItem(kind, initPasteboardUrlItem(url))

proc urlForType*(pasteboard: Pasteboard, kind: string): string =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikUrl:
    return item.url

proc setFile*(pasteboard: Pasteboard, kind, filePath: string): bool =
  pasteboard.setItem(kind, initPasteboardFileItem(filePath))

proc fileForType*(pasteboard: Pasteboard, kind: string): string =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikFile:
    return item.filePath

proc setColor*(pasteboard: Pasteboard, kind: string, color: Color): bool =
  pasteboard.setItem(kind, initPasteboardColorItem(color))

proc colorForType*(pasteboard: Pasteboard, kind: string): Color =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikColor:
    return item.color

proc setFont*(
    pasteboard: Pasteboard, kind: string, font: PasteboardFontDescriptor
): bool =
  pasteboard.setItem(kind, initPasteboardFontItem(font))

proc fontForType*(pasteboard: Pasteboard, kind: string): PasteboardFontDescriptor =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikFont:
    return item.font

proc setImage*(pasteboard: Pasteboard, kind: string, image: ImageResource): bool =
  if image.isNil:
    return false
  pasteboard.setItem(kind, initPasteboardImageItem(image))

proc imageForType*(pasteboard: Pasteboard, kind: string): ImageResource =
  let item = pasteboard.itemForType(kind)
  if item.kind == pikImage:
    return item.image.copyImageResource()

proc availableTypeFromArray*(
    pasteboard: Pasteboard, preferredTypes: openArray[string]
): string =
  if pasteboard.isNil:
    return ""
  pasteboard.syncProviderTypes()
  for kind in preferredTypes:
    if kind in pasteboard.xTypes:
      return kind

proc releaseGlobally*(pasteboard: Pasteboard): bool =
  if pasteboard.isNil:
    return false
  let name = pasteboard.xName
  pasteboard.clearLocalContents()
  pasteboard.xOwner = nil
  inc pasteboard.xChangeCount
  let providerReleased = pasteboard.releaseProviderPasteboard()
  let providerCleared =
    if providerReleased:
      false
    else:
      pasteboard.clearProviderContents()

  ensureNamedPasteboards()
  var removed = false
  if name.len > 0 and name in namedPasteboards and namedPasteboards[name] == pasteboard:
    namedPasteboards.del(name)
    removed = true
  providerReleased or providerCleared or removed

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

proc dragPasteboard*(): Pasteboard =
  pasteboardWithName(DragPasteboardName)

proc findPasteboard*(): Pasteboard =
  pasteboardWithName(FindPasteboardName)

proc fontPasteboard*(): Pasteboard =
  pasteboardWithName(FontPasteboardName)

proc rulerPasteboard*(): Pasteboard =
  pasteboardWithName(RulerPasteboardName)
