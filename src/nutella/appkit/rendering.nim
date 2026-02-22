proc ensureContentView(window: NSWindow): NSView =
  let cv = window.windowContentView()
  if not cv.isNil:
    return ownFromId[NSView](cv)

  let frame = window.windowFrame()
  var rootAlloc = NSView.alloc()
  var root = rootAlloc.initWithFrame(
    0.cfloat, 0.cfloat, frame.size.width.cfloat, frame.size.height.cfloat
  )
  rootAlloc.value = nil
  window.windowContentView = replacedOwnedId(window.windowContentView(), root.value)
  result = root

proc noRenderShadows(): array[ShadowCount, RenderShadow] =
  for i in result.low .. result.high:
    result[i] = RenderShadow(
      style: NoShadow,
      blur: 0.0,
      spread: 0.0,
      x: 0.0,
      y: 0.0,
      fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
    )

proc drawsBg(view: NSView): bool =
  if not view.isKindOfClass(NSTextField):
    return false
  var textField = asType[NSTextField](view.value)
  result = textField.drawsBackground()
  textField.value = nil

proc buttonVisualState(view: NSView): int =
  if not view.isKindOfClass(NSButton):
    return NSOffState
  var button = asType[NSButton](view.value)
  result = button.state()
  button.value = nil

proc aquaButtonFill(state: int): Fill =
  case state
  of NSOnState:
    linear(
      nsColor(0.46, 0.64, 0.90, 1.0).toFigRgba(),
      nsColor(0.31, 0.50, 0.81, 1.0).toFigRgba(),
      nsColor(0.19, 0.34, 0.66, 1.0).toFigRgba(),
      axis = fgaY,
      midPos = 132'u8,
    )
  of NSMixedState:
    linear(
      nsColor(0.76, 0.79, 0.84, 1.0).toFigRgba(),
      nsColor(0.65, 0.69, 0.76, 1.0).toFigRgba(),
      nsColor(0.53, 0.58, 0.66, 1.0).toFigRgba(),
      axis = fgaY,
      midPos = 132'u8,
    )
  else:
    linear(
      nsColor(0.63, 0.78, 0.98, 1.0).toFigRgba(),
      nsColor(0.42, 0.65, 0.95, 1.0).toFigRgba(),
      nsColor(0.27, 0.50, 0.86, 1.0).toFigRgba(),
      axis = fgaY,
      midPos = 132'u8,
    )

proc aquaButtonStroke(state: int): Fill =
  case state
  of NSOnState:
    linear(
      nsColor(0.35, 0.50, 0.78, 1.0).toFigRgba(),
      nsColor(0.11, 0.23, 0.49, 1.0).toFigRgba(),
      axis = fgaY,
    )
  of NSMixedState:
    linear(
      nsColor(0.55, 0.60, 0.68, 1.0).toFigRgba(),
      nsColor(0.36, 0.41, 0.50, 1.0).toFigRgba(),
      axis = fgaY,
    )
  else:
    linear(
      nsColor(0.41, 0.60, 0.88, 1.0).toFigRgba(),
      nsColor(0.15, 0.33, 0.64, 1.0).toFigRgba(),
      axis = fgaY,
    )

proc viewShadows(view: NSView): array[ShadowCount, RenderShadow] =
  result = noRenderShadows()
  if view.isKindOfClass(NSButton):
    let state = buttonVisualState(view)
    let dropAlpha =
      if state == NSOnState:
        0.32
      elif state == NSMixedState:
        0.17
      else:
        0.27
    let bottomInsetAlpha =
      if state == NSOnState:
        0.22
      elif state == NSMixedState:
        0.19
      else:
        0.25
    result[0] = RenderShadow(
      style: DropShadow,
      blur: 2.8,
      spread: 0.0,
      x: 0.0,
      y: 1.2,
      fill: nsColor(0.10, 0.18, 0.35, dropAlpha).toFigColor(),
    )
    result[1] = RenderShadow(
      style: InnerShadow,
      blur: 1.2,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      fill: nsColor(1.0, 1.0, 1.0, 0.52).toFigColor(),
    )
    result[2] = RenderShadow(
      style: InnerShadow,
      blur: 1.5,
      spread: 0.0,
      x: 0.0,
      y: -1.0,
      fill: nsColor(0.03, 0.11, 0.28, bottomInsetAlpha).toFigColor(),
    )
  elif view.isKindOfClass(NSTextField):
    if not drawsBg(view):
      return
    result[0] = RenderShadow(
      style: InnerShadow,
      blur: 1.0,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      fill: nsColor(1.0, 1.0, 1.0, 0.45).toFigColor(),
    )
    result[1] = RenderShadow(
      style: DropShadow,
      blur: 1.0,
      spread: 0.0,
      x: 0.0,
      y: 1.0,
      fill: nsColor(0.34, 0.40, 0.52, 0.20).toFigColor(),
    )

proc viewFill(view: NSView): Fill =
  if view.isKindOfClass(NSButton):
    return aquaButtonFill(buttonVisualState(view))
  if view.isKindOfClass(NSTextField):
    var textField = asType[NSTextField](view.value)
    let drawsBackground = textField.drawsBg()
    let backgroundColor = textField.bgColor()
    textField.value = nil
    if drawsBackground:
      return backgroundColor.solidFill()
    return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
  view.viewBackgroundColor().solidFill()

proc viewStrokeFill(view: NSView): Fill =
  if view.isKindOfClass(NSButton):
    return aquaButtonStroke(buttonVisualState(view))
  if view.isKindOfClass(NSTextField):
    if not drawsBg(view):
      return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
    return nsColor(0.64, 0.70, 0.80, 1.0).solidFill()
  nsColor(0.34, 0.42, 0.56, 0.28).solidFill()

proc viewCornerRadius(view: NSView): float32 =
  if view.isKindOfClass(NSButton):
    return 10.0
  if view.isKindOfClass(NSTextField):
    if not drawsBg(view):
      return 0.0
    return 8.0
  0.0

proc addAquaGlossOverlay(
    renders: var Renders, parentIdx: FigIdx, view: NSView, box: NSRect
) =
  if box.size.width <= 4 or box.size.height <= 4:
    return

  var glossFill = nsColor(1.0, 1.0, 1.0, 0.0).solidFill()
  var glossHeight = 0.0
  if view.isKindOfClass(NSButton):
    glossFill = linear(
      nsColor(1.0, 1.0, 1.0, 0.66).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.40).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.08).toFigRgba(),
      axis = fgaY,
      midPos = 150'u8,
    )
    glossHeight = box.size.height * 0.56
  elif view.isKindOfClass(NSTextField):
    if not drawsBg(view):
      return
    glossFill = linear(
      nsColor(1.0, 1.0, 1.0, 0.38).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.16).toFigRgba(),
      axis = fgaY,
    )
    glossHeight = box.size.height * 0.46
  else:
    return

  glossHeight = min(max(glossHeight, 6.0), box.size.height)
  let radius = viewCornerRadius(view)
  let glossBox = rect(
    box.origin.x + 1.0,
    box.origin.y + 1.0,
    max(box.size.width - 2.0, 0.0),
    max(glossHeight - 1.0, 0.0),
  )
  if glossBox.w <= 0 or glossBox.h <= 0:
    return

  discard renders.addChild(
    0.ZLevel,
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: glossBox,
      fill: glossFill,
      corners: [radius, radius, max(radius - 5.0, 0.0), max(radius - 5.0, 0.0)],
      stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor()),
    ),
  )

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
    echo "[appkit] layer=",
      z.int, " roots=", list.rootIds.len, " nodes=", list.nodes.len
    for i, node in list.nodes:
      let box = node.screenBox
      var line =
        "[appkit]   node[" & $i & "] kind=" & $node.kind & " parent=" & $node.parent.int &
        " children=" & $node.childCount & " box=(" & $box.x & "," & $box.y & " " & $box.w &
        "x" & $box.h & ")"
      if node.kind == nkText:
        line.add(
          " runes=" & $node.textLayout.runes.len & " preview=\"" &
            runesPrefix(node.textLayout, 40) & "\""
        )
      echo line

proc shouldDebugRenderDump(): bool =
  getEnv("NUTELLA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]

proc textLayoutForView(
    view: NSView, box: NSRect
): tuple[ok: bool, layout: GlyphArrangement] =
  if box.size.width <= 2 or box.size.height <= 2:
    return (false, default(GlyphArrangement))
  if not ensureAppKitFont():
    return (false, default(GlyphArrangement))

  if view.isKindOfClass(NSTextField):
    var textField = asType[NSTextField](view.value)
    let textValue = $textField.stringValue()
    let textColor = textField.txtColor()
    let textAlign = toFontHorizontal(textField.alignment())
    textField.value = nil
    if textValue.len == 0:
      return (false, default(GlyphArrangement))
    let spans = [(fs(appkitFont(18.0), textColor.toFigColor()), textValue)]
    let layout = typeset(
      rect(0, 0, box.size.width, box.size.height),
      spans,
      hAlign = textAlign,
      vAlign = FontVertical.Middle,
      minContent = false,
      wrap = true,
    )
    if shouldDebugRenderDump():
      echo "[appkit] textfield layout runes=",
        layout.runes.len, " text=\"", textValue, "\""
    return (true, layout)

  if view.isKindOfClass(NSButton):
    var button = asType[NSButton](view.value)
    let title = $button.title()
    let textAlign = toFontHorizontal(button.alignment())
    button.value = nil
    if title.len == 0:
      return (false, default(GlyphArrangement))
    let spans =
      [(fs(appkitFont(16.0), nsColor(0.98, 0.99, 1.0, 1.0).toFigColor()), title)]
    let layout = typeset(
      rect(0, 0, box.size.width, box.size.height),
      spans,
      hAlign = textAlign,
      vAlign = FontVertical.Middle,
      minContent = false,
      wrap = false,
    )
    if shouldDebugRenderDump():
      echo "[appkit] button layout runes=", layout.runes.len, " title=\"", title, "\""
    return (true, layout)

  (false, default(GlyphArrangement))

proc addViewTree(
  renders: var Renders,
  viewId: ID,
  parentIdx: FigIdx,
  hasParent: bool,
  offsetX: float32,
  offsetY: float32,
)

proc buildWindowRenders(window: NSWindow): Renders =
  let root = ensureContentView(window)
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
  if view.viewHidden():
    return
  let frame = view.viewFrame()

  let box = nsRect(
    offsetX + frame.origin.x,
    offsetY + frame.origin.y,
    max(frame.size.width, 0.0),
    max(frame.size.height, 0.0),
  )
  if box.size.width <= 0 or box.size.height <= 0:
    return

  let fig = Fig(
    kind: nkRectangle,
    childCount: 0,
    screenBox: rect(box.origin.x, box.origin.y, box.size.width, box.size.height),
    fill: viewFill(view),
    corners: uniformCorners(viewCornerRadius(view)),
    shadows: viewShadows(view),
    stroke: RenderStroke(weight: 1.0, fill: viewStrokeFill(view)),
  )

  let idx =
    if hasParent:
      renders.addChild(0.ZLevel, parentIdx, fig)
    else:
      renders.addRoot(0.ZLevel, fig)

  addAquaGlossOverlay(renders, idx, view, box)

  let textFieldHasBackground =
    if view.isKindOfClass(NSTextField):
      drawsBg(view)
    else:
      false
  let textPaddingX =
    if view.isKindOfClass(NSButton):
      8.0
    elif view.isKindOfClass(NSTextField):
      (if textFieldHasBackground: 10.0 else: 0.0)
    else:
      0.0
  let textPaddingY =
    if view.isKindOfClass(NSButton):
      4.0
    elif view.isKindOfClass(NSTextField):
      (if textFieldHasBackground: 4.0 else: 0.0)
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

  for child in view.viewSubviews():
    renders.addViewTree(child, idx, true, box.origin.x, box.origin.y)

proc hitTestButton(
    viewId: ID, x: float32, y: float32, offsetX: float32, offsetY: float32
): ID =
  if viewId.isNil:
    return nil
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return nil
  if view.viewHidden():
    return nil
  let frameSelf = view.viewFrame()

  let frame = nsRect(
    offsetX + frameSelf.origin.x,
    offsetY + frameSelf.origin.y,
    frameSelf.size.width,
    frameSelf.size.height,
  )

  let children = view.viewSubviews()
  for i in countdown(children.high, 0):
    let child = children[i]
    let hit = hitTestButton(child, x, y, frame.origin.x, frame.origin.y)
    if not hit.isNil:
      return hit

  if view.isKindOfClass(NSButton) and frame.contains(x, y):
    return view.value
  nil

proc rawInputToLogical*(rawPos: Vec2, backingSize: IVec2, logicalSize: Vec2): Vec2 =
  ## Siwin mouse/click positions are reported in backing pixel coordinates.
  ## AppKit layout/hit-testing here is done in logical coordinates.
  if backingSize.x <= 0 or backingSize.y <= 0:
    return rawPos
  if logicalSize.x <= 0.0 or logicalSize.y <= 0.0:
    return rawPos
  vec2(
    rawPos.x * logicalSize.x / backingSize.x.float32,
    rawPos.y * logicalSize.y / backingSize.y.float32,
  )

proc logicalInputPos(window: siwinshim.Window, rawPos: Vec2): Vec2 =
  if window.isNil:
    return rawPos
  rawInputToLogical(rawPos, window.backingSize(), window.logicalSize())

proc renderWindow(window: NSWindow) =
  let nativeWindow = window.windowNativeWindow()
  let renderer = window.windowRenderer()
  if renderer.isNil or nativeWindow.isNil:
    return

  let nativeLogicalSize = nativeWindow.logicalSize()
  let logicalSize = vec2(max(nativeLogicalSize.x, 1.0), max(nativeLogicalSize.y, 1.0))
  var frame = window.windowFrame()
  if abs(frame.size.width - logicalSize.x) > 0.01 or
      abs(frame.size.height - logicalSize.y) > 0.01:
    frame.size = nsSize(logicalSize.x, logicalSize.y)
    window.windowFrame = frame
  let root = ensureContentView(window)
  root.setFrame(0.cfloat, 0.cfloat, logicalSize.x.cfloat, logicalSize.y.cfloat)
  var renders = buildWindowRenders(window)
  if renders.isNil:
    return
  if shouldDebugRenderDump():
    dumpRenders(renders)

  renderer.beginFrame()
  renderer.renderFrame(renders, logicalSize)
  renderer.endFrame()

proc debugDumpWindowRenderTree*(window: NSWindow) =
  let renders = buildWindowRenders(window)
  if renders.isNil:
    echo "[appkit] debug dump: no render tree"
  else:
    dumpRenders(renders)

proc cleanupFailedWindowInit(window: NSWindow) =
  if not window.windowNativeWindow().isNil:
    try:
      siwinshim.close(window.windowNativeWindow())
    except Exception:
      discard
  window.windowRenderer = nil
  window.windowNativeWindow = nil
  window.windowNativeReady = false
  window.windowVisibleRequested = false
  window.windowClosed = true

proc ensureNativeWindow(window: NSWindow) =
  if window.windowNativeReady():
    return

  try:
    let frame = window.windowFrame()
    let size =
      ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

    window.windowNativeWindow =
      siwinshim.newSiwinWindow(size = size, title = $window.windowTitle(), vsync = true)
    window.windowAutoScale = window.windowNativeWindow().configureUiScale()
    window.windowRenderer = figrender.newFigRenderer(
      atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
    )
    var renderer = window.windowRenderer()
    renderer.setupBackend(window.windowNativeWindow())
    window.windowRenderer = renderer

    window.windowNativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
      onClose: proc(e: siwinshim.CloseEvent) =
        discard e
        window.windowClosed = true,
      onResize: proc(e: siwinshim.ResizeEvent) =
        discard e
        window.windowNativeWindow().refreshUiScale(window.windowAutoScale())
        renderWindow(window),
      onClick: proc(e: siwinshim.ClickEvent) =
        let root = ensureContentView(window)
        let logicalPos = logicalInputPos(window.windowNativeWindow(), e.pos)
        let buttonId = hitTestButton(root.value, logicalPos.x, logicalPos.y, 0.0, 0.0)
        if not buttonId.isNil:
          let button = ownFromId[NSButton](buttonId)
          button.performClick(window)
        renderWindow(window),
      onRender: proc(e: siwinshim.RenderEvent) =
        discard e
        renderWindow(window),
      onKey: proc(e: siwinshim.KeyEvent) =
        if e.pressed and e.key == siwinshim.Key.escape:
          window.close()
      ,
    )

    window.windowNativeWindow().firstStep()
    window.windowNativeWindow().refreshUiScale(window.windowAutoScale())
    window.windowNativeReady = true
  except Exception as exc:
    cleanupFailedWindowInit(window)
    raise newException(CatchableError, "window backend init failed: " & exc.msg)
