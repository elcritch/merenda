from figdraw/figbasics import ZLevel
from figdraw/fignodes import FigIdx
import std/options

import ../accessibility/accessibilityprotocols
import ./controls
import ../drawing
import ../containers/listbasics
import ../foundation/selectors
import ../themes
import ../foundation/events
import ../foundation/types

type
  PopupListCountProc* = proc(): int {.closure.}
  PopupListMetricProc* = proc(): float32 {.closure.}
  PopupListBoolProc* = proc(): bool {.closure.}
  PopupListStringProc* = proc(): string {.closure.}
  PopupListClassesProc* = proc(): seq[string] {.closure.}
  PopupListItemTextProc* = proc(index: int): string {.closure.}
  PopupListItemBoolProc* = proc(index: int): bool {.closure.}
  PopupListItemStateProc* = proc(index: int): ButtonState {.closure.}
  PopupListItemProc* = proc(index: int) {.closure.}
  PopupListScrollProc* = proc(delta: int) {.closure.}
  PopupListKeyProc* = proc(event: KeyEvent) {.closure.}
  PopupListActionProc* = proc() {.closure.}

  PopupListData* = object
    itemCount*: PopupListCountProc
    visibleCount*: PopupListCountProc
    firstIndex*: PopupListCountProc
    selectedIndex*: PopupListCountProc
    highlightedIndex*: PopupListCountProc
    rowHeight*: PopupListMetricProc
    itemText*: PopupListItemTextProc
    itemKeyEquivalentText*: PopupListItemTextProc
    itemIsSeparator*: PopupListItemBoolProc
    itemHasSubmenu*: PopupListItemBoolProc
    itemIsEnabled*: PopupListItemBoolProc
    itemState*: PopupListItemStateProc
    enabled*: PopupListBoolProc
    focused*: PopupListBoolProc
    opened*: PopupListBoolProc
    styleId*: PopupListStringProc
    styleClasses*: PopupListClassesProc

  PopupListActions* = object
    highlight*: PopupListItemProc
    activate*: PopupListItemProc
    close*: PopupListActionProc
    scroll*: PopupListScrollProc
    keyDown*: PopupListKeyProc

  PopupListView* = ref object of View
    xData: PopupListData
    xActions: PopupListActions
    xTrackingItem: bool
    xPopupRole: StyleRole
    xItemRole: StyleRole

proc itemCount*(popupList: PopupListView): int
proc visibleItemCount*(popupList: PopupListView): int
proc firstIndex*(popupList: PopupListView): int
proc selectedIndex*(popupList: PopupListView): int
proc highlightedIndex*(popupList: PopupListView): int
proc rowHeight*(popupList: PopupListView): float32
proc itemText*(popupList: PopupListView, index: int): string
proc itemKeyEquivalentText*(popupList: PopupListView, index: int): string
proc itemIsSeparator*(popupList: PopupListView, index: int): bool
proc itemHasSubmenu*(popupList: PopupListView, index: int): bool
proc itemIsEnabled*(popupList: PopupListView, index: int): bool
proc itemState*(popupList: PopupListView, index: int): ButtonState
proc isEnabled*(popupList: PopupListView): bool
proc isFocused*(popupList: PopupListView): bool
proc isOpened*(popupList: PopupListView): bool
proc canScrollRows*(popupList: PopupListView, delta: int): bool
proc popupListScrollRows*(event: ScrollEvent): int
proc popupListItemRect*(
  popupList: PopupListView, popupBounds: Rect, itemIndex: int
): Rect

proc popupListItemIndexAtPoint*(
  popupList: PopupListView, popupBounds: Rect, point: Point
): int

proc popupListScrollerKnobRect*(popupList: PopupListView, popupBounds: Rect): Rect
proc drawPopupList*(
  popupList: PopupListView,
  context: DrawContext,
  popupBounds: Rect,
  layer: ZLevel = DefaultDrawLevel,
  parent: FigIdx = (-1).FigIdx,
)

proc beginPopupListTracking*(popupList: PopupListView, popupBounds: Rect, point: Point)
proc trackPopupListPoint*(popupList: PopupListView, popupBounds: Rect, point: Point)
proc finishPopupListTracking*(
  popupList: PopupListView, popupBounds: Rect, point: Point, closeWhenDone = true
)

proc resetPopupListTracking*(popupList: PopupListView)
proc highlightItemAtPoint(popupList: PopupListView, popupBounds: Rect, point: Point)
proc activateItem(popupList: PopupListView, index: int)
proc close(popupList: PopupListView)
proc scrollBy(popupList: PopupListView, delta: int)
proc dispatchKeyDown(popupList: PopupListView, event: KeyEvent)

protocol DefaultPopupListDrawing of ViewDrawingProtocol:
  method drawLevel(popupList: PopupListView): ZLevel =
    PopupDrawLevel

  method draw(popupList: PopupListView, context: DrawContext) =
    if popupList.isOpened():
      popupList.drawPopupList(context, popupList.bounds, popupList.drawLevel())

protocol DefaultPopupListEvents of ResponderEventProtocol:
  method mouseDown(popupList: PopupListView, event: MouseEvent): bool =
    if not popupList.isEnabled() or event.button != mbPrimary:
      return false
    popupList.beginPopupListTracking(popupList.bounds, event.location)
    true

  method mouseDragged(popupList: PopupListView, event: MouseEvent): bool =
    if popupList.isOpened():
      popupList.trackPopupListPoint(popupList.bounds, event.location)
      return true
    false

  method mouseMoved(popupList: PopupListView, event: MouseEvent): bool =
    if popupList.isOpened():
      popupList.trackPopupListPoint(popupList.bounds, event.location)
      return true
    false

  method mouseUp(popupList: PopupListView, event: MouseEvent): bool =
    if not popupList.isEnabled() or event.button != mbPrimary:
      return false
    popupList.finishPopupListTracking(popupList.bounds, event.location)
    true

  method wantsForwardedScrollEvents(
      popupList: PopupListView, event: ScrollEvent
  ): bool =
    not popupList.isOpened() or not popupList.canScrollRows(popupListScrollRows(event))

  method scrollWheel(popupList: PopupListView, event: ScrollEvent): bool =
    let delta = popupListScrollRows(event)
    if popupList.isOpened() and popupList.canScrollRows(delta):
      popupList.scrollBy(delta)
      return true

  method keyDown(popupList: PopupListView, event: KeyEvent): bool =
    popupList.dispatchKeyDown(event)
    result = true

protocol DefaultPopupListAccessibility of AccessibilityProtocol:
  method accessibilityRole(popupList: PopupListView): AccessibilityRole =
    arList

  method accessibilityValue(popupList: PopupListView): string =
    $popupList.itemCount()

  method accessibilityTraits(popupList: PopupListView): AccessibilityTraits =
    result = popupList.xAccessibilityTraits + {atSelectable}
    if not popupList.isEnabled():
      result.incl atDisabled
    if popupList.isFocused():
      result.incl atFocused

  method isAccessibilityElement(popupList: PopupListView): bool =
    true

proc data(popupList: PopupListView): PopupListData =
  if popupList.isNil:
    PopupListData()
  else:
    popupList.xData

proc actions(popupList: PopupListView): PopupListActions =
  if popupList.isNil:
    PopupListActions()
  else:
    popupList.xActions

template valueOr(callback, fallback: untyped): untyped =
  if callback.isNil:
    fallback
  else:
    callback()

template valueAtOr(callback, index, fallback: untyped): untyped =
  if callback.isNil:
    fallback
  else:
    callback(index)

proc itemCount*(popupList: PopupListView): int =
  max(popupList.data().itemCount.valueOr(0), 0)

proc visibleItemCount*(popupList: PopupListView): int =
  max(popupList.data().visibleCount.valueOr(popupList.itemCount()), 0)

proc firstIndex*(popupList: PopupListView): int =
  popupList.data().firstIndex.valueOr(0).clampFirstIndex(
    popupList.itemCount(), popupList.visibleItemCount()
  )

proc selectedIndex*(popupList: PopupListView): int =
  popupList.data().selectedIndex.valueOr(-1)

proc highlightedIndex*(popupList: PopupListView): int =
  popupList.data().highlightedIndex.valueOr(-1)

proc rowHeight*(popupList: PopupListView): float32 =
  popupList.data().rowHeight.valueOr(18.0'f32).normalizedRowHeight()

proc itemText*(popupList: PopupListView, index: int): string =
  popupList.data().itemText.valueAtOr(index, "")

proc itemKeyEquivalentText*(popupList: PopupListView, index: int): string =
  popupList.data().itemKeyEquivalentText.valueAtOr(index, "")

proc itemIsSeparator*(popupList: PopupListView, index: int): bool =
  popupList.data().itemIsSeparator.valueAtOr(index, false)

proc itemHasSubmenu*(popupList: PopupListView, index: int): bool =
  popupList.data().itemHasSubmenu.valueAtOr(index, false)

proc itemIsEnabled*(popupList: PopupListView, index: int): bool =
  popupList.data().itemIsEnabled.valueAtOr(index, true)

proc itemState*(popupList: PopupListView, index: int): ButtonState =
  popupList.data().itemState.valueAtOr(index, bsOff)

proc isEnabled*(popupList: PopupListView): bool =
  popupList.data().enabled.valueOr(true)

proc isFocused*(popupList: PopupListView): bool =
  popupList.data().focused.valueOr(false)

proc isOpened*(popupList: PopupListView): bool =
  popupList.data().opened.valueOr(true)

proc styleId(popupList: PopupListView): string =
  popupList.data().styleId.valueOr("")

proc styleClasses(popupList: PopupListView): seq[string] =
  popupList.data().styleClasses.valueOr(@[])

proc popupListScrollRows*(event: ScrollEvent): int =
  rowScrollRows(event)

proc popupListItemRect*(
    popupList: PopupListView, popupBounds: Rect, itemIndex: int
): Rect =
  rowItemRect(
    popupBounds,
    popupList.firstIndex(),
    popupList.visibleItemCount(),
    itemIndex,
    popupList.rowHeight(),
  )

proc popupListItemIndexAtPoint*(
    popupList: PopupListView, popupBounds: Rect, point: Point
): int =
  rowItemIndexAtPoint(
    popupBounds,
    point,
    popupList.firstIndex(),
    popupList.visibleItemCount(),
    popupList.itemCount(),
    popupList.rowHeight(),
  )

proc popupListScrollerKnobRect*(popupList: PopupListView, popupBounds: Rect): Rect =
  rowScrollerKnobRect(
    popupBounds,
    popupList.firstIndex(),
    popupList.visibleItemCount(),
    popupList.itemCount(),
  )

proc drawPopupList*(
    popupList: PopupListView,
    context: DrawContext,
    popupBounds: Rect,
    layer: ZLevel = DefaultDrawLevel,
    parent: FigIdx = (-1).FigIdx,
) =
  if popupList.isNil or popupBounds.isEmpty:
    return
  var states: set[WidgetState] = {}
  if not popupList.isEnabled():
    states.incl ssDisabled
  if popupList.isFocused():
    states.incl ssFocused
  if popupList.isOpened():
    states.incl ssOpen
  let
    classes = popupList.styleClasses()
    appearance = context.appearance()
    popupStyle = appearance.resolveComboBoxStyle(
      controlStyle(
        popupList.xPopupRole, states, id = popupList.styleId(), classes = classes
      )
    )
    popupFrame = context.renderRectFor(popupBounds)
    popupChrome =
      chromeContext(popupStyle.chrome, crPopupList, cpFace, popupStyle.box.fill, states)
    popupRoot = context.addRenderRectangle(
      layer,
      parent,
      popupFrame,
      appearance.chromeFill(popupChrome),
      popupStyle.box.borderColor,
      max(popupStyle.box.borderWidth, 1.0'f32),
      popupStyle.box.cornerRadius,
      popupStyle.box.shadows,
      maskContent = true,
    )
    first = popupList.firstIndex()
    visible = popupList.visibleItemCount()
    total = popupList.itemCount()

  context.drawChromeExtras(
    popupChrome,
    initChromeExtras(
      popupRoot, popupFrame, layer = layer, cornerRadius = popupStyle.box.cornerRadius
    ),
  )

  for visibleIndex in 0 ..< visible:
    let itemIndex = first + visibleIndex
    if itemIndex < 0 or itemIndex >= total:
      discard
    else:
      let itemRect = popupList.popupListItemRect(popupBounds, itemIndex)
      if popupList.itemIsSeparator(itemIndex):
        let line = initRect(
          itemRect.origin.x + 8.0'f32,
          itemRect.origin.y + itemRect.size.height / 2.0'f32,
          max(itemRect.size.width - 16.0'f32, 0.0'f32),
          1.0'f32,
        )
        discard context.addRenderRectangle(
          layer,
          popupRoot,
          context.renderRectFor(line),
          fill(initColor(0.68, 0.69, 0.71)),
        )
      else:
        let itemEnabled = popupList.isEnabled() and popupList.itemIsEnabled(itemIndex)
        let
          states = block:
            var rowStates: set[WidgetState] = {}
            if not itemEnabled:
              rowStates.incl(ssDisabled)
            if itemIndex == popupList.selectedIndex():
              rowStates.incl(ssSelected)
            if itemEnabled and itemIndex == popupList.highlightedIndex():
              rowStates.incl(ssHovered)
            if popupList.isFocused():
              rowStates.incl(ssFocused)
            rowStates
          row = initRowState(itemIndex, popupList.itemText(itemIndex), states = states)
          rowStyle =
            if ssDisabled in states:
              initRowStyle(textColor = some(initColor(0.48, 0.49, 0.52)))
            else:
              initRowStyle()
          keyEquivalentText = popupList.itemKeyEquivalentText(itemIndex)
          accessoryColor =
            if ssDisabled in states:
              initColor(0.52, 0.53, 0.56)
            elif ssHovered in states:
              initColor(1.0, 1.0, 1.0)
            else:
              initColor(0.27, 0.29, 0.33)
          accessoryStyle = context.appearance.resolveTextStyle(
            controlStyle(
              popupList.xItemRole, states, id = popupList.styleId(), classes = classes
            ),
            accessoryColor,
            insets(0.0),
          )
        context.drawRowItem(
          itemRect,
          row,
          rowStyle,
          popupList.xItemRole,
          popupList.styleId(),
          classes,
          layer = layer,
          parent = popupRoot,
        )
        case popupList.itemState(itemIndex)
        of bsOff:
          discard
        of bsOn, bsMixed:
          context.addText(
            layer,
            popupRoot,
            initRect(
              itemRect.origin.x + 7.0'f32,
              itemRect.origin.y + 3.0'f32,
              12.0'f32,
              max(itemRect.size.height - 5.0'f32, 0.0'f32),
            ),
            if popupList.itemState(itemIndex) == bsOn: "✓" else: "-",
            accessoryStyle,
            taCenter,
          )
        if keyEquivalentText.len > 0:
          context.addText(
            layer,
            popupRoot,
            initRect(
              itemRect.maxX - 86.0'f32,
              itemRect.origin.y + 3.0'f32,
              74.0'f32,
              max(itemRect.size.height - 5.0'f32, 0.0'f32),
            ),
            keyEquivalentText,
            accessoryStyle,
            taRight,
          )
        if popupList.itemHasSubmenu(itemIndex):
          context.addText(
            layer,
            popupRoot,
            initRect(
              itemRect.maxX - 18.0'f32,
              itemRect.origin.y + 3.0'f32,
              10.0'f32,
              max(itemRect.size.height - 5.0'f32, 0.0'f32),
            ),
            ">",
            accessoryStyle,
            taRight,
          )

  let knobRect = popupList.popupListScrollerKnobRect(popupBounds)
  if not knobRect.isEmpty:
    discard context.addRenderRectangle(
      layer,
      popupRoot,
      context.renderRectFor(knobRect),
      fill(initColor(0.10, 0.18, 0.30, 0.34)),
      initColor(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      2.0'f32,
    )

proc highlightItemAtPoint(popupList: PopupListView, popupBounds: Rect, point: Point) =
  let itemIndex = popupList.popupListItemIndexAtPoint(popupBounds, point)
  let highlight = popupList.actions().highlight
  if itemIndex >= 0 and not highlight.isNil:
    highlight(itemIndex)

proc beginPopupListTracking*(
    popupList: PopupListView, popupBounds: Rect, point: Point
) =
  popupList.xTrackingItem = true
  popupList.highlightItemAtPoint(popupBounds, point)

proc trackPopupListPoint*(popupList: PopupListView, popupBounds: Rect, point: Point) =
  popupList.highlightItemAtPoint(popupBounds, point)

proc finishPopupListTracking*(
    popupList: PopupListView, popupBounds: Rect, point: Point, closeWhenDone = true
) =
  let itemIndex =
    if popupList.isOpened() and popupList.xTrackingItem:
      popupList.popupListItemIndexAtPoint(popupBounds, point)
    else:
      -1
  popupList.xTrackingItem = false
  let itemCanActivate =
    itemIndex >= 0 and not popupList.itemIsSeparator(itemIndex) and
    popupList.itemIsEnabled(itemIndex)
  if itemCanActivate:
    popupList.activateItem(itemIndex)
  if closeWhenDone and (itemIndex < 0 or itemCanActivate):
    popupList.close()

proc resetPopupListTracking*(popupList: PopupListView) =
  if not popupList.isNil:
    popupList.xTrackingItem = false

proc activateItem(popupList: PopupListView, index: int) =
  let activate = popupList.actions().activate
  if not activate.isNil:
    activate(index)

proc close(popupList: PopupListView) =
  let closeAction = popupList.actions().close
  if not closeAction.isNil:
    closeAction()

proc scrollBy(popupList: PopupListView, delta: int) =
  let scroll = popupList.actions().scroll
  if delta != 0 and not scroll.isNil:
    scroll(delta)

proc canScrollRows*(popupList: PopupListView, delta: int): bool =
  initRowViewport(popupList.firstIndex()).canScrollBy(
    delta, popupList.itemCount(), popupList.visibleItemCount()
  )

proc dispatchKeyDown(popupList: PopupListView, event: KeyEvent) =
  let keyDown = popupList.actions().keyDown
  if not keyDown.isNil:
    keyDown(event)

proc configure*(
    popupList: PopupListView, data: PopupListData, actions: PopupListActions
) =
  popupList.xData = data
  popupList.xActions = actions

proc setPopupListRoles*(
    popupList: PopupListView,
    popupRole: StyleRole = srComboBox,
    itemRole: StyleRole = srComboBoxItem,
) =
  popupList.xPopupRole = popupRole
  popupList.xItemRole = itemRole
  popupList.setNeedsDisplay(true)

proc initPopupListViewFields*(
    popupList: PopupListView,
    data = PopupListData(),
    actions = PopupListActions(),
    frame: Rect = AutoRect,
) =
  initViewFields(popupList, frame)
  popupList.xPopupRole = srComboBox
  popupList.xItemRole = srComboBoxItem
  popupList.configure(data, actions)
  popupList.setAcceptsFirstResponder(true)
  discard popupList.withProtocol(DefaultPopupListDrawing)
  discard popupList.withProtocol(DefaultPopupListEvents)
  discard popupList.withProtocol(DefaultPopupListAccessibility)

proc newPopupListView*(
    data = PopupListData(), actions = PopupListActions(), frame: Rect = AutoRect
): PopupListView =
  result = PopupListView()
  initPopupListViewFields(result, data, actions, frame)
