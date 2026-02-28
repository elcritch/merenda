import std/[os, strutils, unicode]

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim as siwinshim

import ./runtime
import ./graphicscontexts
import ./views
import ./windows
import ./clipviews
import ./buttons
import ./cells
import ./images
import ./imageviews
import ./textfields
import ./comboboxes
import ./events

var trackedMouseDownButtonId {.threadvar.}: IDPtr
var trackedMouseDownComboBoxId {.threadvar.}: IDPtr
var trackedMouseDownComboPopupItemIndex {.threadvar.}: int

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
    0'f32, 0'f32, frame.size.width.float32, frame.size.height.float32
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

proc drawsBg(view: NSView): bool =
  if view.isKindOfClass(NSClipView):
    let clip = asRetainedType[NSClipView](view)
    result = clip.drawsBackground()
    return
  if not view.isKindOfClass(NSTextField):
    return false
  let textField = asRetainedType[NSTextField](view)
  result = textField.drawsBackground()

const
  DefaultButtonFontSize = 13.0'f32
  DefaultLabelFontSize = 13.0'f32
  ComboBoxPopupZLevel = 8.ZLevel
  ComboBoxArrowZoneMinWidth = 16.0'f32
  ComboBoxArrowZoneMaxWidth = 22.0'f32

var activeRenders {.threadvar.}: ptr Renders
var activeRenderParentIdx {.threadvar.}: FigIdx
var activeRenderLocalBox {.threadvar.}: NSRect
var activeRenderScreenBox {.threadvar.}: NSRect
var activeRenderContextActive {.threadvar.}: bool

type ButtonBezelVisualKind = enum
  roundedButtonBezel
  regularSquareButtonBezel

proc isSwitchButton(button: NSButton): bool =
  if button.isNil:
    return false
  button.buttonType().int == NSSwitchButton

proc buttonBezelVisualKind(button: NSButton): ButtonBezelVisualKind =
  if button.isNil:
    return roundedButtonBezel
  case button.bezelStyle()
  of NSRegularSquareBezelStyle: regularSquareButtonBezel
  else: roundedButtonBezel

proc buttonVisualState(view: NSView): int =
  if not view.isKindOfClass(NSButton):
    return NSOffState
  let button = asRetainedType[NSButton](view)
  if button.isHighlighted() and button.highlightsBy() != NSNoCellMask:
    return NSOnState
  if (
    button.showsStateBy() and
    (NSContentsCellMask or NSChangeGrayCellMask or NSChangeBackgroundCellMask)
  ) != 0:
    return button.state()
  NSOffState

proc aquaButtonFill(kind: ButtonBezelVisualKind, state: int): Fill =
  case kind
  of regularSquareButtonBezel:
    case state
    of NSOnState:
      linear(
        nsColor(0.80, 0.80, 0.80, 1.0).toFigRgba(),
        nsColor(0.70, 0.70, 0.70, 1.0).toFigRgba(),
        axis = fgaY,
      )
    of NSMixedState:
      linear(
        nsColor(0.84, 0.84, 0.84, 1.0).toFigRgba(),
        nsColor(0.74, 0.74, 0.74, 1.0).toFigRgba(),
        axis = fgaY,
      )
    else:
      linear(
        nsColor(0.90, 0.90, 0.90, 1.0).toFigRgba(),
        nsColor(0.80, 0.80, 0.80, 1.0).toFigRgba(),
        axis = fgaY,
      )
  of roundedButtonBezel:
    case state
    of NSOnState:
      linear(
        nsColor(0.84, 0.84, 0.84, 1.0).toFigRgba(),
        nsColor(0.72, 0.72, 0.72, 1.0).toFigRgba(),
        nsColor(0.62, 0.62, 0.62, 1.0).toFigRgba(),
        axis = fgaY,
        midPos = 132'u8,
      )
    of NSMixedState:
      linear(
        nsColor(0.90, 0.90, 0.90, 1.0).toFigRgba(),
        nsColor(0.80, 0.80, 0.80, 1.0).toFigRgba(),
        nsColor(0.72, 0.72, 0.72, 1.0).toFigRgba(),
        axis = fgaY,
        midPos = 132'u8,
      )
    else:
      linear(
        nsColor(0.97, 0.97, 0.97, 1.0).toFigRgba(),
        nsColor(0.86, 0.86, 0.86, 1.0).toFigRgba(),
        nsColor(0.76, 0.76, 0.76, 1.0).toFigRgba(),
        axis = fgaY,
        midPos = 132'u8,
      )

proc aquaButtonStroke(kind: ButtonBezelVisualKind, state: int): Fill =
  case kind
  of regularSquareButtonBezel:
    nsColor(0.83, 0.83, 0.83, 1.0).solidFill()
  of roundedButtonBezel:
    case state
    of NSOnState:
      linear(
        nsColor(0.58, 0.58, 0.58, 1.0).toFigRgba(),
        nsColor(0.47, 0.47, 0.47, 1.0).toFigRgba(),
        axis = fgaY,
      )
    of NSMixedState:
      linear(
        nsColor(0.62, 0.62, 0.62, 1.0).toFigRgba(),
        nsColor(0.52, 0.52, 0.52, 1.0).toFigRgba(),
        axis = fgaY,
      )
    else:
      linear(
        nsColor(0.68, 0.68, 0.68, 1.0).toFigRgba(),
        nsColor(0.55, 0.55, 0.55, 1.0).toFigRgba(),
        axis = fgaY,
      )

proc viewShadows(view: NSView): array[ShadowCount, RenderShadow] =
  result = noRenderShadows()
  if view.isKindOfClass(NSButton):
    return
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
  if view.isKindOfClass(NSClipView):
    let clip = asRetainedType[NSClipView](view)
    let color = clip.backgroundColor()
    let shouldDraw = clip.drawsBackground()
    if shouldDraw:
      return color.solidFill()
    return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
  if view.isKindOfClass(NSButton):
    return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
  if view.isKindOfClass(NSTextField):
    let textField = asRetainedType[NSTextField](view)
    let drawsBackground = textField.drawsBackground()
    let backgroundColor = textField.backgroundColor()
    if drawsBackground:
      return backgroundColor.solidFill()
    return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
  view.viewBackgroundColor().solidFill()

proc viewStrokeFill(view: NSView): Fill =
  if view.isKindOfClass(NSClipView):
    return nsColor(0.64, 0.70, 0.80, 1.0).solidFill()
  if view.isKindOfClass(NSButton):
    return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
  if view.isKindOfClass(NSTextField):
    if not drawsBg(view):
      return nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
    return nsColor(0.64, 0.70, 0.80, 1.0).solidFill()
  nsColor(0.34, 0.42, 0.56, 0.28).solidFill()

proc viewCornerRadius(view: NSView): float32 =
  if view.isKindOfClass(NSButton):
    return 0.0
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
    let button = asRetainedType[NSButton](view)
    if isSwitchButton(button):
      return
    if buttonBezelVisualKind(button) == regularSquareButtonBezel:
      return
    glossFill = linear(
      nsColor(1.0, 1.0, 1.0, 0.30).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.18).toFigRgba(),
      nsColor(1.0, 1.0, 1.0, 0.04).toFigRgba(),
      axis = fgaY,
      midPos = 150'u8,
    )
    glossHeight = box.size.height * 0.48
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

const textLayoutBoundsEpsilon = 0.75'f32

type TextLayoutDebugMetrics* = object
  hasLayout*: bool
  fitsTextBox*: bool
  controlBox*: NSRect
  textBox*: NSRect
  textBounds*: NSRect
  glyphCount*: int

type ImageLayoutDebugMetrics* = object
  hasImage*: bool
  imageId*: ImageId
  imageBox*: NSRect

proc switchIndicatorRect(controlBox: NSRect): NSRect

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

proc comboBoxArrowZoneRect(controlBox: NSRect): NSRect =
  let arrowWidth = clamp(
    controlBox.size.height * 0.8, ComboBoxArrowZoneMinWidth, ComboBoxArrowZoneMaxWidth
  )
  let zoneWidth = min(arrowWidth, max(controlBox.size.width, 0.0))
  nsRect(
    controlBox.origin.x + controlBox.size.width - zoneWidth,
    controlBox.origin.y,
    zoneWidth,
    controlBox.size.height,
  )

proc comboBoxPopupItemHeight(comboBox: NSComboBox): float32 =
  max(comboBox.itemHeight() + 6.0, 18.0)

proc comboBoxVisiblePopupItems(comboBox: NSComboBox): int =
  let count = comboBox.numberOfItems()
  if count <= 0:
    return 0
  let requested = comboBox.numberOfVisibleItems()
  if requested <= 0:
    return count
  min(count, requested)

proc comboBoxPopupFrame(comboBox: NSComboBox, controlBox: NSRect): NSRect =
  let itemCount = comboBoxVisiblePopupItems(comboBox)
  if itemCount <= 0:
    return nsRect(controlBox.origin.x, controlBox.origin.y, 0.0, 0.0)
  let popupHeight = comboBoxPopupItemHeight(comboBox) * itemCount.float32 + 2.0
  nsRect(
    controlBox.origin.x,
    controlBox.origin.y + controlBox.size.height,
    max(controlBox.size.width, 0.0),
    popupHeight,
  )

proc comboBoxPopupFirstItemIndex(comboBox: NSComboBox): int =
  let total = comboBox.numberOfItems()
  let visible = comboBoxVisiblePopupItems(comboBox)
  if total <= 0 or visible <= 0:
    return 0
  if total <= visible:
    return 0
  let selected = comboBox.indexOfSelectedItem()
  if selected < 0:
    return 0
  clamp(selected - visible + 1, 0, total - visible)

proc comboBoxPopupItemRect(
    comboBox: NSComboBox, controlBox: NSRect, itemIndex: int
): NSRect =
  let firstIndex = comboBoxPopupFirstItemIndex(comboBox)
  let visibleIndex = itemIndex - firstIndex
  if visibleIndex < 0 or visibleIndex >= comboBoxVisiblePopupItems(comboBox):
    return nsRect(controlBox.origin.x, controlBox.origin.y, 0.0, 0.0)
  let popupBox = comboBoxPopupFrame(comboBox, controlBox)
  let itemHeight = comboBoxPopupItemHeight(comboBox)
  let yTop =
    popupBox.origin.y + popupBox.size.height - 1.0 - visibleIndex.float32 * itemHeight
  nsRect(
    popupBox.origin.x + 1.0,
    yTop - itemHeight,
    max(popupBox.size.width - 2.0, 0.0),
    max(itemHeight, 0.0),
  )

proc comboBoxPopupItemIndexAtPoint(
    comboBox: NSComboBox, controlBox: NSRect, x: float32, y: float32
): int =
  let popupBox = comboBoxPopupFrame(comboBox, controlBox)
  if popupBox.size.width <= 0.0 or popupBox.size.height <= 0.0:
    return -1
  if not popupBox.contains(x, y):
    return -1
  let itemHeight = comboBoxPopupItemHeight(comboBox)
  if itemHeight <= 0.0:
    return -1
  let fromTop = (popupBox.origin.y + popupBox.size.height - y - 1.0)
  let visibleIndex = int(fromTop / itemHeight)
  if visibleIndex < 0 or visibleIndex >= comboBoxVisiblePopupItems(comboBox):
    return -1
  let itemIndex = comboBoxPopupFirstItemIndex(comboBox) + visibleIndex
  if itemIndex < 0 or itemIndex >= comboBox.numberOfItems():
    return -1
  itemIndex

proc textBoxForView(view: NSView, box: NSRect): NSRect =
  if view.isKindOfClass(NSButton):
    let button = asRetainedType[NSButton](view)
    let control = asRetainedType[NSControl](button)
    let cell = control.cell()
    if not cell.isNil:
      let localTitleRect = cell.titleRectForBounds(button.bounds())
      if isSwitchButton(button):
        let indicator = switchIndicatorRect(box)
        let switchLeftInset =
          max((indicator.origin.x - box.origin.x) + indicator.size.width + 6.0, 0.0)
        return nsRect(
          box.origin.x + switchLeftInset,
          box.origin.y + localTitleRect.origin.y,
          max(box.size.width - switchLeftInset, 0.0),
          localTitleRect.size.height,
        )
      return nsRect(
        box.origin.x + localTitleRect.origin.x,
        box.origin.y + localTitleRect.origin.y,
        localTitleRect.size.width,
        localTitleRect.size.height,
      )
    return box

  if view.isKindOfClass(NSComboBox):
    let arrowZone = comboBoxArrowZoneRect(box)
    let leftInset = 10.0'f32
    let rightInset = max((arrowZone.origin.x - box.origin.x) + 4.0, leftInset + 4.0)
    return nsRect(
      box.origin.x + leftInset,
      box.origin.y + 4.0,
      max(box.size.width - rightInset - leftInset, 0.0),
      max(box.size.height - 8.0, 0.0),
    )

  if view.isKindOfClass(NSTextField) and drawsBg(view):
    return nsRect(
      box.origin.x + 10.0,
      box.origin.y + 4.0,
      max(box.size.width - 20.0, 0.0),
      max(box.size.height - 8.0, 0.0),
    )

  box

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

proc textLayoutForView(
    view: NSView, box: NSRect
): tuple[ok: bool, layout: GlyphArrangement] =
  if box.size.width <= 2 or box.size.height <= 2:
    return (false, default(GlyphArrangement))
  if not ensureAppKitFont():
    return (false, default(GlyphArrangement))

  if view.isKindOfClass(NSTextField):
    let textField = asRetainedType[NSTextField](view)
    let textValue = $textField.stringValue()
    let textColor = textField.textColor()
    let textAlign = toFontHorizontal(textField.alignment())
    if textValue.len == 0:
      return (false, default(GlyphArrangement))
    let fitted = fitSingleLineText(
      textValue,
      fs(appkitFont(DefaultLabelFontSize), textColor.toFigColor()),
      textAlign,
      box,
    )
    if fitted.text.len == 0:
      return (false, default(GlyphArrangement))
    if shouldDebugRenderDump():
      let suffix =
        if fitted.text == textValue:
          ""
        else:
          " (fitted: \"" & fitted.text & "\")"
      echo "[appkit] textfield layout runes=",
        fitted.layout.runes.len, " text=\"", textValue, "\"", suffix
    return (true, fitted.layout)

  if view.isKindOfClass(NSButton):
    let button = asRetainedType[NSButton](view)
    let title = $button.title()
    let textAlign = toFontHorizontal(button.alignment())
    if title.len == 0:
      return (false, default(GlyphArrangement))
    let fitted = fitSingleLineText(
      title,
      fs(
        appkitFont(DefaultButtonFontSize),
        (
          if button.isEnabled():
            nsColor(0.08, 0.08, 0.08, 1.0)
          else:
            nsColor(0.45, 0.45, 0.45, 1.0)
        ).toFigColor(),
      ),
      textAlign,
      box,
    )
    if fitted.text.len == 0:
      return (false, default(GlyphArrangement))
    if shouldDebugRenderDump():
      let suffix =
        if fitted.text == title:
          ""
        else:
          " (fitted: \"" & fitted.text & "\")"
      echo "[appkit] button layout runes=",
        fitted.layout.runes.len, " title=\"", title, "\"", suffix

    return (true, fitted.layout)

  (false, default(GlyphArrangement))

proc switchIndicatorRect(controlBox: NSRect): NSRect =
  let side = clamp(controlBox.size.height - 6.0, 10.0, 13.0)
  nsRect(
    controlBox.origin.x + 3.0,
    controlBox.origin.y + (controlBox.size.height - side) * 0.5,
    side,
    side,
  )

proc addSwitchButtonIndicator(
    renders: var Renders, parentIdx: FigIdx, button: NSButton, controlBox: NSRect
) =
  if button.isNil:
    return
  let indicatorBox = switchIndicatorRect(controlBox)
  if indicatorBox.size.width <= 0.0 or indicatorBox.size.height <= 0.0:
    return

  let state = buttonVisualState(asRetainedType[NSView](button))
  let enabled = button.isEnabled()
  let strokeColor =
    if enabled:
      nsColor(0.43, 0.47, 0.55, 1.0)
    else:
      nsColor(0.58, 0.58, 0.58, 1.0)
  var fillColor =
    if state == NSOnState:
      nsColor(0.90, 0.94, 0.99, 1.0)
    elif state == NSMixedState:
      nsColor(0.94, 0.94, 0.96, 1.0)
    else:
      nsColor(1.0, 1.0, 1.0, 1.0)
  if button.isHighlighted():
    fillColor = nsColor(0.82, 0.86, 0.92, 1.0)

  let indicatorFig = Fig(
    kind: nkRectangle,
    childCount: 0,
    screenBox: rect(
      indicatorBox.origin.x, indicatorBox.origin.y, indicatorBox.size.width,
      indicatorBox.size.height,
    ),
    fill: fillColor.solidFill(),
    corners: uniformCorners(2.8),
    stroke: RenderStroke(weight: 1.0, fill: strokeColor.solidFill()),
  )
  let indicatorIdx = renders.addChild(0.ZLevel, parentIdx, indicatorFig)

  if state == NSOnState:
    let markSide = max(indicatorBox.size.width - 6.0, 2.0)
    let markBox = rect(
      indicatorBox.origin.x + (indicatorBox.size.width - markSide) * 0.5,
      indicatorBox.origin.y + (indicatorBox.size.height - markSide) * 0.5,
      markSide,
      markSide,
    )
    discard renders.addChild(
      0.ZLevel,
      indicatorIdx,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        screenBox: markBox,
        fill: (
          if enabled:
            nsColor(0.23, 0.27, 0.34, 1.0)
          else:
            nsColor(0.58, 0.58, 0.58, 1.0)
        ).solidFill(),
        corners: uniformCorners(1.5),
        stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
      ),
    )
  elif state == NSMixedState:
    let barHeight = max(indicatorBox.size.height * 0.16, 2.0)
    let barWidth = max(indicatorBox.size.width - 4.0, 2.0)
    let barBox = rect(
      indicatorBox.origin.x + (indicatorBox.size.width - barWidth) * 0.5,
      indicatorBox.origin.y + (indicatorBox.size.height - barHeight) * 0.5,
      barWidth,
      barHeight,
    )
    discard renders.addChild(
      0.ZLevel,
      indicatorIdx,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        screenBox: barBox,
        fill: nsColor(0.23, 0.26, 0.33, 1.0).solidFill(),
        corners: uniformCorners(1.0),
        stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
      ),
    )

proc addComboBoxAffordance(
    renders: var Renders, parentIdx: FigIdx, comboBox: NSComboBox, controlBox: NSRect
) =
  if comboBox.isNil:
    return
  let arrowZone = comboBoxArrowZoneRect(controlBox)
  if arrowZone.size.width <= 0.0 or arrowZone.size.height <= 0.0:
    return

  discard renders.addChild(
    0.ZLevel,
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(
        arrowZone.origin.x, arrowZone.origin.y, arrowZone.size.width,
        arrowZone.size.height,
      ),
      fill: linear(
        nsColor(0.95, 0.95, 0.97, 1.0).toFigRgba(),
        nsColor(0.86, 0.88, 0.92, 1.0).toFigRgba(),
        axis = fgaY,
      ),
      corners: uniformCorners(0.0),
      stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
    ),
  )

  discard renders.addChild(
    0.ZLevel,
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(
        arrowZone.origin.x, arrowZone.origin.y + 1.0, 1.0, arrowZone.size.height - 2.0
      ),
      fill: nsColor(0.66, 0.71, 0.80, 1.0).solidFill(),
      corners: uniformCorners(0.0),
      stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
    ),
  )

  if ensureAppKitFont():
    let arrowBox = nsRect(
      arrowZone.origin.x,
      arrowZone.origin.y + 2.0,
      arrowZone.size.width,
      max(arrowZone.size.height - 4.0, 0.0),
    )
    let arrowLayout = singleLineLayout(
      "v",
      fs(appkitFont(11.0), nsColor(0.25, 0.30, 0.38, 1.0).toFigColor()),
      FontHorizontal.Center,
      arrowBox,
    )
    discard renders.addChild(
      0.ZLevel,
      parentIdx,
      Fig(
        kind: nkText,
        childCount: 0,
        screenBox: rect(
          arrowBox.origin.x, arrowBox.origin.y, arrowBox.size.width,
          arrowBox.size.height,
        ),
        fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
        textLayout: arrowLayout,
      ),
    )

proc addComboBoxPopup(renders: var Renders, comboBox: NSComboBox, controlBox: NSRect) =
  if comboBox.isNil or (not comboBox.popupOpen()):
    return
  let popupBox = comboBoxPopupFrame(comboBox, controlBox)
  if popupBox.size.width <= 0.0 or popupBox.size.height <= 0.0:
    return
  var popupShadows = noRenderShadows()
  popupShadows[0] = RenderShadow(
    style: DropShadow,
    blur: 4.0,
    spread: 0.0,
    x: 0.0,
    y: 2.0,
    fill: nsColor(0.0, 0.0, 0.0, 0.20).toFigColor(),
  )

  let popupIdx = renders.addRoot(
    ComboBoxPopupZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(
        popupBox.origin.x, popupBox.origin.y, popupBox.size.width, popupBox.size.height
      ),
      fill: nsColor(0.99, 0.99, 1.0, 1.0).solidFill(),
      corners: uniformCorners(4.0),
      shadows: popupShadows,
      stroke:
        RenderStroke(weight: 1.0, fill: nsColor(0.60, 0.67, 0.78, 1.0).solidFill()),
    ),
  )

  let firstItem = comboBoxPopupFirstItemIndex(comboBox)
  let lastItem = firstItem + comboBoxVisiblePopupItems(comboBox)
  let selectedItem = comboBox.indexOfSelectedItem()
  let hoveredItem = comboBox.popupHoveredIndex()
  for itemIndex in firstItem ..< lastItem:
    let itemBox = comboBoxPopupItemRect(comboBox, controlBox, itemIndex)
    if itemBox.size.width <= 0.0 or itemBox.size.height <= 0.0:
      continue
    let isSelected = itemIndex == selectedItem
    let isHovered = itemIndex == hoveredItem
    if isSelected or isHovered:
      discard renders.addChild(
        ComboBoxPopupZLevel,
        popupIdx,
        Fig(
          kind: nkRectangle,
          childCount: 0,
          screenBox: rect(
            itemBox.origin.x, itemBox.origin.y, itemBox.size.width, itemBox.size.height
          ),
          fill: (
            if isHovered:
              nsColor(0.78, 0.87, 1.0, 1.0)
            else:
              nsColor(0.88, 0.93, 1.0, 1.0)
          ).solidFill(),
          corners: uniformCorners(2.0),
          stroke:
            RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
        ),
      )

    if not ensureAppKitFont():
      continue
    let textValue = $comboBox.itemObjectValueAtIndex(itemIndex)
    if textValue.len == 0:
      continue
    let textBox = nsRect(
      itemBox.origin.x + 6.0,
      itemBox.origin.y + 2.0,
      max(itemBox.size.width - 12.0, 0.0),
      max(itemBox.size.height - 4.0, 0.0),
    )
    let fitted = fitSingleLineText(
      textValue,
      fs(appkitFont(DefaultLabelFontSize), nsColor(0.08, 0.08, 0.08, 1.0).toFigColor()),
      FontHorizontal.Left,
      textBox,
    )
    if fitted.text.len == 0:
      continue
    discard renders.addChild(
      ComboBoxPopupZLevel,
      popupIdx,
      Fig(
        kind: nkText,
        childCount: 0,
        screenBox: rect(
          textBox.origin.x, textBox.origin.y, textBox.size.width, textBox.size.height
        ),
        fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
        textLayout: fitted.layout,
      ),
    )

proc imageLayoutForView(view: NSView, box: NSRect): ImageLayoutDebugMetrics =
  if not view.isKindOfClass(NSImageView):
    return
  let imageView = asRetainedType[NSImageView](view)
  if imageView.isNil:
    return
  let image = imageView.image()
  if image.isNil:
    return
  let imageId = image.imageId()
  if imageId.int == 0:
    return
  let localRect =
    imageView.imageRectForBounds(nsRect(0.0, 0.0, box.size.width, box.size.height))
  if localRect.size.width <= 0.0 or localRect.size.height <= 0.0:
    return
  result.hasImage = true
  result.imageId = imageId
  result.imageBox = nsRect(
    box.origin.x + localRect.origin.x,
    box.origin.y + localRect.origin.y,
    localRect.size.width,
    localRect.size.height,
  )

proc hasActiveRenderContext(): bool =
  activeRenderContextActive and (not activeRenders.isNil)

proc addTextLayoutForActiveView(view: NSView) =
  if not hasActiveRenderContext():
    return
  let textBox = textBoxForView(view, activeRenderLocalBox)
  let textLayout = textLayoutForView(view, textBox)
  if not textLayout.ok:
    return
  discard activeRenders[].addChild(
    0.ZLevel,
    activeRenderParentIdx,
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

proc addImageLayoutForActiveView(view: NSView) =
  if not hasActiveRenderContext():
    return
  let imageLayout = imageLayoutForView(view, activeRenderLocalBox)
  if not imageLayout.hasImage:
    return
  let imageFill = nsColor(1.0, 1.0, 1.0, 1.0).solidFill()
  discard activeRenders[].addChild(
    0.ZLevel,
    activeRenderParentIdx,
    Fig(
      kind: nkImage,
      childCount: 0,
      screenBox: rect(
        imageLayout.imageBox.origin.x, imageLayout.imageBox.origin.y,
        imageLayout.imageBox.size.width, imageLayout.imageBox.size.height,
      ),
      fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill(),
      image: ImageStyle(id: imageLayout.imageId, fill: imageFill),
    ),
  )

proc drawButtonDecorationsForActiveView(button: NSButton) =
  if not hasActiveRenderContext() or button.isNil:
    return
  let buttonView = ownFromId[NSView](button.value)
  if buttonView.isNil:
    return
  if isSwitchButton(button):
    activeRenders[].addSwitchButtonIndicator(
      activeRenderParentIdx, button, activeRenderLocalBox
    )
  addTextLayoutForActiveView(buttonView)

proc drawTextFieldDecorationsForActiveView(textField: NSTextField) =
  if not hasActiveRenderContext() or textField.isNil:
    return
  let textFieldView = ownFromId[NSView](textField.value)
  if textFieldView.isNil:
    return
  addAquaGlossOverlay(
    activeRenders[], activeRenderParentIdx, textFieldView, activeRenderLocalBox
  )
  addTextLayoutForActiveView(textFieldView)

proc drawComboBoxDecorationsForActiveView(comboBox: NSComboBox) =
  if not hasActiveRenderContext() or comboBox.isNil:
    return
  let comboView = ownFromId[NSView](comboBox.value)
  if comboView.isNil:
    return
  activeRenders[].addComboBoxAffordance(
    activeRenderParentIdx, comboBox, activeRenderLocalBox
  )
  addAquaGlossOverlay(
    activeRenders[], activeRenderParentIdx, comboView, activeRenderLocalBox
  )
  addTextLayoutForActiveView(comboView)
  activeRenders[].addComboBoxPopup(comboBox, activeRenderScreenBox)

proc drawImageDecorationsForActiveView(imageView: NSImageView) =
  if imageView.isNil:
    return
  let imageViewAsView = ownFromId[NSView](imageView.value)
  if imageViewAsView.isNil:
    return
  addImageLayoutForActiveView(imageViewAsView)

proc debugTextLayoutMetricsForView*(view: NSView): TextLayoutDebugMetrics =
  if view.isNil:
    return
  let frame = view.viewFrame()
  result.controlBox = nsRect(
    frame.origin.x,
    frame.origin.y,
    max(frame.size.width, 0.0),
    max(frame.size.height, 0.0),
  )
  result.textBox = textBoxForView(view, result.controlBox)
  let textLayout = textLayoutForView(view, result.textBox)
  result.hasLayout = textLayout.ok
  if not textLayout.ok:
    return
  result.glyphCount = textLayout.layout.runes.len
  result.fitsTextBox = layoutFitsTextBox(textLayout.layout, result.textBox)
  let bounds = textBoundsForLayout(textLayout.layout, result.textBox)
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
  if view.viewHidden():
    return
  let frame = view.viewFrame()

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
      if view.isKindOfClass(NSClipView):
        {NfClipContent}
      else:
        {}
    ),
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
  let drawTransformIdx = renders.addChild(
    0.ZLevel,
    idx,
    Fig(
      kind: nkTransform,
      childCount: 0,
      transform: viewLocalToScreenTransform(view, box, localBox),
    ),
  )

  let previousRenders = activeRenders
  let previousParentIdx = activeRenderParentIdx
  let previousLocalBox = activeRenderLocalBox
  let previousScreenBox = activeRenderScreenBox
  let previousContextActive = activeRenderContextActive
  activeRenders = addr renders
  activeRenderParentIdx = drawTransformIdx
  activeRenderLocalBox = localBox
  activeRenderScreenBox = box
  activeRenderContextActive = true
  var renderPort = RenderGraphicsPort(
    renders: addr renders, parentIdx: drawTransformIdx, drawBox: localBox
  )
  let renderGraphicsContext = NSGraphicsContext.graphicsContextWithGraphicsPort(
    cast[pointer](addr renderPort), view.isFlipped()
  )
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.setCurrentContext(renderGraphicsContext)
  pushCurrentFocusView(view)
  try:
    view.drawRect(view.bounds())
    if view.isKindOfClass(NSComboBox):
      drawComboBoxDecorationsForActiveView(asRetainedType[NSComboBox](view))
    elif view.isKindOfClass(NSTextField):
      drawTextFieldDecorationsForActiveView(asRetainedType[NSTextField](view))
    elif view.isKindOfClass(NSButton):
      drawButtonDecorationsForActiveView(asRetainedType[NSButton](view))
    if view.isKindOfClass(NSImageView):
      drawImageDecorationsForActiveView(asRetainedType[NSImageView](view))
  finally:
    discard popCurrentFocusView()
    NSGraphicsContext.restoreGraphicsState()
  activeRenders = previousRenders
  activeRenderParentIdx = previousParentIdx
  activeRenderLocalBox = previousLocalBox
  activeRenderScreenBox = previousScreenBox
  activeRenderContextActive = previousContextActive

  for child in view.viewSubviews():
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
  if view.viewHidden():
    return nil
  let frameSelf = view.viewFrame()

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
  if view.isKindOfClass(NSClipView) and not frame.contains(x, y):
    return nil

  let children = view.viewSubviews()
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
  if view.isNil or view.viewHidden():
    return nil
  let frameSelf = view.viewFrame()
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
  if view.isKindOfClass(NSClipView) and not frame.contains(x, y):
    return nil

  let children = view.viewSubviews()
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
  if view.isNil or view.viewHidden():
    return false
  let frameSelf = view.viewFrame()
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
  for child in view.viewSubviews():
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
  if view.isNil or view.viewHidden():
    return
  let frameSelf = view.viewFrame()
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

  let children = view.viewSubviews()
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
  let comboBox = asRetainedType[NSComboBox](view)
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
  if view.isNil or view.viewHidden():
    return
  if view.isKindOfClass(NSComboBox):
    let comboBox = asRetainedType[NSComboBox](view)
    if (not comboBox.isNil) and comboBox.popupOpen() and
        (exceptComboId.isNil or view.value != exceptComboId):
      comboBox.closePopup()
      changed = true
  for child in view.viewSubviews():
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
  if view.isNil or view.viewHidden():
    return
  let frameSelf = view.viewFrame()
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
    let comboBox = asRetainedType[NSComboBox](view)
    if (not comboBox.isNil) and comboBox.popupOpen():
      let hoverItem = comboBoxPopupItemIndexAtPoint(comboBox, frame, x, y)
      if comboBox.popupHoveredIndex() != hoverItem:
        comboBox.setPopupHoveredIndex(hoverItem)
        changed = true
  for child in view.viewSubviews():
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
    let control = asRetainedType[NSControl](comboBox)
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
  root.setFrame(0'f32, 0'f32, logicalSize.x.float32, logicalSize.y.float32)
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
        discard window.windowShouldClose(asRetainedType[NSObject](window))
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
        let logicalPos = logicalInputPos(nativeWindow, e.pos)
        let appEvent = mouseMoveEventFromSiwin(
          0,
          nsPoint(logicalPos.x, logicalPos.y),
          e,
          nativeWindow.keyboard.modifiers,
          nativeWindow.mouse.pressed,
        )
        if not appEvent.isNil:
          window.sendEvent(appEvent)
        var needsRender = false
        if updateOpenComboPopupHover(window, logicalPos.x, logicalPos.y):
          needsRender = true
        if siwinshim.MouseButton.left in nativeWindow.mouse.pressed:
          if updateTrackedButtonHighlight(window, logicalPos.x, logicalPos.y):
            needsRender = true
        if needsRender:
          renderWindow(window)
      ,
      onMouseButton: proc(e: siwinshim.MouseButtonEvent) =
        let nativeWindow =
          if e.window.isNil:
            window.windowNativeWindow()
          else:
            e.window
        if nativeWindow.isNil:
          return
        let logicalPos = logicalInputPos(nativeWindow, nativeWindow.mouse.pos)
        let appEvent = mouseButtonEventFromSiwin(
          0, nsPoint(logicalPos.x, logicalPos.y), e, nativeWindow.keyboard.modifiers
        )
        if not appEvent.isNil:
          window.sendEvent(appEvent)
        if e.button != siwinshim.MouseButton.left:
          return
        if e.pressed:
          let comboResult = handleComboBoxMouseDown(window, logicalPos.x, logicalPos.y)
          if comboResult.needsRender:
            renderWindow(window)
          if comboResult.consumed:
            return
          let root = ensureContentView(window)
          if root.isNil:
            clearTrackedMouseDownButton()
            return
          clearTrackedMouseDownComboBox()
          let hit = hitTestButton(
            root.value, logicalPos.x, logicalPos.y, false, 0.0, 0.0, 0.0, false
          )
          setTrackedMouseDownButton(hit)
          if trackedMouseDownButtonId.isNil:
            return
          let button = ownFromId[NSButton](trackedMouseDownButtonId)
          if button.isNil or not button.isEnabled():
            clearTrackedMouseDownButton()
            return
          button.setHighlighted(true)
          renderWindow(window)
          return

        let comboResult =
          handleComboBoxMouseUp(window, logicalPos.x, logicalPos.y, e.generated)
        if comboResult.needsRender:
          renderWindow(window)
        if comboResult.consumed:
          return
        if trackedMouseDownButtonId.isNil:
          return
        let button = ownFromId[NSButton](trackedMouseDownButtonId)
        if not button.isNil:
          button.setHighlighted(false)
          if not e.generated and
              buttonShouldBeHighlighted(window, logicalPos.x, logicalPos.y):
            button.performClick(window)
        clearTrackedMouseDownButton()
        renderWindow(window),
      onScroll: proc(e: siwinshim.ScrollEvent) =
        let nativeWindow =
          if e.window.isNil:
            window.windowNativeWindow()
          else:
            e.window
        if nativeWindow.isNil:
          return
        let logicalPos = logicalInputPos(nativeWindow, nativeWindow.mouse.pos)
        let appEvent = scrollEventFromSiwin(
          0, nsPoint(logicalPos.x, logicalPos.y), e, nativeWindow.keyboard.modifiers
        )
        if not appEvent.isNil:
          window.sendEvent(appEvent)
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
            logicalInputPos(nativeWindow, nativeWindow.mouse.pos)
        let appEvent =
          keyEventFromSiwin(0, nsPoint(logicalPos.x, logicalPos.y), e, @ns"", @ns"")
        if not appEvent.isNil:
          window.sendEvent(appEvent)
      ,
    )

    window.windowNativeWindow().firstStep()
    window.windowNativeWindow().refreshUiScale(window.windowAutoScale())
    window.windowNativeReady true
  except Exception as exc:
    cleanupFailedWindowInit(window)
    raise newException(CatchableError, "window backend init failed: " & exc.msg)
