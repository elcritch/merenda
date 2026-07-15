import std/[deques, isolation, locks, math, options, os, strutils, tables, times]

import threading/channels

when not compileOption("threads") and not defined(nimdoc):
  {.error: "NimKit's split renderer runtime requires --threads:on".}

when defined(useNativeDynlib):
  from figdraw/dynlib import clearColor, setFigUiScale, Renders
  import figdraw/dynlib as figrender
  import figdraw/dynlib as siwinshim
else:
  from figdraw import clearColor, setFigUiScale, Renders
  import figdraw as figrender
  import figdraw/windowing/siwinshim as siwinshim
when not defined(useNativeDynlib):
  import pkg/pixie/fileformats/png
import siwin/clipboards as siwinClipboards
import sigils/selectors

when defined(macosx) and not defined(useNativeDynlib):
  import darwin/app_kit/[nscolor, nspasteboard, nswindow]
  import darwin/objc/runtime

import ../drawing/images
import ../drawing/renderresources
import ../controls/nativemenus as nativeMenus
import ../foundation/types
import ../foundation/events
import ./pasteboards

when defined(macosx) and not defined(useNativeDynlib):
  proc setOpaque(window: NSWindow, opaque: BOOL) {.objc: "setOpaque:".}

type
  HostKeyEvent* = object
    event*: events.KeyEvent
    pressed*: bool
    isEscape*: bool
    isModifierChange*: bool

  HostWindowCallbacks* = object
    onClose*: proc() {.closure.}
    onResize*: proc() {.closure.}
    onMove*: proc(pos: Point) {.closure.}
    onMouseButton*: proc(event: events.MouseEvent, pressed: bool) {.closure.}
    onMouseMove*: proc(event: events.MouseEvent, dragging: bool) {.closure.}
    onScroll*: proc(event: events.ScrollEvent) {.closure.}
    onKey*: proc(event: HostKeyEvent) {.closure.}
    onTextInput*: proc(text: string) {.closure.}
    onRender*: proc() {.closure.}
    onFocusChanged*: proc(focused: bool) {.closure.}
    onPopupDone*: proc() {.closure.}

  ThreadHostId* = uint64

  ThreadHostEventKind* = enum
    theReady
    theClosed
    thePopupDone
    theResized
    theMoved
    theMouseButton
    theMouseMove
    theScroll
    theKey
    theTextInput
    theFocusChanged
    theRendered

  ThreadHostEvent* = object
    kind*: ThreadHostEventKind
    size*: Size
    point*: Point
    mouseEvent*: events.MouseEvent
    scrollEvent*: events.ScrollEvent
    keyEvent*: HostKeyEvent
    text*: string
    flag*: bool
    contentScale*: float32
    renderCount*: Natural

  ThreadHostEventQueueObj = object
    lock: Lock
    pending: Deque[ThreadHostEvent]
    lockReady: bool

  ThreadHostEventQueue* = ref ThreadHostEventQueueObj

  ThreadHostCommandKind* = enum
    thcRequestRender
    thcSetLogicalSize
    thcSetMinimumSize
    thcSetMaximumSize
    thcSetTitle
    thcSetVisible
    thcClose

  ThreadHostCommand* = object
    kind*: ThreadHostCommandKind
    size*: Size
    title*: string
    visible*: bool

  ThreadRenderSnapshot* = object
    renders*: Renders
    logicalSize*: Size
    resources*: FrozenRenderResources

  ThreadMenuId* = uint

  ThreadNativeMenuItem* = object
    id*: ThreadMenuId
    title*: string
    separator*: bool
    enabled*: bool
    hidden*: bool
    state*: nativeMenus.NativeMenuItemState
    tag*: int
    keyEquivalent*: string
    modifiers*: set[nativeMenus.NativeMenuModifier]
    submenu*: ThreadNativeMenu

  ThreadNativeMenu* = object
    id*: ThreadMenuId
    title*: string
    items*: seq[ThreadNativeMenuItem]

  ThreadNativeMenuSnapshot* = object
    installed*: bool
    menu*: ThreadNativeMenu
    windowsMenu*: ThreadMenuId
    servicesMenu*: ThreadMenuId

  ThreadMenuEventKind* = enum
    tmeRefresh
    tmeClose
    tmeActivate

  ThreadMenuEvent* = object
    kind*: ThreadMenuEventKind
    menu*: ThreadMenuId
    item*: ThreadMenuId

  ThreadHostChannels* = object
    events*: ThreadHostEventQueue
    commands*: Chan[ThreadHostCommand]
    renders*: Chan[ThreadRenderSnapshot]

  ThreadHostCreateRequest* = object
    id*: ThreadHostId
    ownerId*: ThreadHostId
    frame*: Rect
    title*: string
    isPopup*: bool
    popupPlacement*: siwinshim.PopupPlacement
    channels*: ThreadHostChannels

  ThreadRendererCommandKind* = enum
    trcCreateHost
    trcSetNativeMenu
    trcShowAboutPanel
    trcHideOtherApplications
    trcUnhideAllApplications
    trcQuit

  ThreadRendererCommand* = object
    kind*: ThreadRendererCommandKind
    create*: ThreadHostCreateRequest
    menu*: ThreadNativeMenuSnapshot

  ThreadRendererClient* = ref object
    commands: Chan[ThreadRendererCommand]
    menuEvents: Chan[ThreadMenuEvent]
    nextHostId: uint64

  ThreadHostClient* = ref object
    id*: ThreadHostId
    channels*: ThreadHostChannels
    createRequested*: bool
    ready*: bool
    renderRequested*: bool
    renderCount*: Natural
    contentScale*: float32

  HostWindow* = ref object
    xNativeWindow: siwinshim.Window
    xRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    xAutoScale: bool
    xCallbacks: HostWindowCallbacks
    xReady: bool
    xOwnerKey: pointer
    xRenderRequested: bool
    xRenderCount: Natural
    xHasUiScaleOverride: bool
    xUiScaleOverride: float32
    xTransparent: bool
    xResources: RenderResourceManager

  ThreadRendererHost = ref object
    id: ThreadHostId
    host: HostWindow
    channels: ThreadHostChannels
    lastRenders: Renders
    lastResources: FrozenRenderResources
    logicalSize: Size

  ThreadRenderer* = ref object
    commands: Chan[ThreadRendererCommand]
    menuEvents: Chan[ThreadMenuEvent]
    hosts: Table[ThreadHostId, ThreadRendererHost]
    running: bool

  NativePasteboardProvider = ref object of DynamicAgent
    xHost: HostWindow
    xTypes: seq[string]
    xItems: Table[string, PasteboardItem]
    xItemsReady: bool
    xChangeCount: int
    xHostChangeCount: int
    xObservedHostChangeCount: int
    xHasObservedHostChangeCount: bool
    xHostFingerprint: string
    xHasHostFingerprint: bool

  NativePasteboardPayload = ref object of RootObj
    items: Table[string, PasteboardItem]

proc `=destroy`(queue: ThreadHostEventQueueObj) =
  let queuePtr = addr(queue)
  if queuePtr.lockReady:
    deinitLock(queuePtr.lock)
  `=destroy`(queuePtr.pending)

var
  hostWindows {.threadvar.}: Table[pointer, HostWindow]
  hostWindowsReady {.threadvar.}: bool
  nativePasteboardProvider {.threadvar.}: NativePasteboardProvider

const NativeImagePngType = "image/png"
const
  UiScaleEnv* = "UISCALE"
  NimKitUiScaleEnv* = "NIMKIT_UI_SCALE"
  NimKitCompactUiScaleEnv* = "NIMKIT_UISCALE"
  MerendaUiScaleEnv* = "MERENDA_UISCALE"
  FigDrawLegacyUiScaleEnv* = "HDI"
  UiScaleEnvVars* = [
    NimKitUiScaleEnv, NimKitCompactUiScaleEnv, MerendaUiScaleEnv, UiScaleEnv,
    FigDrawLegacyUiScaleEnv,
  ]

const
  ThreadRendererCommandCapacity = 256
  ThreadHostCommandCapacity = 128
  ThreadRenderCapacity = 2
  ThreadMenuEventCapacity = 128

proc sendMoved[T](channel: Chan[T], value: sink T) =
  var value = move value
  channel.send(unsafeIsolate(move value))

proc pushLatest[T](channel: Chan[T], value: sink T) =
  var
    value = move value
    isolated = unsafeIsolate(move value)
  if channel.tryTake(isolated):
    return

  var stale: T
  discard channel.tryRecv(stale)
  if not channel.tryTake(isolated):
    discard

func coalesces(kind: ThreadHostEventKind): bool =
  kind in {theResized, theMoved, theMouseMove, theRendered}

proc newThreadHostEventQueue*(): ThreadHostEventQueue =
  result = ThreadHostEventQueue(pending: initDeque[ThreadHostEvent]())
  initLock(result.lock)
  result.lockReady = true

proc post*(queue: ThreadHostEventQueue, event: sink ThreadHostEvent) =
  if queue.isNil:
    return
  withLock queue.lock:
    if event.kind.coalesces() and queue.pending.len > 0 and
        queue.pending.peekLast().kind == event.kind:
      queue.pending[^1] = ensureMove event
    else:
      queue.pending.addLast(ensureMove event)

proc poll*(queue: ThreadHostEventQueue, event: var ThreadHostEvent): bool =
  if queue.isNil:
    return
  withLock queue.lock:
    if queue.pending.len > 0:
      event = queue.pending.popFirst()
      result = true

proc newThreadRenderer*(): tuple[renderer: ThreadRenderer, client: ThreadRendererClient] =
  let
    commands = newChan[ThreadRendererCommand](ThreadRendererCommandCapacity)
    menuEvents = newChan[ThreadMenuEvent](ThreadMenuEventCapacity)
  result.renderer = ThreadRenderer(
    commands: commands,
    menuEvents: menuEvents,
    hosts: initTable[ThreadHostId, ThreadRendererHost](),
  )
  result.client =
    ThreadRendererClient(commands: commands, menuEvents: menuEvents, nextHostId: 1)

proc newThreadHostClient*(renderer: ThreadRendererClient): ThreadHostClient =
  if renderer.isNil:
    return nil
  result = ThreadHostClient(
    id: ThreadHostId(renderer.nextHostId),
    channels: ThreadHostChannels(
      events: newThreadHostEventQueue(),
      commands: newChan[ThreadHostCommand](ThreadHostCommandCapacity),
      renders: newChan[ThreadRenderSnapshot](ThreadRenderCapacity),
    ),
    contentScale: 1.0'f32,
  )
  inc renderer.nextHostId

proc requestCreation*(
    host: ThreadHostClient,
    renderer: ThreadRendererClient,
    frame: Rect,
    title: string,
    owner: ThreadHostClient = nil,
    popupPlacement = siwinshim.PopupPlacement(),
) =
  if host.isNil or renderer.isNil or host.createRequested:
    return
  let ownerId =
    if owner.isNil:
      ThreadHostId(0)
    else:
      owner.id
  host.createRequested = true
  renderer.commands.sendMoved(
    ThreadRendererCommand(
      kind: trcCreateHost,
      create: ThreadHostCreateRequest(
        id: host.id,
        ownerId: ownerId,
        frame: frame,
        title: title,
        isPopup: not owner.isNil,
        popupPlacement: popupPlacement,
        channels: host.channels,
      ),
    )
  )

proc stopRenderer*(renderer: ThreadRendererClient) =
  if not renderer.isNil:
    renderer.commands.sendMoved(ThreadRendererCommand(kind: trcQuit))

proc submitNativeMenu*(
    renderer: ThreadRendererClient, snapshot: sink ThreadNativeMenuSnapshot
) =
  if not renderer.isNil:
    renderer.commands.sendMoved(
      ThreadRendererCommand(kind: trcSetNativeMenu, menu: move snapshot)
    )

proc pollMenuEvent*(renderer: ThreadRendererClient, event: var ThreadMenuEvent): bool =
  not renderer.isNil and renderer.menuEvents.tryRecv(event)

proc showAboutPanel*(renderer: ThreadRendererClient) =
  if not renderer.isNil:
    renderer.commands.sendMoved(ThreadRendererCommand(kind: trcShowAboutPanel))

proc hideOtherApplications*(renderer: ThreadRendererClient) =
  if not renderer.isNil:
    renderer.commands.sendMoved(ThreadRendererCommand(kind: trcHideOtherApplications))

proc unhideAllApplications*(renderer: ThreadRendererClient) =
  if not renderer.isNil:
    renderer.commands.sendMoved(ThreadRendererCommand(kind: trcUnhideAllApplications))

proc sendCommand*(host: ThreadHostClient, command: sink ThreadHostCommand) =
  if not host.isNil and host.createRequested:
    host.channels.commands.pushLatest(command)

proc submitRenders*(
    host: ThreadHostClient,
    renders: sink Renders,
    logicalSize: Size,
    resources: sink FrozenRenderResources = default(FrozenRenderResources),
): bool {.discardable.} =
  if host.isNil or not host.createRequested or renders.isNil:
    return false
  var snapshot = ThreadRenderSnapshot(
    renders: ensureMove renders,
    logicalSize: logicalSize,
    resources: ensureMove resources,
  )
  host.channels.renders.pushLatest(move snapshot)
  host.renderRequested = true
  true

proc pollEvent*(host: ThreadHostClient, event: var ThreadHostEvent): bool =
  not host.isNil and host.channels.events.poll(event)

proc pollLatestRender*(
    channels: ThreadHostChannels, snapshot: var ThreadRenderSnapshot
): bool =
  var pending: ThreadRenderSnapshot
  while channels.renders.tryRecv(pending):
    snapshot = move pending
    result = true

type UiScaleOverride* = object
  envName*: string
  scale*: float32

proc ensureHostRegistry() =
  if not hostWindowsReady:
    hostWindows = initTable[pointer, HostWindow]()
    hostWindowsReady = true

proc uiScaleOverrideFromEnv*(): Option[UiScaleOverride] =
  for envName in UiScaleEnvVars:
    if not envOverrideAllowed(envName):
      continue
    let value = getEnv(envName).strip()
    if value.len == 0:
      continue
    let scale = value.parseFloat().float32
    if scale <= 0.0'f32 or scale != scale or scale > float32.high:
      let message = envName & " must be a finite number greater than zero"
      raise newException(ValueError, message)
    return some(UiScaleOverride(envName: envName, scale: scale))
  none(UiScaleOverride)

proc nativePixels(value: float32, scale: float32): int32 =
  max((max(value, 1.0'f32) * scale).round().int32, 1)

proc nativeWindowSize(frameSize: Size, scale: float32): IVec2 =
  ivec2(nativePixels(frameSize.width, scale), nativePixels(frameSize.height, scale))

proc nativeWindowLimit(value, scale: float32): int32 =
  let scaled = value * scale
  if scaled <= 0.0'f32 or scaled >= int32.high.float32:
    return 0
  max(scaled.round().int32, 1)

proc overrideScale(override: Option[UiScaleOverride]): float32 =
  if override.isSome:
    override.get().scale
  else:
    1.0'f32

proc configureHostUiScale(host: HostWindow, override: Option[UiScaleOverride]) =
  if override.isSome:
    host.xHasUiScaleOverride = true
    host.xUiScaleOverride = override.get().scale
    host.xAutoScale = false
    setFigUiScale(host.xUiScaleOverride)
  elif not host.xNativeWindow.isNil:
    host.xAutoScale = host.xNativeWindow.configureUiScale()

proc configuredUiScale(host: HostWindow): float32 =
  if host.xHasUiScaleOverride:
    return host.xUiScaleOverride
  if host.xNativeWindow.isNil:
    return 1.0'f32
  max(host.xNativeWindow.contentScale(), 1.0'f32)

proc usesScaledBackingSize(host: HostWindow, window: siwinshim.Window): bool =
  if window.isNil:
    return false
  if host.xHasUiScaleOverride:
    return true
  let scale = host.configuredUiScale()
  scale != 1.0'f32 and not window.inputUsesBackingPixels()

proc logicalSizeForBacking(host: HostWindow, window: siwinshim.Window): Vec2 =
  let
    scale = host.configuredUiScale()
    backing = window.backingSize()
  vec2(backing.x.float32 / scale, backing.y.float32 / scale)

proc nativeWindowKey(nativeWindow: siwinshim.Window): pointer =
  cast[pointer](nativeWindow)

proc registerHost(host: HostWindow) =
  if host.xNativeWindow.isNil:
    return
  ensureHostRegistry()
  host.xOwnerKey = host.xNativeWindow.nativeWindowKey
  hostWindows[host.xOwnerKey] = host

proc unregisterHost(host: HostWindow) =
  if host.xOwnerKey.isNil:
    return
  ensureHostRegistry()
  hostWindows.del(host.xOwnerKey)
  host.xOwnerKey = nil

proc hostReady(host: HostWindow): bool =
  host.xReady and not host.xNativeWindow.isNil

proc firstReadyHost(): HostWindow =
  ensureHostRegistry()
  for host in hostWindows.values:
    if host.hostReady:
      return host

proc clipboardText(clipboard: siwinClipboards.Clipboard): string =
  let content = clipboard.content(siwinClipboards.ClipboardContentKind.text)
  case content.kind
  of siwinClipboards.ClipboardContentKind.text: content.text
  else: ""

proc clipboardFiles(clipboard: siwinClipboards.Clipboard): seq[string] =
  let content = clipboard.content(siwinClipboards.ClipboardContentKind.files)
  case content.kind
  of siwinClipboards.ClipboardContentKind.files:
    content.files
  else:
    @[]

proc clipboardData(clipboard: siwinClipboards.Clipboard, mimeType: string): string =
  let content = clipboard.content(siwinClipboards.ClipboardContentKind.other, mimeType)
  case content.kind
  of siwinClipboards.ClipboardContentKind.other: content.data
  else: ""

proc `clipboardText=`(clipboard: siwinClipboards.Clipboard, value: string) =
  type TextClipboardPayload = ref object of RootObj
    value: string

  var content: siwinClipboards.ClipboardConvertableContent
  content.data = TextClipboardPayload(value: value)
  content.converters.add siwinClipboards.ClipboardContentConverter(
    kind: siwinClipboards.ClipboardContentKind.text,
    f: proc(
        data: ref RootObj, kind: siwinClipboards.ClipboardContentKind, mimeType: string
    ): siwinClipboards.ClipboardContent =
      siwinClipboards.ClipboardContent(
        kind: siwinClipboards.ClipboardContentKind.text,
        text: TextClipboardPayload(data).value,
      ),
  )
  clipboard.content = content

proc readyHost(provider: NativePasteboardProvider): HostWindow =
  if not provider.xHost.hostReady:
    provider.xHost = firstReadyHost()
  provider.xHost

proc ensureItems(provider: NativePasteboardProvider) =
  if provider.xItemsReady:
    return
  provider.xItems = initTable[string, PasteboardItem]()
  provider.xItemsReady = true

proc addType(provider: NativePasteboardProvider, kind: string) =
  if kind.len == 0:
    return
  if kind notin provider.xTypes:
    provider.xTypes.add kind

proc addType(types: var seq[string], kind: string) =
  if kind.len > 0 and kind notin types:
    types.add kind

proc hostReportedChangeCount(provider: NativePasteboardProvider): Option[int] =
  discard provider
  when defined(macosx) and not defined(useNativeDynlib):
    let pasteboard = NSPasteboard.generalPasteboard()
    if pasteboard != nil:
      return some(pasteboard.changeCount().int)
  none(int)

proc hostClipboardFingerprint(provider: NativePasteboardProvider): Option[string] =
  let host = provider.readyHost()
  if not host.hostReady:
    return none(string)
  let clipboard = host.xNativeWindow.clipboard
  var parts: seq[string]

  let text = clipboard.clipboardText
  if text.len > 0:
    parts.add "text=" & text

  for filePath in clipboard.clipboardFiles:
    parts.add "file=" & filePath

  for mimeType in clipboard.availableMimeTypes:
    parts.add "mime=" & mimeType & "=" & clipboard.clipboardData(mimeType)

  some(parts.join("\x1F"))

proc syntheticHostChangeCount(provider: NativePasteboardProvider): Option[int] =
  let fingerprint = provider.hostClipboardFingerprint()
  if fingerprint.isNone:
    return none(int)
  let value = fingerprint.get()
  if not provider.xHasHostFingerprint:
    provider.xHostFingerprint = value
    provider.xHasHostFingerprint = true
  elif value != provider.xHostFingerprint:
    provider.xHostFingerprint = value
    inc provider.xHostChangeCount
  some(provider.xHostChangeCount)

proc currentHostChangeCount(provider: NativePasteboardProvider): Option[int] =
  let reported = provider.hostReportedChangeCount()
  if reported.isSome:
    return reported
  provider.syntheticHostChangeCount()

proc clearHostBackedCache(provider: NativePasteboardProvider) =
  provider.ensureItems()
  provider.xTypes.setLen(0)
  provider.xItems.clear()

proc syncExternalHostChanges(provider: NativePasteboardProvider): Option[int] =
  let count = provider.currentHostChangeCount()
  if count.isNone:
    return none(int)
  let value = count.get()
  if not provider.xHasObservedHostChangeCount:
    provider.xObservedHostChangeCount = value
    provider.xHasObservedHostChangeCount = true
  elif value != provider.xObservedHostChangeCount:
    provider.xObservedHostChangeCount = value
    provider.clearHostBackedCache()
  some(value)

proc observeHostChangeCount(provider: NativePasteboardProvider) =
  let count = provider.currentHostChangeCount()
  if count.isSome:
    provider.xObservedHostChangeCount = count.get()
    provider.xHasObservedHostChangeCount = true

proc hostTypes(provider: NativePasteboardProvider): seq[string] =
  let host = provider.readyHost()
  if not host.hostReady:
    return @[]
  let clipboard = host.xNativeWindow.clipboard
  if clipboard.clipboardText.len > 0:
    result.addType(PasteboardTypeString)
  if clipboard.clipboardFiles.len > 0:
    result.addType(PasteboardTypeFile)
    result.addType(PasteboardTypeUrl)
  for mimeType in clipboard.availableMimeTypes:
    case mimeType
    of NativeImagePngType:
      result.addType(PasteboardTypeImage)
    of "public.utf8-plain-text", "NSStringPboardType", "text/plain":
      result.addType(PasteboardTypeString)
    of "text/uri-list":
      result.addType(PasteboardTypeFile)
      result.addType(PasteboardTypeUrl)
    else:
      result.addType(mimeType)

proc copyItems(provider: NativePasteboardProvider): Table[string, PasteboardItem] =
  provider.ensureItems()
  result = initTable[string, PasteboardItem]()
  for kind, item in provider.xItems:
    result[kind] = item.copyPasteboardItem()

proc itemForPayload(
    data: ref RootObj, kind: string, fallbackKind = ""
): PasteboardItem =
  if data.isNil:
    return PasteboardItem(kind: pikNone)
  let payload = NativePasteboardPayload(data)
  if kind in payload.items:
    return payload.items[kind].copyPasteboardItem()
  if fallbackKind.len > 0 and fallbackKind in payload.items:
    return payload.items[fallbackKind].copyPasteboardItem()
  PasteboardItem(kind: pikNone)

proc payloadFiles(data: ref RootObj): seq[string] =
  if data.isNil:
    return @[]
  let payload = NativePasteboardPayload(data)
  for item in payload.items.values:
    case item.kind
    of pikFile:
      if item.filePath.len > 0:
        result.add item.filePath
    of pikUrl:
      if item.url.startsWith("file://"):
        result.add item.url.substr("file://".len)
    else:
      discard

proc payloadOtherData(data: ref RootObj, mimeType: string): string =
  let item =
    if mimeType == NativeImagePngType:
      itemForPayload(data, PasteboardTypeImage)
    else:
      itemForPayload(data, mimeType, PasteboardTypeData)
  case item.kind
  of pikData:
    item.data
  of pikUrl:
    item.url
  of pikFile:
    item.filePath
  of pikString:
    item.stringValue
  of pikImage:
    let pixels = item.image.pixels()
    if pixels.isNil:
      ""
    else:
      pixels.encodePng()
  else:
    ""

proc addClipboardConverter(
    content: var siwinClipboards.ClipboardConvertableContent,
    kind: siwinClipboards.ClipboardContentKind,
    mimeType = "",
) =
  for entry in content.converters:
    if entry.kind == kind and entry.mimeType == mimeType:
      return
  content.converters.add siwinClipboards.ClipboardContentConverter(
    kind: kind,
    mimeType: mimeType,
    f: proc(
        data: ref RootObj, kind: siwinClipboards.ClipboardContentKind, mimeType: string
    ): siwinClipboards.ClipboardContent =
      case kind
      of siwinClipboards.ClipboardContentKind.text:
        let item = itemForPayload(data, PasteboardTypeString)
        siwinClipboards.ClipboardContent(
          kind: siwinClipboards.ClipboardContentKind.text,
          text: if item.kind == pikString: item.stringValue else: "",
        )
      of siwinClipboards.ClipboardContentKind.files:
        siwinClipboards.ClipboardContent(
          kind: siwinClipboards.ClipboardContentKind.files, files: payloadFiles(data)
        )
      of siwinClipboards.ClipboardContentKind.other:
        siwinClipboards.ClipboardContent(
          kind: siwinClipboards.ClipboardContentKind.other,
          mimeType: mimeType,
          data: payloadOtherData(data, mimeType),
        ),
  )

proc publishHostClipboard(provider: NativePasteboardProvider) =
  let host = provider.readyHost()
  if not host.hostReady:
    return
  provider.ensureItems()
  var content: siwinClipboards.ClipboardConvertableContent
  content.data = NativePasteboardPayload(items: provider.copyItems())
  if PasteboardTypeString in provider.xItems and
      provider.xItems[PasteboardTypeString].kind == pikString:
    content.addClipboardConverter(siwinClipboards.ClipboardContentKind.text)

  var hasFileItem = false
  for item in provider.xItems.values:
    if item.kind == pikFile or item.kind == pikUrl and item.url.startsWith("file://"):
      hasFileItem = true
  if hasFileItem:
    content.addClipboardConverter(siwinClipboards.ClipboardContentKind.files)

  for kind, item in provider.xItems:
    case item.kind
    of pikData:
      content.addClipboardConverter(siwinClipboards.ClipboardContentKind.other, kind)
    of pikUrl:
      content.addClipboardConverter(siwinClipboards.ClipboardContentKind.other, kind)
    of pikImage:
      content.addClipboardConverter(
        siwinClipboards.ClipboardContentKind.other, NativeImagePngType
      )
      content.addClipboardConverter(siwinClipboards.ClipboardContentKind.other, kind)
    else:
      discard

  when defined(useNativeDynlib):
    host.xNativeWindow.clipboard.clipboardText = ""
    host.xNativeWindow.clipboard.clipboardFiles = payloadFiles(content.data)
    for kind, item in provider.xItems:
      case item.kind
      of pikString:
        if kind == PasteboardTypeString:
          host.xNativeWindow.clipboard.clipboardText = item.stringValue
        else:
          host.xNativeWindow.clipboard.setClipboardData(kind, item.stringValue)
      of pikFile:
        host.xNativeWindow.clipboard.setClipboardData(kind, item.filePath)
      of pikUrl:
        host.xNativeWindow.clipboard.setClipboardData(kind, item.url)
      of pikData:
        host.xNativeWindow.clipboard.setClipboardData(kind, item.data)
      of pikImage:
        let data = payloadOtherData(content.data, kind)
        host.xNativeWindow.clipboard.setClipboardData(kind, data)
        host.xNativeWindow.clipboard.setClipboardData(NativeImagePngType, data)
      else:
        discard
  else:
    if content.converters.len > 0:
      host.xNativeWindow.clipboard.content = content
    else:
      host.xNativeWindow.clipboard.clipboardText = ""

proc storeItem(
    provider: NativePasteboardProvider, kind: string, item: PasteboardItem
): bool =
  if kind.len == 0 or item.kind == pikNone:
    return false
  provider.ensureItems()
  provider.addType(kind)
  provider.xItems[kind] = item.copyPasteboardItem()
  inc provider.xChangeCount
  provider.publishHostClipboard()
  provider.observeHostChangeCount()
  true

proc nativeItemForType(
    provider: NativePasteboardProvider, kind: string
): PasteboardItem =
  let host = provider.readyHost()
  if not host.hostReady or kind.len == 0:
    return PasteboardItem(kind: pikNone)
  let clipboard = host.xNativeWindow.clipboard
  case kind
  of PasteboardTypeString:
    let value = clipboard.clipboardText
    if value.len > 0 or kind in clipboard.availableMimeTypes:
      return initPasteboardStringItem(value)
  of PasteboardTypeFile:
    let files = clipboard.clipboardFiles
    if files.len > 0:
      return initPasteboardFileItem(files[0])
  of PasteboardTypeUrl:
    let url = clipboard.clipboardData(PasteboardTypeUrl)
    if url.len > 0 or PasteboardTypeUrl in clipboard.availableMimeTypes:
      return initPasteboardUrlItem(url)
    let files = clipboard.clipboardFiles
    if files.len > 0:
      return initPasteboardUrlItem("file://" & files[0])
  of PasteboardTypeData:
    let data = clipboard.clipboardData(kind)
    if data.len > 0 or kind in clipboard.availableMimeTypes:
      return initPasteboardDataItem(data)
  of PasteboardTypeImage:
    var data = clipboard.clipboardData(NativeImagePngType)
    if data.len == 0:
      data = clipboard.clipboardData(PasteboardTypeImage)
    if data.len > 0:
      try:
        return initPasteboardImageItem(newImageResourceFromData(data))
      except CatchableError:
        discard
  else:
    let data = clipboard.clipboardData(kind)
    if data.len > 0 or kind in clipboard.availableMimeTypes:
      return initPasteboardDataItem(data)
  PasteboardItem(kind: pikNone)

proc clearStoredItems(provider: NativePasteboardProvider) =
  provider.ensureItems()
  provider.xTypes.setLen(0)
  provider.xItems.clear()
  inc provider.xChangeCount
  provider.publishHostClipboard()
  provider.observeHostChangeCount()

protocol NativePasteboardProviderProtocol of PasteboardProviderProtocol:
  method pasteboardTypes(
      provider: NativePasteboardProvider, pasteboard: Pasteboard
  ): seq[string] =
    discard provider.syncExternalHostChanges()
    provider.ensureItems()
    for kind in provider.xTypes:
      result.addType(kind)
    for kind in provider.hostTypes():
      result.addType(kind)

  method pasteboardChangeCount(
      provider: NativePasteboardProvider, pasteboard: Pasteboard
  ): int =
    let hostCount = provider.syncExternalHostChanges()
    if hostCount.isSome:
      max(provider.xChangeCount, hostCount.get())
    else:
      provider.xChangeCount

  method pasteboardItemForType(
      provider: NativePasteboardProvider, request: PasteboardTypeRequest
  ): PasteboardItem =
    discard provider.syncExternalHostChanges()
    let nativeItem = provider.nativeItemForType(request.kind)
    if nativeItem.kind != pikNone:
      return nativeItem
    provider.ensureItems()
    if request.kind in provider.xItems:
      return provider.xItems[request.kind].copyPasteboardItem()

  method stringForPasteboardType(
      provider: NativePasteboardProvider, request: PasteboardTypeRequest
  ): string =
    discard provider.syncExternalHostChanges()
    let host = provider.readyHost()
    if host.hostReady and request.kind == PasteboardTypeString:
      return host.xNativeWindow.clipboard.clipboardText

  method setStringForPasteboardType(
      provider: NativePasteboardProvider, request: PasteboardStringRequest
  ): bool =
    provider.storeItem(request.kind, initPasteboardStringItem(request.value))

  method setPasteboardItemForType(
      provider: NativePasteboardProvider, request: PasteboardItemRequest
  ): bool =
    provider.storeItem(request.kind, request.item)

  method clearPasteboardContents(
      provider: NativePasteboardProvider, pasteboard: Pasteboard
  ): bool =
    provider.clearStoredItems()
    true

  method releasePasteboard(
      provider: NativePasteboardProvider, pasteboard: Pasteboard
  ): bool =
    provider.clearStoredItems()
    true

proc installNativeClipboardBridge(host: HostWindow) =
  if nativePasteboardProvider.isNil:
    nativePasteboardProvider = NativePasteboardProvider()
    nativePasteboardProvider.ensureItems()
    discard nativePasteboardProvider.withProtocol(NativePasteboardProviderProtocol)
  nativePasteboardProvider.xHost = host
  generalPasteboard().provider = nativePasteboardProvider

proc hostForNativeWindow(
    nativeWindow: siwinshim.Window, fallbackKey: pointer
): HostWindow =
  ensureHostRegistry()
  let key = if nativeWindow.isNil: fallbackKey else: nativeWindow.nativeWindowKey
  if key.isNil or key notin hostWindows:
    return nil
  hostWindows[key]

proc toNimkitMouseButton(button: siwinshim.MouseButton): events.MouseButton =
  case button
  of siwinshim.MouseButton.left: events.mbPrimary
  of siwinshim.MouseButton.right: events.mbSecondary
  else: events.mbOther

proc toNimkitModifiers(modifiers: set[siwinshim.ModifierKey]): set[events.KeyModifier] =
  if siwinshim.ModifierKey.shift in modifiers:
    result.incl events.kmShift
  if siwinshim.ModifierKey.control in modifiers:
    result.incl events.kmControl
  if siwinshim.ModifierKey.alt in modifiers:
    result.incl events.kmOption
  if siwinshim.ModifierKey.system in modifiers:
    result.incl events.kmCommand

proc toNimkitKey(key: siwinshim.Key): events.Key =
  if key.ord < ord(low(events.Key)) or key.ord > ord(high(events.Key)):
    return events.keyUnknown
  events.Key(key.ord)

proc keyText(key: siwinshim.Key): string =
  case key
  of siwinshim.Key.enter: "\n"
  of siwinshim.Key.tab: "\t"
  else: ""

proc isModifierKey(key: events.Key): bool =
  key in {
    events.keyLeftControl, events.keyRightControl, events.keyLeftShift,
    events.keyRightShift, events.keyLeftOption, events.keyRightOption,
    events.keyLeftCommand, events.keyRightCommand,
  }

proc rawInputToLogical*(rawPos: Vec2, inputSize: IVec2, logicalSize: Vec2): Vec2 =
  if inputSize.x <= 0 or inputSize.y <= 0:
    return rawPos
  if logicalSize.x <= 0.0 or logicalSize.y <= 0.0:
    return rawPos
  vec2(
    rawPos.x * logicalSize.x / inputSize.x.float32,
    rawPos.y * logicalSize.y / inputSize.y.float32,
  )

proc hostLogicalSize(host: HostWindow, window: siwinshim.Window): Vec2 =
  if window.isNil:
    return vec2(0.0'f32, 0.0'f32)
  if host.usesScaledBackingSize(window):
    return host.logicalSizeForBacking(window)
  window.logicalSize()

proc nativeMousePoint(host: HostWindow, window: siwinshim.Window): Point =
  # siwin mouse.pos is reported in window.size coordinates, which may lag
  # backingSize on Cocoa until resize/backing notifications are delivered.
  let pos =
    rawInputToLogical(window.mouse.pos, window.size(), host.hostLogicalSize(window))
  initPoint(pos.x.float32, pos.y.float32)

proc nativeMousePoint(host: HostWindow, window: siwinshim.Window, rawPos: Vec2): Point =
  let pos = rawInputToLogical(rawPos, window.size(), host.hostLogicalSize(window))
  initPoint(pos.x.float32, pos.y.float32)

proc nativeModifiers(window: siwinshim.Window): set[events.KeyModifier] =
  window.keyboard.modifiers.toNimkitModifiers

proc activeMouseButton(window: siwinshim.Window): events.MouseButton =
  if siwinshim.MouseButton.left in window.mouse.pressed:
    return events.mbPrimary
  if siwinshim.MouseButton.right in window.mouse.pressed:
    return events.mbSecondary
  if window.mouse.pressed.len > 0:
    return events.mbOther
  return events.mbPrimary

proc isReady*(host: HostWindow): bool =
  host.hostReady

proc nativeWindowOrNil*(host: HostWindow): siwinshim.Window =
  host.xNativeWindow

proc rendererOrNil*(
    host: HostWindow
): figrender.FigRenderer[siwinshim.SiwinRenderBackend] =
  host.xRenderer

proc renderRequested*(host: HostWindow): bool =
  host.xRenderRequested

proc renderCount*(host: HostWindow): Natural =
  host.xRenderCount

proc resourceMetrics*(host: HostWindow): RenderResourceMetrics =
  if not host.isNil:
    result = host.xResources.metrics()

proc requestRender*(host: HostWindow) =
  if host.xRenderRequested:
    return
  host.xRenderRequested = true
  if host.isReady and not host.xNativeWindow.isNil:
    host.xNativeWindow.redraw()

proc contentScale*(host: HostWindow): float32 =
  if host.xHasUiScaleOverride:
    return host.xUiScaleOverride
  if not host.isReady:
    return 1.0'f32
  max(host.xNativeWindow.contentScale(), 1.0'f32)

proc refreshContentScale*(host: HostWindow) =
  if host.xHasUiScaleOverride:
    setFigUiScale(host.xUiScaleOverride)
  elif host.isReady:
    host.xNativeWindow.refreshUiScale(host.xAutoScale)

proc markClosed(host: HostWindow, notify: bool) =
  let callbacks = host.xCallbacks
  host.unregisterHost()
  if not nativePasteboardProvider.isNil and nativePasteboardProvider.xHost == host:
    nativePasteboardProvider.xHost = firstReadyHost()
  host.xReady = false
  host.xRenderRequested = false
  if notify and not callbacks.onClose.isNil:
    callbacks.onClose()

proc logicalSize*(host: HostWindow, fallback: Size): Size =
  if not host.isReady:
    return initSize(max(fallback.width, 1.0'f32), max(fallback.height, 1.0'f32))

  if host.usesScaledBackingSize(host.xNativeWindow):
    let nativeSize = host.logicalSizeForBacking(host.xNativeWindow)
    return initSize(max(nativeSize.x, 1.0'f32), max(nativeSize.y, 1.0'f32))

  let nativeSize = host.xNativeWindow.logicalSize()
  if nativeSize.x <= 0.0'f32 or nativeSize.y <= 0.0'f32:
    return initSize(max(fallback.width, 1.0'f32), max(fallback.height, 1.0'f32))
  initSize(nativeSize.x, nativeSize.y)

proc nativeSizeScale(host: HostWindow): float32 =
  if host.xHasUiScaleOverride or host.usesScaledBackingSize(host.xNativeWindow):
    host.configuredUiScale()
  else:
    1.0'f32

proc setLogicalSize*(host: HostWindow, size: Size) =
  if not host.isReady:
    return
  host.xNativeWindow.size = nativeWindowSize(size, host.nativeSizeScale())

proc setMinimumSize*(host: HostWindow, size: Size) =
  if not host.isReady:
    return
  let
    scale = host.nativeSizeScale()
    nativeSize =
      ivec2(nativeWindowLimit(size.width, scale), nativeWindowLimit(size.height, scale))
  host.xNativeWindow.minSize = nativeSize

proc setMaximumSize*(host: HostWindow, size: Size) =
  if not host.isReady:
    return
  let
    scale = host.nativeSizeScale()
    nativeSize =
      ivec2(nativeWindowLimit(size.width, scale), nativeWindowLimit(size.height, scale))
  host.xNativeWindow.maxSize = nativeSize

proc setTitle*(host: HostWindow, title: string) =
  if host.isReady:
    host.xNativeWindow.title = title

proc setVisible*(host: HostWindow, visible: bool) =
  if not host.isReady:
    return
  if visible and host.xNativeWindow.visible() and not host.xNativeWindow.focused():
    host.xNativeWindow.visible = false
  host.xResources.setVisible(visible)
  host.xNativeWindow.visible = visible

proc render*(
    host: HostWindow,
    renders: var Renders,
    logicalSize: Size,
    resources = default(FrozenRenderResources),
) =
  if not host.isReady or host.xRenderer.isNil or not host.xNativeWindow.opened():
    return
  host.xRenderRequested = false
  host.refreshContentScale()
  host.xResources.commit(resources)
  host.xResources.prepare(host.xRenderer)
  let size = vec2(logicalSize.width, logicalSize.height)
  host.xRenderer.beginFrame()
  if host.xTransparent:
    host.xRenderer.renderFrame(renders, size, clearColor = clearColor)
  else:
    host.xRenderer.renderFrame(renders, size)
  host.xRenderer.endFrame()
  inc host.xRenderCount

proc configureTransparentPresentation(host: HostWindow) =
  if not host.xTransparent or host.xRenderer.isNil:
    return
  when defined(macosx) and not defined(useNativeDynlib):
    if host.xNativeWindow of siwinshim.WindowCocoa:
      let nativeWindow =
        cast[NSWindow](siwinshim.WindowCocoa(host.xNativeWindow).nativeWindowHandle())
      if not nativeWindow.isNil:
        nativeWindow.setOpaque(false)
        nativeWindow.setBackgroundColor(NSColor.clearColor())
    when compiles(host.xRenderer.backendState.metalLayer.layer):
      if not host.xRenderer.backendState.metalLayer.layer.isNil:
        host.xRenderer.backendState.metalLayer.setOpaque(false)
    when compiles(host.xRenderer.backendState.vulkanMetalLayer.layer):
      if not host.xRenderer.backendState.vulkanMetalLayer.layer.isNil:
        host.xRenderer.backendState.vulkanMetalLayer.setOpaque(false)

proc close*(host: HostWindow) =
  let nativeWindow = host.xNativeWindow
  let shouldClose = not nativeWindow.isNil and not nativeWindow.closed()
  host.xResources.clear()
  if not host.xRenderer.isNil:
    host.xRenderer.processImageMessages()
  host.markClosed(notify = false)
  if shouldClose:
    siwinshim.close(nativeWindow)

proc dispatchMouseButton(host: HostWindow, event: siwinshim.MouseButtonEvent) =
  let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
  if nativeWindow.isNil or host.xCallbacks.onMouseButton.isNil:
    return
  host.xCallbacks.onMouseButton(
    events.MouseEvent(
      location: host.nativeMousePoint(nativeWindow),
      button: event.button.toNimkitMouseButton,
      clickCount: 0,
      modifiers: nativeWindow.nativeModifiers,
      timestamp: epochTime(),
    ),
    event.pressed,
  )

proc dispatchMouseMove(host: HostWindow, event: siwinshim.MouseMoveEvent) =
  let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
  if nativeWindow.isNil or host.xCallbacks.onMouseMove.isNil:
    return
  let dragging =
    event.kind == siwinshim.MouseMoveKind.moveWhileDragging or
    nativeWindow.mouse.pressed != {}
  host.xCallbacks.onMouseMove(
    events.MouseEvent(
      location: host.nativeMousePoint(nativeWindow, event.pos),
      button: nativeWindow.activeMouseButton,
      clickCount: 0,
      modifiers: nativeWindow.nativeModifiers,
      timestamp: epochTime(),
    ),
    dragging,
  )

proc dispatchScroll(host: HostWindow, event: siwinshim.ScrollEvent) =
  let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
  if nativeWindow.isNil or host.xCallbacks.onScroll.isNil:
    return
  host.xCallbacks.onScroll(
    events.ScrollEvent(
      location: host.nativeMousePoint(nativeWindow),
      deltaX: event.deltaX.float32,
      deltaY: event.delta.float32,
      phase: sepChanged,
      modifiers: nativeWindow.nativeModifiers,
      timestamp: epochTime(),
    )
  )

proc dispatchKey(host: HostWindow, event: siwinshim.KeyEvent) =
  if host.xCallbacks.onKey.isNil:
    return
  let key = event.key.toNimkitKey
  host.xCallbacks.onKey(
    HostKeyEvent(
      event: events.KeyEvent(
        text: event.key.keyText,
        key: key,
        keyCode: event.key.ord,
        modifiers: event.modifiers.toNimkitModifiers,
        repeated: event.repeated,
      ),
      pressed: event.pressed,
      isEscape: event.key == siwinshim.Key.escape,
      isModifierChange: key.isModifierKey,
    )
  )

proc dispatchTextInput(host: HostWindow, event: siwinshim.TextInputEvent) =
  if event.text.len > 0 and not host.xCallbacks.onTextInput.isNil:
    host.xCallbacks.onTextInput(event.text)

proc installEventHandlers(host: HostWindow) =
  if host.xNativeWindow.isNil:
    return
  let ownerKey = host.xOwnerKey
  host.xNativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
    onClose: proc(event: siwinshim.CloseEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.markClosed(notify = true)
    ,
    onPopupDone: proc(event: siwinshim.PopupEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      host.markClosed(notify = false)
      if not host.xCallbacks.onPopupDone.isNil:
        host.xCallbacks.onPopupDone()
    ,
    onResize: proc(event: siwinshim.ResizeEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      let nativeWindow = if event.window.isNil: host.xNativeWindow else: event.window
      if nativeWindow.isNil:
        return
      host.refreshContentScale()
      if not host.xCallbacks.onResize.isNil:
        host.xCallbacks.onResize()
      if not host.xCallbacks.onRender.isNil:
        host.xCallbacks.onRender()
      siwinshim.presentNow(nativeWindow),
    onWindowMove: proc(event: siwinshim.WindowMoveEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil and not host.xCallbacks.onMove.isNil:
        host.xCallbacks.onMove(initPoint(event.pos.x.float32, event.pos.y.float32))
    ,
    onMouseButton: proc(event: siwinshim.MouseButtonEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchMouseButton(event)
    ,
    onMouseMove: proc(event: siwinshim.MouseMoveEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchMouseMove(event)
    ,
    onScroll: proc(event: siwinshim.ScrollEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchScroll(event)
    ,
    onRender: proc(event: siwinshim.RenderEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil and not host.xCallbacks.onRender.isNil:
        host.xCallbacks.onRender()
    ,
    onKey: proc(event: siwinshim.KeyEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchKey(event)
    ,
    onTextInput: proc(event: siwinshim.TextInputEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if not host.isNil:
        host.dispatchTextInput(event)
    ,
    onStateBoolChanged: proc(event: siwinshim.StateBoolChangedEvent) =
      let host = hostForNativeWindow(event.window, ownerKey)
      if event.kind == siwinshim.StateBoolChangedEventKind.focus and
          not host.xCallbacks.onFocusChanged.isNil:
        host.xCallbacks.onFocusChanged(event.value)
    ,
  )

proc createHostWindow*(
    frame: Rect, title: string, callbacks: HostWindowCallbacks
): HostWindow =
  let
    scaleOverride = uiScaleOverrideFromEnv()
    size = nativeWindowSize(frame.size, scaleOverride.overrideScale())
  result = HostWindow(xCallbacks: callbacks, xResources: newRenderResourceManager())
  result.xNativeWindow =
    siwinshim.newSiwinWindow(size = size, title = title, vsync = true, resizable = true)
  result.xRenderer = figrender.newFigRenderer(
    atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
  )
  result.xRenderer.setupBackend(result.xNativeWindow)
  result.xNativeWindow.pos = ivec2(frame.origin.x.int32, frame.origin.y.int32)
  result.configureHostUiScale(scaleOverride)
  if scaleOverride.isNone and result.usesScaledBackingSize(result.xNativeWindow):
    result.xNativeWindow.size = nativeWindowSize(frame.size, result.configuredUiScale())
  result.configureTransparentPresentation()
  result.registerHost()
  result.installNativeClipboardBridge()
  result.installEventHandlers()

  result.xNativeWindow.firstStep()
  result.xNativeWindow.refreshUiScale(result.xAutoScale)
  result.xReady = true

proc createPopupHostWindow*(
    owner: HostWindow,
    placement: siwinshim.PopupPlacement,
    callbacks: HostWindowCallbacks,
): HostWindow =
  if not owner.isReady:
    return nil

  let scaleOverride =
    if owner.xHasUiScaleOverride:
      some(UiScaleOverride(scale: owner.xUiScaleOverride))
    else:
      none(UiScaleOverride)

  result = HostWindow(
    xCallbacks: callbacks, xTransparent: true, xResources: newRenderResourceManager()
  )
  when defined(useNativeDynlib):
    result.xNativeWindow = siwinshim.newPopupWindow(
      owner.xNativeWindow, placement, transparent = true, grab = true
    )
  else:
    result.xNativeWindow = siwinshim.sharedSiwinGlobals().newPopupWindow(
        owner.xNativeWindow, placement, transparent = true, grab = true
      )
  result.configureHostUiScale(scaleOverride)
  result.xRenderer = figrender.newFigRenderer(
    atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
  )
  result.xRenderer.setupBackend(result.xNativeWindow)
  result.configureTransparentPresentation()
  result.registerHost()
  result.installEventHandlers()
  result.xNativeWindow.firstStep(makeVisible = true)
  result.xNativeWindow.reposition(placement)
  result.xNativeWindow.refreshUiScale(result.xAutoScale)
  result.xReady = true

proc pump*(host: HostWindow) =
  if not host.isReady:
    return
  let nativeWindow = host.xNativeWindow
  if nativeWindow.isNil or not nativeWindow.opened():
    return
  if not host.xRenderer.isNil:
    host.xRenderer.processImageMessages()
  if host.xRenderRequested:
    nativeWindow.redraw()
  nativeWindow.step()
  if host.isReady and nativeWindow.closed():
    host.markClosed(notify = true)

proc postEvent(state: ThreadRendererHost, event: sink ThreadHostEvent) =
  if not state.isNil:
    state.channels.events.post(ensureMove event)

proc acceptPendingRender(state: ThreadRendererHost): bool =
  if state.isNil:
    return
  var snapshot: ThreadRenderSnapshot
  if not state.channels.pollLatestRender(snapshot):
    return
  state.lastRenders = move snapshot.renders
  state.lastResources = move snapshot.resources
  true

proc renderLatest(state: ThreadRendererHost) =
  if state.isNil or state.host.isNil or state.lastRenders.isNil:
    return
  let previousCount = state.host.renderCount()
  state.host.render(state.lastRenders, state.logicalSize, state.lastResources)
  if state.host.renderCount() != previousCount:
    state.postEvent(
      ThreadHostEvent(kind: theRendered, renderCount: state.host.renderCount())
    )

proc createRendererHost(
    renderer: ThreadRenderer, request: sink ThreadHostCreateRequest
) =
  if request.id in renderer.hosts:
    return

  let state = ThreadRendererHost(
    id: request.id, channels: request.channels, logicalSize: request.frame.size
  )
  let callbacks = HostWindowCallbacks(
    onClose: proc() =
      state.postEvent(ThreadHostEvent(kind: theClosed)),
    onResize: proc() =
      if not state.host.isNil:
        let size = state.host.logicalSize(state.logicalSize)
        state.logicalSize = size
        state.postEvent(ThreadHostEvent(kind: theResized, size: size))
    ,
    onMove: proc(pos: Point) =
      state.postEvent(ThreadHostEvent(kind: theMoved, point: pos)),
    onMouseButton: proc(event: events.MouseEvent, pressed: bool) =
      state.postEvent(
        ThreadHostEvent(kind: theMouseButton, mouseEvent: event, flag: pressed)
      ),
    onMouseMove: proc(event: events.MouseEvent, dragging: bool) =
      state.postEvent(
        ThreadHostEvent(kind: theMouseMove, mouseEvent: event, flag: dragging)
      ),
    onScroll: proc(event: events.ScrollEvent) =
      state.postEvent(ThreadHostEvent(kind: theScroll, scrollEvent: event)),
    onKey: proc(event: HostKeyEvent) =
      state.postEvent(ThreadHostEvent(kind: theKey, keyEvent: event)),
    onTextInput: proc(text: string) =
      state.postEvent(ThreadHostEvent(kind: theTextInput, text: text)),
    onRender: proc() =
      # Native live-resize runs its own event loop. Consume the worker's newest
      # snapshot here because the outer renderer loop cannot drain it meanwhile.
      discard state.acceptPendingRender()
      state.renderLatest(),
    onFocusChanged: proc(focused: bool) =
      state.postEvent(ThreadHostEvent(kind: theFocusChanged, flag: focused)),
    onPopupDone: proc() =
      state.postEvent(ThreadHostEvent(kind: thePopupDone)),
  )

  if request.isPopup:
    if request.ownerId notin renderer.hosts:
      state.postEvent(ThreadHostEvent(kind: theClosed))
      return
    let owner = renderer.hosts[request.ownerId].host
    state.host = createPopupHostWindow(owner, request.popupPlacement, callbacks)
  else:
    state.host = createHostWindow(request.frame, request.title, callbacks)

  if state.host.isNil:
    state.postEvent(ThreadHostEvent(kind: theClosed))
    return

  renderer.hosts[state.id] = state
  state.logicalSize = state.host.logicalSize(request.frame.size)
  state.postEvent(
    ThreadHostEvent(
      kind: theReady, size: state.logicalSize, contentScale: state.host.contentScale()
    )
  )

proc applyHostCommand(state: ThreadRendererHost, command: sink ThreadHostCommand) =
  if state.isNil or state.host.isNil:
    return
  case command.kind
  of thcRequestRender:
    state.host.requestRender()
  of thcSetLogicalSize:
    state.logicalSize = command.size
    state.host.setLogicalSize(command.size)
  of thcSetMinimumSize:
    state.host.setMinimumSize(command.size)
  of thcSetMaximumSize:
    state.host.setMaximumSize(command.size)
  of thcSetTitle:
    state.host.setTitle(command.title)
  of thcSetVisible:
    state.host.setVisible(command.visible)
  of thcClose:
    state.host.close()

proc drainHostChannels(state: ThreadRendererHost) =
  var command: ThreadHostCommand
  while state.channels.commands.tryRecv(command):
    state.applyHostCommand(move command)

  # The host's logical size is authoritative. A render snapshot can lag one
  # native resize event while the application thread lays out its view tree.
  if state.acceptPendingRender():
    state.renderLatest()

proc postMenuEvent(
    events: Chan[ThreadMenuEvent],
    kind: ThreadMenuEventKind,
    menu: ThreadMenuId = 0,
    item: ThreadMenuId = 0,
) =
  events.sendMoved(ThreadMenuEvent(kind: kind, menu: menu, item: item))

proc nativeMenuDescription(
    menu: ThreadNativeMenu, events: Chan[ThreadMenuEvent]
): nativeMenus.NativeMenuDescription =
  if menu.id == 0:
    return nil

  let frozenMenu = menu
  result = nativeMenus.NativeMenuDescription(
    identity: cast[pointer](menu.id), title: menu.title
  )
  result.refresh = proc(): nativeMenus.NativeMenuDescription =
    events.postMenuEvent(tmeRefresh, frozenMenu.id)
    frozenMenu.nativeMenuDescription(events)
  result.didClose = proc() =
    events.postMenuEvent(tmeClose, frozenMenu.id)

  for item in menu.items:
    let frozenItem = item
    var description = nativeMenus.NativeMenuItemDescription(
      title: item.title,
      separator: item.separator,
      enabled: item.enabled,
      hidden: item.hidden,
      state: item.state,
      tag: item.tag,
      keyEquivalent: item.keyEquivalent,
      modifiers: item.modifiers,
    )
    if item.submenu.id != 0:
      description.submenu = item.submenu.nativeMenuDescription(events)
    elif item.id != 0:
      description.activate = proc() =
        events.postMenuEvent(tmeActivate, frozenMenu.id, frozenItem.id)
    result.items.add description

proc installNativeMenu(
    renderer: ThreadRenderer, snapshot: sink ThreadNativeMenuSnapshot
) =
  if not snapshot.installed:
    nativeMenus.installNativeMenus(nil, nil, nil)
    return
  nativeMenus.installNativeMenus(
    snapshot.menu.nativeMenuDescription(renderer.menuEvents),
    cast[pointer](snapshot.windowsMenu),
    cast[pointer](snapshot.servicesMenu),
  )

proc drainRendererCommands(renderer: ThreadRenderer) =
  var command: ThreadRendererCommand
  while renderer.commands.tryRecv(command):
    case command.kind
    of trcCreateHost:
      renderer.createRendererHost(move command.create)
    of trcSetNativeMenu:
      renderer.installNativeMenu(move command.menu)
    of trcShowAboutPanel:
      nativeMenus.showStandardAboutPanel()
    of trcHideOtherApplications:
      nativeMenus.hideOtherNativeApplications()
    of trcUnhideAllApplications:
      nativeMenus.unhideAllNativeApplications()
    of trcQuit:
      renderer.running = false

proc run*(renderer: ThreadRenderer) =
  if renderer.isNil:
    return
  renderer.running = true
  while renderer.running:
    renderer.drainRendererCommands()
    for state in renderer.hosts.values:
      state.drainHostChannels()
      if not state.host.isNil:
        state.host.pump()
    sleep(1)

  for state in renderer.hosts.values:
    if not state.host.isNil:
      state.host.close()
  renderer.hosts.clear()
  nativeMenus.installNativeMenus(nil, nil, nil)
