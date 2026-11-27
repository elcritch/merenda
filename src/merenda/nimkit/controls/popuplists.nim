from figdraw import ZLevel, FigIdx
import std/options

import ../../foundation/backrefs
import ../accessibility/accessibilityprotocols
import ./controls
import ../drawing
import ../containers/listbasics
import ../foundation/selectors
import ../themes
import ../foundation/events
import ../foundation/types

type
  PopupListItem* = object
    ## Presentation of one popup row. An ordinary row is enabled by default.
    text*: string
    keyEquivalentText*: string
    separator*: bool
    hasSubmenu*: bool
    reservesSubmenuSpace*: bool
    disabled*: bool

  PopupListView* = ref object of View
    xDataSource: BackRef[Responder]
    xDelegate: BackRef[Responder]
    xTrackingItem: bool
    xPopupRole: StyleRole
    xItemRole: StyleRole
    xControlScrollRows: int

  PopupListItemMetrics = object
    textStyle: TextStyle
    baseInsets: EdgeInsets
    textInsets: EdgeInsets
    stateWidth: float32
    shortcutWidth: float32
    submenuWidth: float32

protocol PopupListDataSource {.selectorScope: protocol.}:
  ## Supplies live content, viewport metrics, and presentation state.
  method totalCount*(popupList: PopupListView): int {.optional.}
  method visibleCount*(popupList: PopupListView): int {.optional.}
  method topIndex*(popupList: PopupListView): int {.optional.}
  method selectionIndex*(popupList: PopupListView): int {.optional.}
  method highlightIndex*(popupList: PopupListView): int {.optional.}
  method heightOfRow*(popupList: PopupListView): float32 {.optional.}
  method rowAtIndex*(popupList: PopupListView, index: int): PopupListItem {.optional.}

  method stateForItem*(popupList: PopupListView, index: int): ButtonState {.optional.}

    ## Kept separate so checking for a state column can skip row text and shortcuts.

  method isInteractive*(popupList: PopupListView): bool {.optional.}
  method hasFocus*(popupList: PopupListView): bool {.optional.}
  method isShowing*(popupList: PopupListView): bool {.optional.}
  method contentStyleId*(popupList: PopupListView): string {.optional.}
  method contentStyleClasses*(popupList: PopupListView): seq[string] {.optional.}

protocol PopupListDelegate {.selectorScope: protocol.}:
  ## Handles interactions with popup content.
  method highlightRow*(popupList: PopupListView, index: int) {.optional.}
  method activateRow*(popupList: PopupListView, index: int) {.optional.}
  method dismissAfterActivation*(popupList: PopupListView): bool {.optional.}
    ## Defaults to true. Return false when the delegate manages dismissal.

  method dismissList*(popupList: PopupListView) {.optional.}
  method scrollByRows*(popupList: PopupListView, delta: int) {.optional.}
  method handleKeyDown*(popupList: PopupListView, event: KeyEvent) {.optional.}
  method handleFlagsChanged*(popupList: PopupListView, event: KeyEvent) {.optional.}
  method moveFocus*(popupList: PopupListView, delta: int) {.optional.}
    ## Handles Tab (1) or Backtab (-1). Without this method, the command
    ## continues along the popup's responder chain.

proc dataSource*(popupList: PopupListView): Responder =
  ## Returns the current data source, cleared when it is destroyed.
  popupList.xDataSource.target

proc delegate*(popupList: PopupListView): Responder =
  ## Returns the current delegate, cleared when it is destroyed.
  popupList.xDelegate.target

proc `dataSource=`*(popupList: PopupListView, source: Responder) =
  ## Assigns a data source. Its owner must keep it alive while the popup uses it.
  if popupList.dataSource() == source:
    return
  if not source.isNil:
    discard source.adopt(PopupListDataSource)
  popupList.xDataSource.target = source
  popupList.needsDisplay = true

proc `delegate=`*(popupList: PopupListView, delegate: Responder) =
  ## Assigns a delegate. Its owner must keep it alive while the popup uses it.
  if popupList.delegate() == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(PopupListDelegate)
  popupList.xDelegate.target = delegate

proc sendToDelegate[A](
    popupList: PopupListView, message: Selector[A, EmptyArgs], args: sink A
): bool {.inline, discardable.} =
  popupList.delegate().asDynamicAgent().sendLocalIfHandled(message, ensureMove args)

const
  PopupStateGap = 6.0'f32
  PopupShortcutGap = 12.0'f32
  PopupSubmenuGap = 8.0'f32

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
proc scrollBy(popupList: PopupListView, delta: int)

func controlScrollRows*(popupList: PopupListView): Positive =
  ## The number of rows moved by a wheel event while Control is held.
  max(1, popupList.xControlScrollRows)

proc `controlScrollRows=`*(popupList: PopupListView, rows: Positive) =
  popupList.xControlScrollRows = rows

proc popupListScrollRows(popupList: PopupListView, event: ScrollEvent): int =
  let rows = popupListScrollRows(event)
  if kmControl in event.modifiers:
    return rows * popupList.controlScrollRows()
  rows

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
    not popupList.isOpened() or
      not popupList.canScrollRows(popupList.popupListScrollRows(event))

  method scrollWheel(popupList: PopupListView, event: ScrollEvent): bool =
    let delta = popupList.popupListScrollRows(event)
    if popupList.isOpened() and popupList.canScrollRows(delta):
      popupList.scrollBy(delta)
      return true

  method keyDown(popupList: PopupListView, event: KeyEvent): bool =
    popupList.sendToDelegate(handleKeyDown(), (popupList: popupList, event: event))
    true

  method flagsChanged(popupList: PopupListView, event: KeyEvent): bool =
    popupList.sendToDelegate(handleFlagsChanged(), (popupList: popupList, event: event))

protocol DefaultPopupListKeyCommands of KeyViewCommandProtocol:
  method insertTab(popupList: PopupListView, args: ActionArgs) =
    if not popupList.sendToDelegate(moveFocus(), (popupList: popupList, delta: 1)):
      popupList.nextResponder().performCommandInChain(
        TryToPerformArgs(selector: insertTab(), sender: args.sender)
      )

  method insertBacktab(popupList: PopupListView, args: ActionArgs) =
    if not popupList.sendToDelegate(moveFocus(), (popupList: popupList, delta: -1)):
      popupList.nextResponder().performCommandInChain(
        TryToPerformArgs(selector: insertBacktab(), sender: args.sender)
      )

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

template queryPopupData(popupList: PopupListView, message, args: untyped): untyped =
  popupList.dataSource().asDynamicAgent().trySendLocal(message, args)

proc itemCount*(popupList: PopupListView): int =
  max(popupList.queryPopupData(totalCount(), popupList).get(0), 0)

proc visibleItemCount*(popupList: PopupListView): int =
  let reply = popupList.queryPopupData(visibleCount(), popupList)
  if reply.isSome:
    return max(reply.get(), 0)
  popupList.itemCount()

proc firstIndex*(popupList: PopupListView): int =
  let first = popupList.queryPopupData(topIndex(), popupList).get(0)
  first.clampFirstIndex(popupList.itemCount(), popupList.visibleItemCount())

proc selectedIndex*(popupList: PopupListView): int =
  popupList.queryPopupData(selectionIndex(), popupList).get(-1)

proc highlightedIndex*(popupList: PopupListView): int =
  popupList.queryPopupData(highlightIndex(), popupList).get(-1)

proc rowHeight*(popupList: PopupListView): float32 =
  let height = popupList.queryPopupData(heightOfRow(), popupList).get(18.0'f32)
  height.normalizedRowHeight()

proc itemAtIndex*(popupList: PopupListView, index: int): PopupListItem =
  popupList.queryPopupData(rowAtIndex(), (popupList: popupList, index: index)).get(
    PopupListItem()
  )

proc itemText*(popupList: PopupListView, index: int): string =
  popupList.itemAtIndex(index).text

proc itemKeyEquivalentText*(popupList: PopupListView, index: int): string =
  popupList.itemAtIndex(index).keyEquivalentText

proc itemIsSeparator*(popupList: PopupListView, index: int): bool =
  popupList.itemAtIndex(index).separator

proc itemHasSubmenu*(popupList: PopupListView, index: int): bool =
  popupList.itemAtIndex(index).hasSubmenu

proc itemIsEnabled*(popupList: PopupListView, index: int): bool =
  not popupList.itemAtIndex(index).disabled

proc itemState*(popupList: PopupListView, index: int): ButtonState =
  popupList.queryPopupData(stateForItem(), (popupList: popupList, index: index)).get(
    bsOff
  )

proc isEnabled*(popupList: PopupListView): bool =
  popupList.queryPopupData(isInteractive(), popupList).get(true)

proc isFocused*(popupList: PopupListView): bool =
  popupList.queryPopupData(hasFocus(), popupList).get(false)

proc isOpened*(popupList: PopupListView): bool =
  popupList.queryPopupData(isShowing(), popupList).get(true)

proc styleId(popupList: PopupListView): string =
  popupList.queryPopupData(contentStyleId(), popupList).get("")

proc styleClasses(popupList: PopupListView): seq[string] =
  popupList.queryPopupData(contentStyleClasses(), popupList).get(@[])

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

proc hasStateColumn(popupList: PopupListView): bool =
  for index in 0 ..< popupList.itemCount():
    if popupList.itemState(index) != bsOff and not popupList.itemAtIndex(index).separator:
      return true

proc itemMetrics(
    popupList: PopupListView,
    item: PopupListItem,
    appearance: Appearance,
    states: set[WidgetState],
    stateColumn: bool,
): PopupListItemMetrics =
  let style = appearance.resolveRowItemStyle(
    controlStyle(
      popupList.xItemRole,
      states,
      id = popupList.styleId(),
      classes = popupList.styleClasses(),
    )
  )
  result.textStyle = style.text
  result.baseInsets = style.text.insets
  result.textInsets = style.text.insets
  if stateColumn:
    result.stateWidth = max(textNaturalSize("✓", style.text).width, 12.0'f32)
    result.textInsets.left += result.stateWidth + PopupStateGap
  let shortcut = item.keyEquivalentText
  if shortcut.len > 0:
    result.shortcutWidth = textNaturalSize(shortcut, style.text).width
    result.textInsets.right += result.shortcutWidth + PopupShortcutGap
  if item.hasSubmenu or item.reservesSubmenuSpace:
    result.submenuWidth = max(textNaturalSize(">", style.text).width, 10.0'f32)
    result.textInsets.right += result.submenuWidth + PopupSubmenuGap

proc popupListContentSize*(popupList: PopupListView, appearance: Appearance): Size =
  ## Measure popup contents with the appearance used by their presentation host.
  ## Include columns for checked states, shortcuts, and submenu indicators.
  let stateColumn = popupList.hasStateColumn()
  for index in 0 ..< popupList.itemCount():
    let item = popupList.itemAtIndex(index)
    if not item.separator:
      let metrics = popupList.itemMetrics(item, appearance, {}, stateColumn)
      result.width = max(
        result.width,
        textNaturalSize(item.text, metrics.textStyle).width + metrics.textInsets.left +
          metrics.textInsets.right + 2.0'f32,
      )
  result.height =
    max(popupList.rowHeight() * popupList.visibleItemCount().float32 + 2.0'f32, 1.0'f32)

proc drawPopupList*(
    popupList: PopupListView,
    context: DrawContext,
    popupBounds: Rect,
    layer: ZLevel = DefaultDrawLevel,
    parent: FigIdx = (-1).FigIdx,
) =
  if popupBounds.isEmpty:
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
      cornerRadii = popupStyle.box.cornerRadii,
    )
    first = popupList.firstIndex()
    visible = popupList.visibleItemCount()
    total = popupList.itemCount()
    rowHeight = popupList.rowHeight()
    last = min(first + visible, total) - 1
    borderWidth = max(popupStyle.box.borderWidth, 1.0'f32)
    contentBounds = popupBounds.inset(insets(borderWidth))
    itemRadius = max(popupStyle.box.cornerRadius - borderWidth, 0.0'f32)
    stateColumn = popupList.hasStateColumn()

  context.drawChromeExtras(
    popupChrome,
    initChromeExtras(
      popupRoot,
      popupFrame,
      layer = layer,
      cornerRadius = popupStyle.box.cornerRadius,
      cornerRadii = popupStyle.box.cornerRadii,
    ),
  )

  for visibleIndex in 0 ..< visible:
    let itemIndex = first + visibleIndex
    if itemIndex < 0 or itemIndex >= total:
      discard
    else:
      let
        item = popupList.itemAtIndex(itemIndex)
        itemRect = rowItemRect(popupBounds, first, visible, itemIndex, rowHeight)
          .intersection(contentBounds)
      if item.separator:
        let line = rect(
          itemRect.origin.x + 8.0'f32,
          itemRect.origin.y + itemRect.size.height / 2.0'f32,
          max(itemRect.size.width - 16.0'f32, 0.0'f32),
          1.0'f32,
        )
        discard context.addRenderRectangle(
          layer, popupRoot, context.renderRectFor(line), fill(color(0.68, 0.69, 0.71))
        )
      else:
        let itemEnabled = popupList.isEnabled() and not item.disabled
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
          row = initRowState(itemIndex, item.text, states = states)
          metrics = popupList.itemMetrics(item, appearance, states, stateColumn)
          itemCornerRadii = initCornerRadii(
            if itemIndex == first: itemRadius else: 0.0'f32,
            if itemIndex == first: itemRadius else: 0.0'f32,
            if itemIndex == last: itemRadius else: 0.0'f32,
            if itemIndex == last: itemRadius else: 0.0'f32,
          )
          rowStyle = initRowStyle(
            textColor =
              if ssDisabled in states:
                some(color(0.48, 0.49, 0.52))
              else:
                none(Color),
            cornerRadii = some(itemCornerRadii),
            textInsets = some(metrics.textInsets),
          )
          keyEquivalentText = item.keyEquivalentText
          accessoryStyle = metrics.textStyle
          accessoryY = itemRect.minY + metrics.baseInsets.top
          accessoryHeight = max(
            itemRect.size.height - metrics.baseInsets.top - metrics.baseInsets.bottom, 0
          )
          submenuX = itemRect.maxX - metrics.baseInsets.right - metrics.submenuWidth
          shortcutX =
            submenuX - (if metrics.submenuWidth > 0: PopupSubmenuGap else: 0.0'f32) -
            metrics.shortcutWidth
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
        let state = popupList.itemState(itemIndex)
        case state
        of bsOff:
          discard
        of bsOn, bsMixed:
          context.addText(
            layer,
            popupRoot,
            rect(
              itemRect.minX + metrics.baseInsets.left,
              accessoryY,
              metrics.stateWidth,
              accessoryHeight,
            ),
            if state == bsOn: "✓" else: "-",
            accessoryStyle,
            taCenter,
          )
        if keyEquivalentText.len > 0:
          context.addText(
            layer,
            popupRoot,
            rect(shortcutX, accessoryY, metrics.shortcutWidth, accessoryHeight),
            keyEquivalentText,
            accessoryStyle,
            taRight,
          )
        if item.hasSubmenu:
          context.addText(
            layer,
            popupRoot,
            rect(submenuX, accessoryY, metrics.submenuWidth, accessoryHeight),
            ">",
            accessoryStyle,
            taRight,
          )

  let knobRect = rowScrollerKnobRect(popupBounds, first, visible, total)
  if not knobRect.isEmpty:
    discard context.addRenderRectangle(
      layer,
      popupRoot,
      context.renderRectFor(knobRect),
      fill(color(0.10, 0.18, 0.30, 0.34)),
      color(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      2.0'f32,
    )

proc highlightItemAtPoint(popupList: PopupListView, popupBounds: Rect, point: Point) =
  let itemIndex = popupList.popupListItemIndexAtPoint(popupBounds, point)
  if itemIndex >= 0:
    popupList.sendToDelegate(highlightRow(), (popupList: popupList, index: itemIndex))

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
    if itemIndex < 0:
      false
    else:
      let item = popupList.itemAtIndex(itemIndex)
      not item.separator and not item.disabled
  if itemCanActivate:
    popupList.sendToDelegate(activateRow(), (popupList: popupList, index: itemIndex))
  if closeWhenDone and (
    itemIndex < 0 or (
      itemCanActivate and
      popupList
      .delegate()
      .asDynamicAgent()
      .trySendLocal(dismissAfterActivation(), popupList)
      .get(true)
    )
  ):
    popupList.sendToDelegate(dismissList(), popupList)

proc resetPopupListTracking*(popupList: PopupListView) =
  popupList.xTrackingItem = false

proc scrollBy(popupList: PopupListView, delta: int) =
  if delta != 0:
    popupList.sendToDelegate(scrollByRows(), (popupList: popupList, delta: delta))

proc canScrollRows*(popupList: PopupListView, delta: int): bool =
  initRowViewport(popupList.firstIndex()).canScrollBy(
    delta, popupList.itemCount(), popupList.visibleItemCount()
  )

proc setPopupListRoles*(
    popupList: PopupListView,
    popupRole: StyleRole = srComboBox,
    itemRole: StyleRole = srComboBoxItem,
) =
  popupList.xPopupRole = popupRole
  popupList.xItemRole = itemRole
  popupList.needsDisplay = true

proc initPopupListViewFields*(
    popupList: PopupListView,
    dataSource: Responder = nil,
    delegate: Responder = nil,
    frame: Rect = AutoRect,
) =
  initViewFields(popupList, frame)
  popupList.xPopupRole = srComboBox
  popupList.xItemRole = srComboBoxItem
  popupList.usesThemedRootBackground = false
  popupList.dataSource = dataSource
  popupList.delegate = delegate
  popupList.focusable = true
  discard popupList.withProtocol(DefaultPopupListDrawing)
  discard popupList.withProtocol(DefaultPopupListEvents)
  discard popupList.withProtocol(DefaultPopupListKeyCommands)
  discard popupList.withProtocol(DefaultPopupListAccessibility)

proc newPopupListView*(
    dataSource: Responder = nil, delegate: Responder = nil, frame: Rect = AutoRect
): PopupListView =
  ## Creates a popup that refers to its data source and delegate without owning them.
  result = PopupListView()
  initPopupListViewFields(result, dataSource, delegate, frame)
