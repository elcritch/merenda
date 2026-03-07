import std/[os, strutils, unicode]

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim as siwinshim

import ./runtime
import ./graphicscontexts
import ./views
import ./windows
import ./buttons
import ./comboboxes
import ./events

var trackedMouseDownButtonId {.threadvar.}: IDPtr
var trackedMouseDownComboBoxId {.threadvar.}: IDPtr
var trackedMouseDownComboPopupItemIndex {.threadvar.}: int
var windowFlushHookInstalled {.threadvar.}: bool

proc setTrackedMouseDownButton(buttonId: IDPtr) =
  trackedMouseDownButtonId = replacedOwnedId(trackedMouseDownButtonId, buttonId)

proc clearTrackedMouseDownButton() =
  trackedMouseDownButtonId = replacedOwnedId(trackedMouseDownButtonId, nil)

proc setTrackedMouseDownComboBox(comboBoxId: IDPtr, popupItemIndex: int) =
  trackedMouseDownComboBoxId = replacedOwnedId(trackedMouseDownComboBoxId, comboBoxId)
  trackedMouseDownComboPopupItemIndex = popupItemIndex

proc clearTrackedMouseDownComboBox() =
  trackedMouseDownComboBoxId = replacedOwnedId(trackedMouseDownComboBoxId, nil)
  trackedMouseDownComboPopupItemIndex = -1

proc ensureContentView(window: NSWindow): NSView =
  let cv = window.contentView()
  if not cv.isNil:
    return ownFromId[NSView](cv)

  let frame = window.windowFrame()
  var rootAlloc = NSView.alloc()
  var root = rootAlloc.initWithFrame(
    nsRect(0'f32, 0'f32, frame.size.width.float32, frame.size.height.float32)
  )
  rootAlloc.value = nil
  window.setContentView(root)
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

const DefaultLabelFontSize = 13.0'f32

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
  getEnv("KNUTELLA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]

const textLayoutBoundsEpsilon = 0.75'f32

type TextLayoutDebugMetrics* = object
  hasLayout*: bool
  fitsTextBox*: bool
  controlBox*: NSRect
  textBox*: NSRect
  textBounds*: NSRect
  glyphCount*: int

proc textLayoutBounds(
    layout: GlyphArrangement
): tuple[ok: bool, minX: float32, minY: float32, maxX: float32, maxY: float32] =
  var found = false
  var minX = 0.0'f32
  var minY = 0.0'f32
  var maxX = 0.0'f32
  var maxY = 0.0'f32
  for r in layout.selectionRects:
    if r.w <= 0 or r.h <= 0:
      continue
    if not found:
      minX = r.x
      minY = r.y
      maxX = r.x + r.w
      maxY = r.y + r.h
      found = true
      continue
    minX = min(minX, r.x)
    minY = min(minY, r.y)
    maxX = max(maxX, r.x + r.w)
    maxY = max(maxY, r.y + r.h)
  if not found:
    return (false, 0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32)
  (true, minX, minY, maxX, maxY)

proc textBoundsForLayout(
    layout: GlyphArrangement, box: NSRect
): tuple[ok: bool, bounds: NSRect] =
  let bounds = textLayoutBounds(layout)
  if not bounds.ok:
    return (false, nsRect(box.origin.x, box.origin.y, 0.0, 0.0))
  (
    true,
    nsRect(
      box.origin.x + bounds.minX,
      box.origin.y + bounds.minY,
      bounds.maxX - bounds.minX,
      bounds.maxY - bounds.minY,
    ),
  )

proc layoutFitsTextBox(
    layout: GlyphArrangement, box: NSRect, epsilon = textLayoutBoundsEpsilon
): bool =
  let bounds = textLayoutBounds(layout)
  if not bounds.ok:
    return true
  bounds.minX >= -epsilon and bounds.minY >= -epsilon and
    bounds.maxX <= box.size.width + epsilon and bounds.maxY <= box.size.height + epsilon

proc singleLineLayout(
    text: string, style: FontStyle, textAlign: FontHorizontal, box: NSRect
): GlyphArrangement =
  let spans = [(style, text)]
  typeset(
    rect(0, 0, box.size.width, box.size.height),
    spans,
    hAlign = textAlign,
    vAlign = FontVertical.Middle,
    minContent = false,
    wrap = false,
  )

proc singleLineTextCandidate(runes: seq[Rune], keep: int): string =
  result = newStringOfCap(keep + 3)
  for i in 0 ..< keep:
    result.add($runes[i])
  if keep < runes.len:
    result.add("...")

proc fitSingleLineText(
    text: string, style: FontStyle, textAlign: FontHorizontal, box: NSRect
): tuple[text: string, layout: GlyphArrangement] =
  let layout = singleLineLayout(text, style, textAlign, box)
  if layoutFitsTextBox(layout, box):
    return (text, layout)

  var runes: seq[Rune] = @[]
  for rune in text.runes:
    runes.add(rune)
  if runes.len == 0:
    return ("", default(GlyphArrangement))

  var low = 0
  var high = runes.len
  var bestText = ""
  var bestLayout = default(GlyphArrangement)
  while low <= high:
    let keep = (low + high) div 2
    let candidate = singleLineTextCandidate(runes, keep)
    let candidateLayout = singleLineLayout(candidate, style, textAlign, box)
    if layoutFitsTextBox(candidateLayout, box):
      bestText = candidate
      bestLayout = candidateLayout
      low = keep + 1
    else:
      high = keep - 1
  if bestText.len == 0:
    return (text, layout)
  (bestText, bestLayout)

proc sendInt(obj: IDPtr, op: SEL): int {.inline.} =
  if obj.isNil or cast[pointer](op).isNil:
    return 0
  cast[proc(self: IDPtr, op: SEL): int {.cdecl, varargs.}](objc_msgSend)(obj, op)

proc sendId(obj: IDPtr, op: SEL): IDPtr {.inline.} =
  if obj.isNil or cast[pointer](op).isNil:
    return nil
  cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(obj, op)

proc debugTextLayoutMetricsForView*(view: NSView): TextLayoutDebugMetrics =
  if view.isNil:
    return
  let frame = view.frame()
  result.controlBox = nsRect(
    frame.origin.x,
    frame.origin.y,
    max(frame.size.width, 0.0),
    max(frame.size.height, 0.0),
  )
  result.textBox = result.controlBox
  if result.textBox.size.width <= 2.0 or result.textBox.size.height <= 2.0:
    return
  if not ensureAppKitFont():
    return

  var textValue = ""
  if view.respondsToSelector("stringValue"):
    let stringId = sendId(view.value, getSelector("stringValue"))
    if not stringId.isNil:
      textValue = $ownFromId[NSString](stringId)
  if textValue.len == 0:
    return

  var textAlign = FontHorizontal.Left
  if view.respondsToSelector("alignment"):
    textAlign =
      toFontHorizontal(NSTextAlignment(sendInt(view.value, getSelector("alignment"))))

  let fitted = fitSingleLineText(
    textValue,
    fs(appkitFont(DefaultLabelFontSize), nsColor(0.08, 0.08, 0.08, 1.0).toFigColor()),
    textAlign,
    result.textBox,
  )
  if fitted.text.len == 0:
    return
  result.hasLayout = true
  result.glyphCount = fitted.layout.runes.len
  result.fitsTextBox = layoutFitsTextBox(fitted.layout, result.textBox)
  let bounds = textBoundsForLayout(fitted.layout, result.textBox)
  if bounds.ok:
    result.textBounds = bounds.bounds
  else:
    result.textBounds =
      nsRect(result.textBox.origin.x, result.textBox.origin.y, 0.0, 0.0)

proc viewLocalToScreenTransform(
    view: NSView, screenBox: NSRect, localBounds: NSRect
): TransformStyle =
  if view.isFlipped():
    return TransformStyle(
      translation: vec2(
        screenBox.origin.x - localBounds.origin.x,
        screenBox.origin.y - localBounds.origin.y,
      ),
      useMatrix: false,
    )
  TransformStyle(
    translation: vec2(
      screenBox.origin.x - localBounds.origin.x,
      screenBox.origin.y + screenBox.size.height + localBounds.origin.y,
    ),
    matrix: scale(vec3(1.0'f32, -1.0'f32, 1.0'f32)),
    useMatrix: true,
  )

proc addViewTree(
  renders: var Renders,
  viewId: IDPtr,
  parentIdx: FigIdx,
  hasParent: bool,
  parentOriginX: float32,
  parentOriginY: float32,
  parentHeight: float32,
  parentFlipped: bool,
)

proc childScreenOriginY(
    parentOriginY: float32,
    parentHeight: float32,
    parentFlipped: bool,
    childFrame: NSRect,
): float32 =
  if parentFlipped:
    return parentOriginY + childFrame.origin.y
  parentOriginY + parentHeight - childFrame.origin.y - childFrame.size.height

proc buildWindowRenders(window: NSWindow): Renders =
  let root = ensureContentView(window)
  if root.isNil:
    return nil
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.addViewTree(root.value, FigIdx(0), false, 0.0, 0.0, 0.0, false)

proc addViewTree(
    renders: var Renders,
    viewId: IDPtr,
    parentIdx: FigIdx,
    hasParent: bool,
    parentOriginX: float32,
    parentOriginY: float32,
    parentHeight: float32,
    parentFlipped: bool,
) =
  if viewId.isNil:
    return
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return
  if view.isHidden():
    return
  let frame = view.frame()

  let boxOriginY =
    if hasParent:
      childScreenOriginY(parentOriginY, parentHeight, parentFlipped, frame)
    else:
      frame.origin.y
  let box = nsRect(
    parentOriginX + frame.origin.x,
    boxOriginY,
    max(frame.size.width, 0.0),
    max(frame.size.height, 0.0),
  )
  if box.size.width <= 0 or box.size.height <= 0:
    return
  var localBox = view.bounds()
  localBox.size.width = max(localBox.size.width, 0.0)
  localBox.size.height = max(localBox.size.height, 0.0)
  if localBox.size.width <= 0.0:
    localBox.size.width = box.size.width
  if localBox.size.height <= 0.0:
    localBox.size.height = box.size.height

  let fig = Fig(
    kind: nkRectangle,
    childCount: 0,
    flags: (
      if view.wantsClipToBounds():
        {NfClipContent}
      else:
        {}
    ),
    screenBox: rect(box.origin.x, box.origin.y, box.size.width, box.size.height),
    fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill(),
    corners: uniformCorners(0.0),
    shadows: noRenderShadows(),
    stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
  )

  let idx =
    if hasParent:
      renders.addChild(0.ZLevel, parentIdx, fig)
    else:
      renders.addRoot(0.ZLevel, fig)
  let drawTransformIdx = renders.addChild(
    0.ZLevel,
    idx,
    Fig(
      kind: nkTransform,
      childCount: 0,
      transform: viewLocalToScreenTransform(view, box, localBox),
    ),
  )

  var renderPort = RenderGraphicsPort(
    renders: addr renders, parentIdx: drawTransformIdx, drawBox: localBox
  )
  let renderGraphicsContext = NSGraphicsContext.graphicsContextWithGraphicsPort(
    cast[pointer](addr renderPort), view.isFlipped()
  )
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.setCurrentContext(renderGraphicsContext)
  NSGraphicsContext.currentContext().pushFocusView(view)

  try:
    view.drawRect(view.bounds())
  finally:
    discard NSGraphicsContext.currentContext().popFocusView()
    NSGraphicsContext.restoreGraphicsState()

  for child in view.subviews():
    renders.addViewTree(
      child.value,
      idx,
      true,
      box.origin.x,
      box.origin.y,
      box.size.height,
      view.isFlipped(),
    )

proc hitTestButton(
    viewId: IDPtr,
    x: float32,
    y: float32,
    hasParent: bool,
    parentOriginX: float32,
    parentOriginY: float32,
    parentHeight: float32,
    parentFlipped: bool,
): IDPtr =
  if viewId.isNil:
    return nil
  let view = ownFromId[NSView](viewId)
  if view.isNil:
    return nil
  if view.isHidden():
    return nil
  let frameSelf = view.frame()

  let frameOriginY =
    if hasParent:
      childScreenOriginY(parentOriginY, parentHeight, parentFlipped, frameSelf)
    else:
      frameSelf.origin.y
  let frame = nsRect(
    parentOriginX + frameSelf.origin.x,
    frameOriginY,
    frameSelf.size.width,
    frameSelf.size.height,
  )
  if view.wantsClipToBounds() and not frame.contains(x, y):
    return nil

  let children = view.subviews()
  for i in countdown(children.high, 0):
    let child = children[i]
    let hit = hitTestButton(
      child.value,
      x,
      y,
      true,
      frame.origin.x,
      frame.origin.y,
      frame.size.height,
      view.isFlipped(),
    )
    if not hit.isNil:
      return hit

  if view.isKindOfClass(NSButton) and frame.contains(x, y):
    return view.value
  nil

proc hitTestComboBox(
    viewId: IDPtr,
    x: float32,
    y: float32,
    hasParent: bool,
    parentOriginX: float32,
    parentOriginY: float32,
    parentHeight: float32,
    parentFlipped: bool,
): IDPtr =
  if viewId.isNil:
    return nil
  let view = ownFromId[NSView](viewId)
  if view.isNil or view.isHidden():
    return nil
  let frameSelf = view.frame()
  let frameOriginY =
    if hasParent:
      childScreenOriginY(parentOriginY, parentHeight, parentFlipped, frameSelf)
    else:
      frameSelf.origin.y
  let frame = nsRect(
    parentOriginX + frameSelf.origin.x,
    frameOriginY,
    frameSelf.size.width,
    frameSelf.size.height,
  )
  if view.wantsClipToBounds() and not frame.contains(x, y):
    return nil

  let children = view.subviews()
  for i in countdown(children.high, 0):
    let hit = hitTestComboBox(
      children[i].value,
      x,
      y,
      true,
      frame.origin.x,
      frame.origin.y,
      frame.size.height,
      view.isFlipped(),
    )
    if not hit.isNil:
      return hit
  if view.isKindOfClass(NSComboBox) and frame.contains(x, y):
    return view.value
  nil

proc findViewScreenFrame(
    viewId: IDPtr,
    targetId: IDPtr,
    hasParent: bool,
    parentOriginX: float32,
    parentOriginY: float32,
    parentHeight: float32,
    parentFlipped: bool,
    resultFrame: var NSRect,
): bool =
  if viewId.isNil or targetId.isNil:
    return false
  let view = ownFromId[NSView](viewId)
  if view.isNil or view.isHidden():
    return false
  let frameSelf = view.frame()
  let frameOriginY =
    if hasParent:
      childScreenOriginY(parentOriginY, parentHeight, parentFlipped, frameSelf)
    else:
      frameSelf.origin.y
  let frame = nsRect(
    parentOriginX + frameSelf.origin.x,
    frameOriginY,
    frameSelf.size.width,
    frameSelf.size.height,
  )
  if view.value == targetId:
    resultFrame = frame
    return true
  for child in view.subviews():
    if findViewScreenFrame(
      child.value,
      targetId,
      true,
      frame.origin.x,
      frame.origin.y,
      frame.size.height,
      view.isFlipped(),
      resultFrame,
    ):
      return true
  false

type ComboPopupHit = object
  comboId: IDPtr
  itemIndex: int
  inPopup: bool

proc hitTestOpenComboPopup(
    viewId: IDPtr,
    x: float32,
    y: float32,
    hasParent: bool,
    parentOriginX: float32,
    parentOriginY: float32,
    parentHeight: float32,
    parentFlipped: bool,
): ComboPopupHit =
  if viewId.isNil:
    return
  let view = ownFromId[NSView](viewId)
  if view.isNil or view.isHidden():
    return
  let frameSelf = view.frame()
  let frameOriginY =
    if hasParent:
      childScreenOriginY(parentOriginY, parentHeight, parentFlipped, frameSelf)
    else:
      frameSelf.origin.y
  let frame = nsRect(
    parentOriginX + frameSelf.origin.x,
    frameOriginY,
    frameSelf.size.width,
    frameSelf.size.height,
  )

  let children = view.subviews()
  for i in countdown(children.high, 0):
    let childHit = hitTestOpenComboPopup(
      children[i].value,
      x,
      y,
      true,
      frame.origin.x,
      frame.origin.y,
      frame.size.height,
      view.isFlipped(),
    )
    if childHit.inPopup:
      return childHit

  if not view.isKindOfClass(NSComboBox):
    return
  let comboBox = view.NSComboBox
  if comboBox.isNil or (not comboBox.popupOpen()):
    return
  let popupBox = comboBoxPopupFrame(comboBox, frame)
  if not popupBox.contains(x, y):
    return
  result.comboId = view.value
  result.itemIndex = comboBoxPopupItemIndexAtPoint(comboBox, frame, x, y)
  result.inPopup = true

proc closeOpenComboPopupsInTree(
    viewId: IDPtr, exceptComboId: IDPtr, changed: var bool
) =
  if viewId.isNil:
    return
  let view = ownFromId[NSView](viewId)
  if view.isNil or view.isHidden():
    return
  if view.isKindOfClass(NSComboBox):
    let comboBox = view.NSComboBox
    if (not comboBox.isNil) and comboBox.popupOpen() and
        (exceptComboId.isNil or view.value != exceptComboId):
      comboBox.closePopup()
      changed = true
  for child in view.subviews():
    closeOpenComboPopupsInTree(child.value, exceptComboId, changed)

proc closeOpenComboPopups(rootViewId: IDPtr, exceptComboId: IDPtr): bool =
  var changed = false
  closeOpenComboPopupsInTree(rootViewId, exceptComboId, changed)
  changed

proc updateOpenComboPopupHoverInTree(
    viewId: IDPtr,
    x: float32,
    y: float32,
    hasParent: bool,
    parentOriginX: float32,
    parentOriginY: float32,
    parentHeight: float32,
    parentFlipped: bool,
    changed: var bool,
) =
  if viewId.isNil:
    return
  let view = ownFromId[NSView](viewId)
  if view.isNil or view.isHidden():
    return
  let frameSelf = view.frame()
  let frameOriginY =
    if hasParent:
      childScreenOriginY(parentOriginY, parentHeight, parentFlipped, frameSelf)
    else:
      frameSelf.origin.y
  let frame = nsRect(
    parentOriginX + frameSelf.origin.x,
    frameOriginY,
    frameSelf.size.width,
    frameSelf.size.height,
  )
  if view.isKindOfClass(NSComboBox):
    let comboBox = view.NSComboBox
    if (not comboBox.isNil) and comboBox.popupOpen():
      let hoverItem = comboBoxPopupItemIndexAtPoint(comboBox, frame, x, y)
      if comboBox.popupHoveredIndex() != hoverItem:
        comboBox.setPopupHoveredIndex(hoverItem)
        changed = true
  for child in view.subviews():
    updateOpenComboPopupHoverInTree(
      child.value,
      x,
      y,
      true,
      frame.origin.x,
      frame.origin.y,
      frame.size.height,
      view.isFlipped(),
      changed,
    )

proc updateOpenComboPopupHover(window: NSWindow, x: float32, y: float32): bool =
  let root = ensureContentView(window)
  if root.isNil:
    return false
  var changed = false
  updateOpenComboPopupHoverInTree(
    root.value, x, y, false, 0.0, 0.0, 0.0, false, changed
  )
  changed

proc handleComboBoxMouseDown(
    window: NSWindow, x: float32, y: float32
): tuple[consumed: bool, needsRender: bool] =
  let root = ensureContentView(window)
  if root.isNil:
    return

  let popupHit = hitTestOpenComboPopup(root.value, x, y, false, 0.0, 0.0, 0.0, false)
  if popupHit.inPopup:
    clearTrackedMouseDownButton()
    setTrackedMouseDownComboBox(popupHit.comboId, popupHit.itemIndex)
    let comboBox = ownFromId[NSComboBox](popupHit.comboId)
    if (not comboBox.isNil) and comboBox.popupHoveredIndex() != popupHit.itemIndex:
      comboBox.setPopupHoveredIndex(popupHit.itemIndex)
      result.needsRender = true
    result.consumed = true
    return

  let hit = hitTestComboBox(root.value, x, y, false, 0.0, 0.0, 0.0, false)
  if not hit.isNil:
    clearTrackedMouseDownButton()
    clearTrackedMouseDownComboBox()
    let comboBox = ownFromId[NSComboBox](hit)
    if comboBox.isNil:
      result.consumed = true
      return
    let control = comboBox.NSControl
    if not control.isEnabled():
      result.consumed = true
      return

    var changed = closeOpenComboPopups(root.value, hit)
    if comboBox.popupOpen():
      comboBox.closePopup()
      changed = true
    else:
      comboBox.openPopup()
      if comboBox.popupOpen():
        comboBox.setPopupHoveredIndex(comboBox.indexOfSelectedItem())
        changed = true
    result.consumed = true
    result.needsRender = changed
    return

  if closeOpenComboPopups(root.value, nil):
    clearTrackedMouseDownComboBox()
    result.needsRender = true

proc handleComboBoxMouseUp(
    window: NSWindow, x: float32, y: float32, generated: bool
): tuple[consumed: bool, needsRender: bool] =
  if trackedMouseDownComboBoxId.isNil:
    return
  let comboBox = ownFromId[NSComboBox](trackedMouseDownComboBoxId)
  let trackedItemIndex = trackedMouseDownComboPopupItemIndex
  clearTrackedMouseDownComboBox()
  result.consumed = true
  if comboBox.isNil or (not comboBox.popupOpen()):
    return

  let root = ensureContentView(window)
  if root.isNil:
    comboBox.closePopup()
    result.needsRender = true
    return

  var comboFrame = nsRect(0.0, 0.0, 0.0, 0.0)
  let found = findViewScreenFrame(
    root.value, comboBox.value, false, 0.0, 0.0, 0.0, false, comboFrame
  )
  if found:
    let itemIndex = comboBoxPopupItemIndexAtPoint(comboBox, comboFrame, x, y)
    if (not generated) and trackedItemIndex >= 0 and itemIndex == trackedItemIndex:
      comboBox.activateItemAtIndex(itemIndex)

  comboBox.closePopup()
  result.needsRender = true

proc buttonShouldBeHighlighted(window: NSWindow, x: float32, y: float32): bool =
  if trackedMouseDownButtonId.isNil:
    return false
  let root = ensureContentView(window)
  if root.isNil:
    return false
  let hit = hitTestButton(root.value, x, y, false, 0.0, 0.0, 0.0, false)
  (not hit.isNil) and hit == trackedMouseDownButtonId

proc updateTrackedButtonHighlight(window: NSWindow, x: float32, y: float32): bool =
  if trackedMouseDownButtonId.isNil:
    return false
  let button = ownFromId[NSButton](trackedMouseDownButtonId)
  if button.isNil:
    clearTrackedMouseDownButton()
    return false
  let shouldHighlight = buttonShouldBeHighlighted(window, x, y)
  if button.isHighlighted() == shouldHighlight:
    return false
  button.setHighlighted(shouldHighlight)
  true

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

proc appKitInputPos(
    window: NSWindow, nativeWindow: siwinshim.Window, rawPos: Vec2
): Vec2 =
  ## Siwin reports input with a top-left origin. AppKit event dispatch here uses
  ## a bottom-left window coordinate system, so convert before queuing events.
  let logicalPos = logicalInputPos(nativeWindow, rawPos)
  let logicalSize = nativeWindow.logicalSize()
  let height = max(logicalSize.y, 0.0)
  if height <= 0.0:
    return logicalPos
  vec2(logicalPos.x, height - logicalPos.y)

proc renderWindow(window: NSWindow) =
  let nativeWindow = window.windowNativeWindow()
  let renderer = window.windowRenderer()
  if renderer.isNil or nativeWindow.isNil:
    return

  let nativeLogicalSize = nativeWindow.logicalSize()
  var logicalSize = vec2(max(nativeLogicalSize.x, 1.0), max(nativeLogicalSize.y, 1.0))
  var frame = window.windowFrame()
  if abs(frame.size.width - logicalSize.x) > 1.01 or
      abs(frame.size.height - logicalSize.y) > 1.01:
    frame.size = nsSize(logicalSize.x, logicalSize.y)
    window.windowFrame frame
  else:
    logicalSize = vec2(max(frame.size.width, 1.0), max(frame.size.height, 1.0))
  let root = ensureContentView(window)
  root.setFrame(nsRect(0'f32, 0'f32, logicalSize.x.float32, logicalSize.y.float32))
  var renders = buildWindowRenders(window)
  if renders.isNil:
    return
  if shouldDebugRenderDump():
    dumpRenders(renders)

  renderer.beginFrame()
  renderer.renderFrame(renders, logicalSize)
  renderer.endFrame()

proc installWindowFlushHook() =
  if windowFlushHookInstalled:
    return
  setWindowFlushHook(
    proc(windowId: IDPtr) =
      if windowId.isNil:
        return
      let window = ownFromId[NSWindow](windowId)
      if window.isNil:
        return
      renderWindow(window)
  )
  windowFlushHookInstalled = true

proc debugDumpWindowRenderTree*(window: NSWindow) =
  let renders = buildWindowRenders(window)
  if renders.isNil:
    echo "[appkit] debug dump: no render tree"
  else:
    dumpRenders(renders)

proc debugBuildWindowRenders*(window: NSWindow): Renders =
  buildWindowRenders(window)

proc cleanupFailedWindowInit(window: NSWindow) =
  if not window.windowNativeWindow().isNil:
    try:
      siwinshim.close(window.windowNativeWindow())
    except Exception:
      discard
  window.windowRenderer nil
  window.windowNativeWindow nil
  window.windowNativeReady false
  window.windowVisibleRequested false
  window.windowClosed true

proc ensureNativeWindow*(window: NSWindow) =
  installWindowFlushHook()
  if window.windowNativeReady():
    return

  try:
    let frame = window.windowFrame()
    let size =
      ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

    window.windowNativeWindow(
      siwinshim.newSiwinWindow(size = size, title = $window.windowTitle(), vsync = true)
    )
    window.windowAutoScale(window.windowNativeWindow().configureUiScale())
    window.windowRenderer(
      figrender.newFigRenderer(
        atlasSize = 1024, backendState = siwinshim.SiwinRenderBackend()
      )
    )
    var renderer = window.windowRenderer()
    renderer.setupBackend(window.windowNativeWindow())
    window.windowRenderer renderer

    window.windowNativeWindow.eventsHandler = siwinshim.WindowEventsHandler(
      onClose: proc(e: siwinshim.CloseEvent) =
        discard e
        clearTrackedMouseDownButton()
        clearTrackedMouseDownComboBox()
        discard window.windowShouldClose(window.NSObject)
        window.windowClosed(true),
      onResize: proc(e: siwinshim.ResizeEvent) =
        discard e
        window.windowNativeWindow().refreshUiScale(window.windowAutoScale())
        renderWindow(window),
      onClick: proc(e: siwinshim.ClickEvent) =
        discard e,
      onMouseMove: proc(e: siwinshim.MouseMoveEvent) =
        let nativeWindow = window.windowNativeWindow()
        if nativeWindow.isNil:
          return
        let logicalPos = appKitInputPos(window, nativeWindow, e.pos)
        let appEvent = mouseMoveEventFromSiwin(
          window.windowNumber(),
          nsPoint(logicalPos.x, logicalPos.y),
          e,
          nativeWindow.keyboard.modifiers,
          nativeWindow.mouse.pressed,
        )
        if not appEvent.isNil:
          window.postEvent(appEvent, false)
      ,
      onMouseButton: proc(e: siwinshim.MouseButtonEvent) =
        let nativeWindow =
          if e.window.isNil:
            window.windowNativeWindow()
          else:
            e.window
        if nativeWindow.isNil:
          return
        let logicalPos = appKitInputPos(window, nativeWindow, nativeWindow.mouse.pos)
        let appEvent = mouseButtonEventFromSiwin(
          window.windowNumber(),
          nsPoint(logicalPos.x, logicalPos.y),
          e,
          nativeWindow.keyboard.modifiers,
        )
        if not appEvent.isNil:
          window.postEvent(appEvent, false)
      ,
      onScroll: proc(e: siwinshim.ScrollEvent) =
        let nativeWindow =
          if e.window.isNil:
            window.windowNativeWindow()
          else:
            e.window
        if nativeWindow.isNil:
          return
        let logicalPos = appKitInputPos(window, nativeWindow, nativeWindow.mouse.pos)
        let appEvent = scrollEventFromSiwin(
          window.windowNumber(),
          nsPoint(logicalPos.x, logicalPos.y),
          e,
          nativeWindow.keyboard.modifiers,
        )
        if not appEvent.isNil:
          window.postEvent(appEvent, false)
      ,
      onRender: proc(e: siwinshim.RenderEvent) =
        discard e
        renderWindow(window),
      onKey: proc(e: siwinshim.KeyEvent) =
        let nativeWindow =
          if e.window.isNil:
            window.windowNativeWindow()
          else:
            e.window
        let logicalPos =
          if nativeWindow.isNil:
            vec2(0.0, 0.0)
          else:
            appKitInputPos(window, nativeWindow, nativeWindow.mouse.pos)
        let appEvent = keyEventFromSiwin(
          window.windowNumber(), nsPoint(logicalPos.x, logicalPos.y), e, @ns"", @ns""
        )
        if not appEvent.isNil:
          window.postEvent(appEvent, false)
      ,
      onTextInput: proc(e: siwinshim.TextInputEvent) =
        let nativeWindow =
          if e.window.isNil:
            window.windowNativeWindow()
          else:
            e.window
        if nativeWindow.isNil:
          return
        let logicalPos = appKitInputPos(window, nativeWindow, nativeWindow.mouse.pos)
        let appEvent = textInputEventFromSiwin(
          window.windowNumber(),
          nsPoint(logicalPos.x, logicalPos.y),
          e,
          nativeWindow.keyboard.modifiers,
        )
        if not appEvent.isNil:
          window.postEvent(appEvent, false)
      ,
    )

    window.windowNativeWindow().firstStep()
    window.windowNativeWindow().refreshUiScale(window.windowAutoScale())
    window.windowNativeReady true
  except Exception as exc:
    cleanupFailedWindowInit(window)
    raise newException(CatchableError, "window backend init failed: " & exc.msg)
