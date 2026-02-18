import std/[math, os, strutils, unicode]
import pkg/chroma
import pkg/vmath

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim as siwinshim

import ../objc
import ../objc/ivar
import ./types

type
  NSButtonCallbackProc = proc(sender: ID) {.gcsafe.}

  NSViewStateRef = ref object
    frame: NSRect
    backgroundColor: NSColor
    hidden: bool
    subviews: seq[ID]

  NSControlStateRef = ref object
    enabled: bool

  NSTextFieldStateRef = ref object
    stringValue: string
    textColor: NSColor

  NSButtonStateRef = ref object
    title: string
    onClick: NSButtonCallbackProc

  NSWindowStateRef = ref object
    frame: NSRect
    title: string
    contentView: ID
    nativeWindow: siwinshim.Window
    renderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    autoScale: bool
    nativeReady: bool
    visibleRequested: bool
    closed: bool

  NSApplicationStateRef = ref object
    windows: seq[ID]
    running: bool

proc defaultViewState(): NSViewStateRef =
  NSViewStateRef(
    frame: nsRect(0, 0, 100, 100),
    backgroundColor: nsColor(0.90, 0.90, 0.90, 1.0),
    hidden: false,
    subviews: @[],
  )

proc defaultControlState(): NSControlStateRef =
  NSControlStateRef(enabled: true)

proc defaultTextFieldState(): NSTextFieldStateRef =
  NSTextFieldStateRef(stringValue: "", textColor: nsColor(0.08, 0.08, 0.08, 1.0))

proc defaultButtonState(): NSButtonStateRef =
  NSButtonStateRef(title: "Button", onClick: nil)

proc defaultWindowState(): NSWindowStateRef =
  NSWindowStateRef(
    frame: nsRect(100, 100, 640, 420),
    title: "Nutella Window",
    contentView: nil,
    nativeWindow: nil,
    renderer: nil,
    autoScale: true,
    nativeReady: false,
    visibleRequested: false,
    closed: false,
  )

proc defaultApplicationState(): NSApplicationStateRef =
  NSApplicationStateRef(windows: @[], running: false)

proc toFigColor(c: NSColor): Color {.inline.} =
  color(c.r, c.g, c.b, c.a)

var appkitTypefaceId {.threadvar.}: TypefaceId
var appkitFontReady {.threadvar.}: bool
var appkitFontUnavailable {.threadvar.}: bool

proc appkitFontCandidates(): seq[string] =
  result = @["Ubuntu.ttf", "HackNerdFont-Regular.ttf"]
  let dir = figDataDir()
  if not dirExists(dir):
    return
  for kind, path in walkDir(dir):
    if kind != pcFile:
      continue
    let (_, name, ext) = splitFile(path)
    let lowerExt = ext.toLowerAscii()
    if lowerExt notin [".ttf", ".otf"]:
      continue
    let fileName = name & ext
    if fileName notin result:
      result.add(fileName)

proc ensureAppKitFont(): bool =
  if appkitFontReady:
    return true
  if appkitFontUnavailable:
    return false
  for candidate in appkitFontCandidates():
    try:
      appkitTypefaceId = loadTypeface(candidate)
      appkitFontReady = true
      return true
    except Exception:
      discard
  appkitFontUnavailable = true
  false

proc appkitFont(size: float32): FigFont {.inline.} =
  appkitTypefaceId.fontWithSize(size)

proc uniformCorners(radius: float32): array[DirectionCorners, float32] {.inline.} =
  [radius, radius, radius, radius]

proc clampWindowSize(v: float32): int32 {.inline.} =
  if v < 1.0: 1 else: v.round.int32

proc ownFromId[T: NSObject](id: ID): T =
  if id.isNil:
    return T(value: nil)
  var borrowed = asType[T](id)
  result = retain(borrowed)
  borrowed.value = nil

proc retainId(id: ID): ID =
  if id.isNil:
    return nil
  var borrowed = asType[NSObject](id)
  var owned = retain(borrowed)
  borrowed.value = nil
  result = owned.value
  owned.value = nil

proc releaseId(id: ID) =
  if id.isNil:
    return
  var owned = asType[NSObject](id)
  discard owned

proc replaceOwnedId(slot: var ID, next: ID) =
  if slot == next:
    return
  let old = slot
  slot = retainId(next)
  releaseId(old)

proc clearOwnedIds(ids: var seq[ID]) =
  for id in ids:
    releaseId(id)
  ids.setLen(0)

proc removeOwnedIdAt(ids: var seq[ID], idx: int) =
  let old = ids[idx]
  ids.del(idx)
  releaseId(old)

proc runApplicationFrames(appObj: NSObject, maxFrames: int): int

objcImpl:
  type NUResponderObj = object of NSObject

objcImpl:
  type NUViewObj = object of NUResponderObj
    viewStateRef: NSViewStateRef

  method init*(self: var NUViewObj): NUViewObj =
    result = asType[NUViewObj](super(self, init))
    self.value = nil
    if result.isNil:
      return
    if result.viewStateRef().isNil:
      result.viewStateRef = defaultViewState()

  method initWithFrame*(self: var NUViewObj, x, y, width, height: cfloat): NUViewObj =
    result = self.init()
    if result.isNil:
      return
    var st = result.viewStateRef()
    if st.isNil:
      st = defaultViewState()
      result.viewStateRef = st
    st.frame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setFrame*(self: NUViewObj, x, y, width, height: cfloat) =
    var st = self.viewStateRef()
    if st.isNil:
      st = defaultViewState()
      self.viewStateRef = st
    st.frame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setBackgroundColor*(self: NUViewObj, r, g, b, a: cfloat) =
    var st = self.viewStateRef()
    if st.isNil:
      st = defaultViewState()
      self.viewStateRef = st
    st.backgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setHidden*(self: NUViewObj, hidden: bool) =
    var st = self.viewStateRef()
    if st.isNil:
      st = defaultViewState()
      self.viewStateRef = st
    st.hidden = hidden

  method dealloc(self: NUViewObj) {.used.} =
    let st = self.viewStateRef()
    if not st.isNil:
      clearOwnedIds(st.subviews)
    clearIvarRefs(self)
    superDealloc(self)

objcImpl:
  type NUControlObj = object of NUViewObj
    controlStateRef: NSControlStateRef

  method init*(self: var NUControlObj): NUControlObj =
    result = asType[NUControlObj](super(self, init))
    self.value = nil
    if result.isNil:
      return
    if result.controlStateRef().isNil:
      result.controlStateRef = defaultControlState()

  method setEnabled*(self: NUControlObj, enabled: bool) =
    var st = self.controlStateRef()
    if st.isNil:
      st = defaultControlState()
      self.controlStateRef = st
    st.enabled = enabled

objcImpl:
  type NUTextFieldObj = object of NUControlObj
    textFieldStateRef: NSTextFieldStateRef

  method init*(self: var NUTextFieldObj): NUTextFieldObj =
    result = asType[NUTextFieldObj](super(self, init))
    self.value = nil
    if result.isNil:
      return
    if result.textFieldStateRef().isNil:
      result.textFieldStateRef = defaultTextFieldState()

  method setStringValue*(self: NUTextFieldObj, value: string) =
    var st = self.textFieldStateRef()
    if st.isNil:
      st = defaultTextFieldState()
      self.textFieldStateRef = st
    st.stringValue = value

objcImpl:
  type NUButtonObj = object of NUControlObj
    buttonStateRef: NSButtonStateRef

  method init*(self: var NUButtonObj): NUButtonObj =
    result = asType[NUButtonObj](super(self, init))
    self.value = nil
    if result.isNil:
      return
    if result.buttonStateRef().isNil:
      result.buttonStateRef = defaultButtonState()

  method setTitle*(self: NUButtonObj, value: string) =
    var st = self.buttonStateRef()
    if st.isNil:
      st = defaultButtonState()
      self.buttonStateRef = st
    st.title = value

  method performClick*(self: NUButtonObj, sender: NSObject) =
    discard sender
    let st = self.buttonStateRef()
    if st.isNil or st.onClick.isNil:
      return
    st.onClick(self.value)

objcImpl:
  type NUWindowObj = object of NUResponderObj
    windowStateRef: NSWindowStateRef

  method init*(self: var NUWindowObj): NUWindowObj =
    result = asType[NUWindowObj](super(self, init))
    self.value = nil
    if result.isNil:
      return
    if result.windowStateRef().isNil:
      result.windowStateRef = defaultWindowState()

  method initWithContentRect*(
      self: var NUWindowObj, x, y, width, height: cfloat
  ): NUWindowObj =
    result = self.init()
    if result.isNil:
      return
    let st = result.windowStateRef()
    st.frame =
      nsRect(x.float32, y.float32, max(width.float32, 1.0), max(height.float32, 1.0))

  method setContentView*(self: NUWindowObj, view: NUViewObj) =
    if self.isNil:
      return
    var st = self.windowStateRef()
    if st.isNil:
      st = defaultWindowState()
      self.windowStateRef = st
    replaceOwnedId(st.contentView, view.value)

  method contentView*(self: NUWindowObj): NUViewObj =
    let st = self.windowStateRef()
    if st.isNil or st.contentView.isNil:
      return NUViewObj(value: nil)
    result = ownFromId[NUViewObj](st.contentView)

  method setTitle*(self: NUWindowObj, value: string) =
    var st = self.windowStateRef()
    if st.isNil:
      st = defaultWindowState()
      self.windowStateRef = st
    st.title = value
    if st.nativeReady and not st.nativeWindow.isNil:
      st.nativeWindow.title = value

  method makeKeyAndOrderFront*(self: NUWindowObj, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    var st = self.windowStateRef()
    if st.isNil:
      st = defaultWindowState()
      self.windowStateRef = st
    st.visibleRequested = true

  method close*(self: NUWindowObj) =
    let st = self.windowStateRef()
    if st.isNil:
      return
    st.closed = true
    if st.nativeReady and not st.nativeWindow.isNil:
      siwinshim.close(st.nativeWindow)

  method dealloc(self: NUWindowObj) {.used.} =
    let st = self.windowStateRef()
    if not st.isNil:
      if st.nativeReady and (not st.nativeWindow.isNil):
        siwinshim.close(st.nativeWindow)
      replaceOwnedId(st.contentView, nil)
    clearIvarRefs(self)
    superDealloc(self)

objcImpl:
  type NUApplicationObj = object of NUResponderObj
    appStateRef: NSApplicationStateRef

  method init*(self: var NUApplicationObj): NUApplicationObj =
    result = asType[NUApplicationObj](super(self, init))
    self.value = nil
    if result.isNil:
      return
    if result.appStateRef().isNil:
      result.appStateRef = defaultApplicationState()

  method addWindow*(self: NUApplicationObj, window: NUWindowObj) =
    if self.isNil or window.isNil:
      return
    var st = self.appStateRef()
    if st.isNil:
      st = defaultApplicationState()
      self.appStateRef = st
    if window.value notin st.windows:
      st.windows.add(retainId(window.value))
    let wst = window.windowStateRef()
    if not wst.isNil:
      wst.visibleRequested = true

  method run*(self: NUApplicationObj) =
    discard runApplicationFrames(self, -1)

  method stop*(self: NUApplicationObj) =
    let st = self.appStateRef()
    if not st.isNil:
      st.running = false

  method dealloc(self: NUApplicationObj) {.used.} =
    let st = self.appStateRef()
    if not st.isNil:
      clearOwnedIds(st.windows)
    clearIvarRefs(self)
    superDealloc(self)

type
  NSResponder* = NUResponderObj
  NSView* = NUViewObj
  NSControl* = NUControlObj
  NSTextField* = NUTextFieldObj
  NSButton* = NUButtonObj
  NSWindow* = NUWindowObj
  NSApplication* = NUApplicationObj

proc viewState*(view: NSView): NSViewStateRef =
  var st = view.viewStateRef()
  if st.isNil:
    st = defaultViewState()
    view.viewStateRef = st
  st

proc controlState*(control: NSControl): NSControlStateRef =
  var st = control.controlStateRef()
  if st.isNil:
    st = defaultControlState()
    control.controlStateRef = st
  st

proc textFieldState*(field: NSTextField): NSTextFieldStateRef =
  var st = field.textFieldStateRef()
  if st.isNil:
    st = defaultTextFieldState()
    field.textFieldStateRef = st
  st

proc buttonState*(button: NSButton): NSButtonStateRef =
  var st = button.buttonStateRef()
  if st.isNil:
    st = defaultButtonState()
    button.buttonStateRef = st
  st

proc windowState*(window: NSWindow): NSWindowStateRef =
  var st = window.windowStateRef()
  if st.isNil:
    st = defaultWindowState()
    window.windowStateRef = st
  st

proc applicationState*(app: NSApplication): NSApplicationStateRef =
  var st = app.appStateRef()
  if st.isNil:
    st = defaultApplicationState()
    app.appStateRef = st
  st

proc frame*(view: NSView): NSRect =
  view.viewState().frame

proc frame*(window: NSWindow): NSRect =
  window.windowState().frame

proc setBackgroundColor*(view: NSView, r, g, b: float32, a: float32 = 1.0'f32) =
  let st = view.viewState()
  st.backgroundColor = nsColor(r, g, b, a)

proc setHidden*(view: NSView, hidden: bool) =
  view.viewState().hidden = hidden

proc setFrame*(view: NSView, frame: NSRect) =
  view.setFrame(
    frame.origin.x.cfloat, frame.origin.y.cfloat, frame.size.width.cfloat,
    frame.size.height.cfloat,
  )

proc setFrame*(window: NSWindow, frame: NSRect) =
  let st = window.windowState()
  st.frame = frame
  if st.nativeReady and not st.nativeWindow.isNil:
    st.nativeWindow.size =
      ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

proc subviews*(view: NSView): seq[NSView] =
  let st = view.viewState()
  result = newSeq[NSView](st.subviews.len)
  for i, child in st.subviews:
    result[i] = ownFromId[NSView](child)

proc addSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil:
    return
  let st = self.viewState()
  if view.value notin st.subviews:
    st.subviews.add(retainId(view.value))

proc stringValue*(field: NSTextField): string =
  field.textFieldState().stringValue

proc setEnabled*(control: NSControl, enabled: bool) =
  control.controlState().enabled = enabled

proc title*(button: NSButton): string =
  button.buttonState().title

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton) {.gcsafe.}) =
  let st = button.buttonState()
  if cb.isNil:
    st.onClick = nil
  else:
    st.onClick = proc(sender: ID) {.gcsafe.} =
      cb(ownFromId[NSButton](sender))

proc click*(button: NSButton) =
  let st = button.buttonState()
  if not st.onClick.isNil:
    st.onClick(button.value)

proc ensureContentView(window: NSWindow, st: NSWindowStateRef): NSView =
  if not st.contentView.isNil:
    return ownFromId[NSView](st.contentView)

  var rootAlloc = NSView.alloc()
  var root = rootAlloc.initWithFrame(
    0.cfloat, 0.cfloat, st.frame.size.width.cfloat, st.frame.size.height.cfloat
  )
  rootAlloc.value = nil
  replaceOwnedId(st.contentView, root.value)
  result = root

proc viewFillColor(view: NSView, st: NSViewStateRef): Color =
  if view.isKindOfClass(NSButton):
    return nsColor(0.18, 0.45, 0.90, 1.0).toFigColor()
  if view.isKindOfClass(NSTextField):
    return nsColor(1.0, 1.0, 1.0, 1.0).toFigColor()
  st.backgroundColor.toFigColor()

proc viewStrokeColor(view: NSView): Color =
  if view.isKindOfClass(NSButton):
    return nsColor(0.10, 0.20, 0.50, 1.0).toFigColor()
  if view.isKindOfClass(NSTextField):
    return nsColor(0.75, 0.75, 0.80, 1.0).toFigColor()
  nsColor(0.0, 0.0, 0.0, 0.18).toFigColor()

proc viewCornerRadius(view: NSView): float32 =
  if view.isKindOfClass(NSButton):
    return 8.0
  if view.isKindOfClass(NSTextField):
    return 6.0
  0.0

proc runesPrefix(layout: GlyphArrangement, maxRunes: int): string =
  var count = 0
  for rune in layout.runes:
    if count >= maxRunes:
      break
    result.add($rune)
    inc count
  if layout.runes.len > maxRunes:
    result.add("...")

proc dumpRenders(renders: Renders) =
  for z, list in renders.layers.pairs():
    echo "[appkit] layer=", z.int, " roots=", list.rootIds.len, " nodes=", list.nodes.len
    for i, node in list.nodes:
      let box = node.screenBox
      var line =
        "[appkit]   node[" & $i & "] kind=" & $node.kind &
        " parent=" & $node.parent.int &
        " children=" & $node.childCount &
        " box=(" & $box.x & "," & $box.y & " " & $box.w & "x" & $box.h & ")"
      if node.kind == nkText:
        line.add(
          " runes=" & $node.textLayout.runes.len & " preview=\"" &
            runesPrefix(node.textLayout, 40) & "\""
        )
      echo line

proc shouldDebugRenderDump(): bool =
  getEnv("NUTELLA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]

proc textLayoutForView(view: NSView, box: NSRect): tuple[ok: bool, layout: GlyphArrangement] =
  if box.size.width <= 2 or box.size.height <= 2:
    return (false, default(GlyphArrangement))
  if not ensureAppKitFont():
    return (false, default(GlyphArrangement))

  if view.isKindOfClass(NSTextField):
    var textField = asType[NSTextField](view.value)
    let tstate = textField.textFieldState()
    textField.value = nil
    if tstate.stringValue.len == 0:
      return (false, default(GlyphArrangement))
    let spans = [(fs(appkitFont(18.0), tstate.textColor.toFigColor()), tstate.stringValue)]
    let layout = typeset(
      rect(0, 0, box.size.width, box.size.height),
      spans,
      hAlign = FontHorizontal.Left,
      vAlign = FontVertical.Middle,
      minContent = false,
      wrap = true,
    )
    if shouldDebugRenderDump():
      echo "[appkit] textfield layout runes=", layout.runes.len, " text=\"", tstate.stringValue, "\""
    return (
      true,
      layout,
    )

  if view.isKindOfClass(NSButton):
    var button = asType[NSButton](view.value)
    let bstate = button.buttonState()
    button.value = nil
    if bstate.title.len == 0:
      return (false, default(GlyphArrangement))
    let spans = [(fs(appkitFont(16.0), nsColor(1.0, 1.0, 1.0, 1.0).toFigColor()), bstate.title)]
    let layout = typeset(
      rect(0, 0, box.size.width, box.size.height),
      spans,
      hAlign = FontHorizontal.Center,
      vAlign = FontVertical.Middle,
      minContent = false,
      wrap = false,
    )
    if shouldDebugRenderDump():
      echo "[appkit] button layout runes=", layout.runes.len, " title=\"", bstate.title, "\""
    return (
      true,
      layout,
    )

  (false, default(GlyphArrangement))

proc addViewTree(
    renders: var Renders,
    viewId: ID,
    parentIdx: FigIdx,
    hasParent: bool,
    offsetX: float32,
    offsetY: float32,
)

proc buildWindowRenders(window: NSWindow, st: NSWindowStateRef): Renders =
  if st.isNil:
    return nil
  let root = ensureContentView(window, st)
  if root.isNil:
    return nil
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.addViewTree(root.value, FigIdx(0), false, 0.0, 0.0)

proc addViewTree(
    renders: var Renders,
    viewId: ID,
    parentIdx: FigIdx,
    hasParent: bool,
    offsetX: float32,
    offsetY: float32,
) =
  if viewId.isNil:
    return
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return
  let st = view.viewState()
  if st.isNil or st.hidden:
    return

  let box = nsRect(
    offsetX + st.frame.origin.x,
    offsetY + st.frame.origin.y,
    max(st.frame.size.width, 0.0),
    max(st.frame.size.height, 0.0),
  )
  if box.size.width <= 0 or box.size.height <= 0:
    return

  let fig = Fig(
    kind: nkRectangle,
    childCount: 0,
    screenBox: rect(box.origin.x, box.origin.y, box.size.width, box.size.height),
    fill: viewFillColor(view, st),
    corners: uniformCorners(viewCornerRadius(view)),
    stroke: RenderStroke(weight: 1.0, color: viewStrokeColor(view)),
  )

  let idx =
    if hasParent:
      renders.addChild(0.ZLevel, parentIdx, fig)
    else:
      renders.addRoot(0.ZLevel, fig)

  let textPaddingX =
    if view.isKindOfClass(NSButton):
      8.0
    elif view.isKindOfClass(NSTextField):
      10.0
    else:
      0.0
  let textPaddingY =
    if view.isKindOfClass(NSButton) or view.isKindOfClass(NSTextField):
      4.0
    else:
      0.0

  let textBox = nsRect(
    box.origin.x + textPaddingX,
    box.origin.y + textPaddingY,
    max(box.size.width - textPaddingX * 2, 0.0),
    max(box.size.height - textPaddingY * 2, 0.0),
  )
  let textLayout = textLayoutForView(view, textBox)
  if textLayout.ok:
    discard renders.addChild(
      0.ZLevel,
      idx,
      Fig(
        kind: nkText,
        childCount: 0,
        screenBox: rect(
          textBox.origin.x, textBox.origin.y, textBox.size.width, textBox.size.height
        ),
        fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
        textLayout: textLayout.layout,
      ),
    )

  for child in st.subviews:
    renders.addViewTree(child, idx, true, box.origin.x, box.origin.y)

proc hitTestButton(
    viewId: ID, x: float32, y: float32, offsetX: float32, offsetY: float32
): ID =
  if viewId.isNil:
    return nil
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return nil
  let st = view.viewState()
  if st.isNil or st.hidden:
    return nil

  let frame = nsRect(
    offsetX + st.frame.origin.x,
    offsetY + st.frame.origin.y,
    st.frame.size.width,
    st.frame.size.height,
  )

  for i in countdown(st.subviews.high, 0):
    let child = st.subviews[i]
    let hit = hitTestButton(child, x, y, frame.origin.x, frame.origin.y)
    if not hit.isNil:
      return hit

  if view.isKindOfClass(NSButton) and frame.contains(x, y):
    return view.value
  nil

proc renderWindow(window: NSWindow, st: NSWindowStateRef) =
  if st.isNil or st.renderer.isNil or st.nativeWindow.isNil:
    return

  let logicalSize = st.nativeWindow.logicalSize()
  st.frame.size = nsSize(logicalSize.x.float32, logicalSize.y.float32)
  var renders = buildWindowRenders(window, st)
  if renders.isNil:
    return
  let root = ensureContentView(window, st)
  root.setFrame(0.cfloat, 0.cfloat, logicalSize.x.cfloat, logicalSize.y.cfloat)
  if shouldDebugRenderDump():
    dumpRenders(renders)

  st.renderer.beginFrame()
  st.renderer.renderFrame(renders, logicalSize)
  st.renderer.endFrame()

proc debugDumpWindowRenderTree*(window: NSWindow) =
  let st = window.windowState()
  let renders = buildWindowRenders(window, st)
  if renders.isNil:
    echo "[appkit] debug dump: no render tree"
  else:
    dumpRenders(renders)

proc cleanupFailedWindowInit(st: NSWindowStateRef) =
  if st.isNil:
    return
  if not st.nativeWindow.isNil:
    try:
      siwinshim.close(st.nativeWindow)
    except Exception:
      discard
  st.renderer = nil
  st.nativeWindow = nil
  st.nativeReady = false
  st.visibleRequested = false
  st.closed = true

proc ensureNativeWindow(window: NSWindow, st: NSWindowStateRef) =
  if st.isNil or st.nativeReady:
    return

  try:
    let size =
      ivec2(clampWindowSize(st.frame.size.width), clampWindowSize(st.frame.size.height))

    st.nativeWindow =
      siwinshim.newSiwinWindow(size = size, title = st.title, vsync = true)
    st.autoScale = st.nativeWindow.configureUiScale()
    st.renderer = figrender.newFigRenderer(
      atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
    )
    st.renderer.setupBackend(st.nativeWindow)

    st.nativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
      onClose: proc(e: siwinshim.CloseEvent) =
        discard e
        st.closed = true,
      onResize: proc(e: siwinshim.ResizeEvent) =
        st.frame.size = nsSize(e.size.x.float32, e.size.y.float32)
        let root = ensureContentView(window, st)
        root.setFrame(0.cfloat, 0.cfloat, e.size.x.cfloat, e.size.y.cfloat)
        st.nativeWindow.refreshUiScale(st.autoScale)
        renderWindow(window, st),
      onClick: proc(e: siwinshim.ClickEvent) =
        let root = ensureContentView(window, st)
        let buttonId = hitTestButton(root.value, e.pos.x, e.pos.y, 0.0, 0.0)
        if not buttonId.isNil:
          let button = ownFromId[NSButton](buttonId)
          button.performClick(window)
        renderWindow(window, st),
      onRender: proc(e: siwinshim.RenderEvent) =
        discard e
        renderWindow(window, st),
      onKey: proc(e: siwinshim.KeyEvent) =
        if e.pressed and e.key == siwinshim.Key.escape:
          window.close()
      ,
    )

    st.nativeWindow.firstStep()
    st.nativeWindow.refreshUiScale(st.autoScale)
    st.nativeReady = true
  except Exception as exc:
    cleanupFailedWindowInit(st)
    raise newException(CatchableError, "window backend init failed: " & exc.msg)

var sharedApplicationRef {.threadvar.}: NSApplication

proc sharedApplication*(t: typedesc[NSApplication]): NSApplication =
  when false:
    discard t
  if sharedApplicationRef.isNil:
    sharedApplicationRef = NSApplication.new()
  sharedApplicationRef

proc NSApp*(): NSApplication =
  NSApplication.sharedApplication()

proc addWindow*(app: NSApplication, window: NSWindow) =
  let st = app.applicationState()
  if window.value notin st.windows:
    st.windows.add(retainId(window.value))
  window.windowState().visibleRequested = true

proc setContentView*(window: NSWindow, view: NSView) =
  replaceOwnedId(window.windowState().contentView, view.value)

proc contentView*(window: NSWindow): NSView =
  let cv = window.windowState().contentView
  if cv.isNil:
    return NSView(value: nil)
  ownFromId[NSView](cv)

proc makeKeyAndOrderFront*(window: NSWindow, sender: NSObject) =
  discard sender
  window.windowState().visibleRequested = true

proc close*(window: NSWindow) =
  let st = window.windowState()
  st.closed = true
  if st.nativeReady and not st.nativeWindow.isNil:
    siwinshim.close(st.nativeWindow)

proc run*(app: NSApplication) =
  discard runApplicationFrames(app, -1)

proc stop*(app: NSApplication) =
  app.applicationState().running = false

proc runApplicationFrames(appObj: NSObject, maxFrames: int): int =
  let app = ownFromId[NSApplication](appObj.value)
  let st = app.applicationState()
  st.running = true

  while st.running:
    var activeWindows = 0
    var i = 0
    while i < st.windows.len:
      let window = ownFromId[NSWindow](st.windows[i])
      if window.isNil:
        removeOwnedIdAt(st.windows, i)
        continue

      let wst = window.windowState()
      if wst.closed:
        removeOwnedIdAt(st.windows, i)
        continue

      try:
        ensureNativeWindow(window, wst)
      except CatchableError:
        removeOwnedIdAt(st.windows, i)
        raise

      if not wst.visibleRequested:
        inc i
        continue

      if not wst.nativeWindow.isNil and wst.nativeWindow.opened:
        wst.nativeWindow.redraw()
        wst.nativeWindow.step()
      if (not wst.nativeWindow.isNil) and wst.nativeWindow.closed:
        wst.closed = true
        removeOwnedIdAt(st.windows, i)
        continue

      inc activeWindows
      inc i

    inc result
    if maxFrames >= 0 and result >= maxFrames:
      break
    if activeWindows == 0:
      break
    sleep(8)

  st.running = false

proc runForFrames*(app: NSApplication, maxFrames: int): int =
  runApplicationFrames(app, maxFrames)

proc newWindow*(x, y, width, height: float32, title = "Nutella Window"): NSWindow =
  var wAlloc = NSWindow.alloc()
  result = wAlloc.initWithContentRect(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  wAlloc.value = nil
  result.setTitle(title)

proc newView*(x, y, width, height: float32): NSView =
  var vAlloc = NSView.alloc()
  result = vAlloc.initWithFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  vAlloc.value = nil

proc newTextField*(x, y, width, height: float32, value = ""): NSTextField =
  result = NSTextField.new()
  result.setFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  result.setStringValue(value)

proc newButton*(x, y, width, height: float32, title = "Button"): NSButton =
  result = NSButton.new()
  result.setFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  result.setTitle(title)
