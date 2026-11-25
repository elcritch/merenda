## Tag selection built from an MVC controller and views that bind to it.
##
## `TagController` is the model. Its `available` ArrayController holds candidate
## tags, such as the results of a search, and its `selected` ArrayController holds
## the chosen tags in order. Views observe the controllers' change signals and
## send edits back through `TagController` commands, so several views can share
## one controller:
##
## - `TagInput` is a text field with a dropdown of matching tags. It follows the
##   ARIA combobox pattern and the NSTokenField and QCompleter conventions.
##   Clicking the field or pressing Down lists every match, typing filters the
##   list, Up and Down move the highlight, Return adds the highlighted tag,
##   Escape closes the list, and Delete in an empty field removes the last tag
##   when the tags are inline.
## - `TagList` shows the selected tags as removable chips that wrap onto lines.
## - `TagPicker` arranges a `TagInput` and a `TagList` by `TagListPlacement`.
##   Create the two views directly to show the list somewhere else.
##
## For a server-side search, observe `tagQueryDidChange`, run the search and
## pass its results to `setAvailableTags`. The list keeps filtering the current
## options locally while the search runs.
import std/[strutils, unicode]

import sigils/core
import sigils/selectors as dynamicSelectors

import ../accessibility/accessibility
import ../app/modelcontrollers
import ../app/windows
import ../containers/listbasics
import ../containers/stackviews
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../text/fieldeditors
import ../text/textfields
import ../themes
import ./chips
import ./popuplists

type
  TagMatchMode* = enum
    tmmPrefix ## Titles that start with the query, like QCompleter's default.
    tmmContains ## Titles that contain the query anywhere.

  TagListPlacement* = enum
    tlpInline ## Chips sit inside the field before the text, like NSTokenField.
    tlpAbove ## Chips form a list above the field.
    tlpBelow ## Chips form a list below the field, common in web forms.

  TagController* = ref object of Responder
    ## The tag model. Edit `available` and `selected` through the commands below
    ## so views and observers are notified consistently.
    available*: ArrayController
    selected*: ArrayController
    matchMode*: TagMatchMode
    allowsNewTags*: bool ## Return or a separator turns unmatched text into a tag.
    separators*: set[char] ## Characters that commit typed text as tags.
    xQuery: string
    xDelegate: BackRef[Responder]

  TagList* = ref object of View
    ## The selected tags as removable chips that wrap onto lines. A trailing
    ## view, such as a text field, can share the last line.
    xController: TagController
    xChips: seq[Chip]
    xTrailing: View
    xMeasuredHeight, xLayoutWidth: float32

  TagInputFieldCell = ref object of TextFieldCell
    editor: FieldEditor

  TagInput* = ref object of View
    ## A text field that filters and adds tags from a dropdown list.
    xController: TagController
    xField: TextField
    xInlineList: TagList
    xList: PopupListView
    xHost: PopupHost
    xMatches: seq[ModelItem]
    xHighlight: int
    xFirstRow: int
    xMaxVisibleRows: int
    xListRequested: bool
    xPopupPresentation: PopupPresentation
    xSyncingText: bool
    xMeasuredHeight, xLayoutWidth: float32

  TagPicker* = ref object of StackView
    ## A `TagInput` and the selected tags, arranged by placement.
    xInput: TagInput
    xList: TagList
    xPlacement: TagListPlacement

const
  TagSpacing = 6.0'f32
  TagInlineInset = 3.0'f32
  TagInlineMinimumQueryWidth = 120.0'f32
  TagInputDefaultWidth = 280.0'f32
  TagRowHeight = 24.0'f32

proc tagQueryDidChange*(controller: TagController, sender: DynamicAgent) {.signal.}
  ## Sent when the typed query changes. Start a search here if needed.

proc tagSelectionDidChange*(controller: TagController, sender: DynamicAgent) {.signal.}
  ## Sent after the user adds or removes a tag. `setSelectedTags` does not send
  ## it, so loading tags from a model cannot loop back into that model.

protocol TagControllerDelegate {.selectorScope: protocol.}:
  ## Optional decisions about the tags a user adds.
  method shouldAddTag*(controller: TagController, item: ModelItem): bool {.optional.}
    ## Return false to reject a tag before it is added.

  method tagForText*(controller: TagController, text: string): ModelItem {.optional.}
    ## Build the tag for unmatched text when `allowsNewTags` is on. The default
    ## uses the trimmed text as both identifier and title.

# Model

proc tagItem*(identifier: string, title = ""): ModelItem =
  ## A tag model item. The title defaults to the identifier.
  modelItem(identifier, if title.len > 0: title else: identifier)

proc newTagController*(
    available: openArray[ModelItem] = [],
    selected: openArray[ModelItem] = [],
    matchMode = tmmPrefix,
    allowsNewTags = false,
): TagController =
  result = TagController(
    available: newArrayController(available),
    selected: newArrayController(selected),
    matchMode: matchMode,
    allowsNewTags: allowsNewTags,
    separators: {','},
  )
  initResponder(result)

proc delegate*(controller: TagController): Responder =
  controller.xDelegate.target

proc `delegate=`*(controller: TagController, delegate: Responder) =
  ## The delegate is held weakly; its owner must keep it alive.
  if not delegate.isNil:
    discard delegate.adopt(TagControllerDelegate)
  controller.xDelegate.target = delegate

proc query*(controller: TagController): string =
  controller.xQuery

proc `query=`*(controller: TagController, value: string) =
  if controller.xQuery != value:
    controller.xQuery = value
    emit controller.tagQueryDidChange(DynamicAgent(controller))

proc items(controller: ArrayController): seq[ModelItem] =
  for index in 0 ..< controller.len:
    result.add controller.itemAt(index)

proc selectedTags*(controller: TagController): seq[ModelItem] =
  controller.selected.items()

proc selectedIdentifiers*(controller: TagController): seq[string] =
  for index in 0 ..< controller.selected.len:
    result.add controller.selected.itemAt(index).identifier

proc isSelected*(controller: TagController, identifier: string): bool =
  controller.selected.indexOfIdentifier(identifier) >= 0

proc matchesQuery(controller: TagController, item: ModelItem): bool =
  let query = controller.xQuery.strip.toLower
  if query.len == 0:
    return true
  let title = item.displayTitle.toLower
  case controller.matchMode
  of tmmPrefix:
    title.startsWith(query)
  of tmmContains:
    query in title

proc matches*(controller: TagController): seq[ModelItem] =
  ## Available tags that are not selected and match the query, in arranged order.
  for index in 0 ..< controller.available.len:
    let item = controller.available.itemAt(index)
    if item.enabled and not item.hidden and not item.separator and
        item.identifier.len > 0 and not controller.isSelected(item.identifier) and
        controller.matchesQuery(item):
      result.add item

proc setAvailableTags*(controller: TagController, items: openArray[ModelItem]) =
  ## Replace the candidate tags, for example with new search results.
  controller.available.setItems(items)

proc setSelectedTags*(controller: TagController, items: openArray[ModelItem]) =
  ## Load the selected tags from a model. This is not a user edit, so it does
  ## not send `tagSelectionDidChange`.
  controller.selected.setItems(items)

proc addTag*(controller: TagController, item: ModelItem): bool {.discardable.} =
  ## Add a tag as a user edit. Returns false for a duplicate or rejected tag.
  if item.identifier.len == 0 or controller.isSelected(item.identifier):
    return
  let allowed = controller.delegate.asDynamicAgent().trySendLocal(
      shouldAddTag(), (controller: controller, item: item)
    )
  if allowed.isSome and not allowed.get:
    return
  controller.selected.addItem(item)
  emit controller.tagSelectionDidChange(DynamicAgent(controller))
  result = true

proc removeTag*(controller: TagController, identifier: string): bool {.discardable.} =
  ## Remove a tag as a user edit.
  if controller.selected.removeItem(identifier):
    emit controller.tagSelectionDidChange(DynamicAgent(controller))
    result = true

proc removeLastTag*(controller: TagController): bool {.discardable.} =
  if controller.selected.len > 0:
    result = controller.removeTag(
      controller.selected.itemAt(controller.selected.len - 1).identifier
    )

proc tagForText(controller: TagController, text: string): ModelItem =
  let custom = controller.delegate.asDynamicAgent().trySendLocal(
      tagForText(), (controller: controller, text: text)
    )
  if custom.isSome:
    custom.get
  else:
    tagItem(text)

proc commitQuery*(controller: TagController): bool {.discardable.} =
  ## Add the tag the query names: a match with the same title, or a new tag when
  ## `allowsNewTags` is on. Clears the query when a tag is added.
  let text = controller.xQuery.strip
  if text.len == 0:
    return
  for item in controller.matches():
    if item.displayTitle.toLower == text.toLower:
      result = controller.addTag(item)
      break
  if not result and controller.allowsNewTags:
    result = controller.addTag(controller.tagForText(text))
  if result:
    controller.query = ""

# Flow layout shared by the chip list and the inline input

type FlowLayout = object
  frames: seq[Rect]
  height: float32

func flowLayout(
    sizes: openArray[Size], width: float32, fillLast = false, minLastWidth = 0.0'f32
): FlowLayout =
  ## Place items left to right, wrapping at `width`. With `fillLast`, the last
  ## item takes the rest of its line, wrapping first if less than `minLastWidth`
  ## is left. Items are centered vertically in their line.
  var
    x, y, lineHeight = 0.0'f32
    lineStart = 0
  proc finishLine(layout: var FlowLayout, start: int, height: float32) =
    for index in start ..< layout.frames.len:
      let frame = layout.frames[index]
      layout.frames[index] = rect(
        frame.origin.x,
        frame.origin.y + (height - frame.size.height) / 2,
        frame.size.width,
        frame.size.height,
      )

  for index, size in sizes:
    let last = fillLast and index == sizes.high
    var itemWidth = min(size.width, max(width, 0.0'f32))
    if last:
      itemWidth = min(minLastWidth, max(width, 0.0'f32))
    if x > 0.0'f32 and x + itemWidth > width:
      result.finishLine(lineStart, lineHeight)
      x = 0.0'f32
      y += lineHeight + TagSpacing
      lineHeight = 0.0'f32
      lineStart = index
    if last:
      itemWidth = max(width - x, itemWidth)
    result.frames.add rect(x, y, itemWidth, size.height)
    x += itemWidth + TagSpacing
    lineHeight = max(lineHeight, size.height)
  result.finishLine(lineStart, lineHeight)
  result.height =
    if sizes.len == 0:
      0.0'f32
    else:
      y + lineHeight

# TagList

proc flowSizes(list: TagList): seq[Size] =
  for chip in list.xChips:
    result.add chip.sizeThatFits()
  if not list.xTrailing.isNil:
    result.add list.xTrailing.sizeThatFits()

proc flowHeight(list: TagList, width: float32): float32 =
  # Before the first layout there is no width, so measure a single line.
  let width = if width > 0.0'f32: width else: Inf.float32
  flowLayout(
    list.flowSizes(), width, not list.xTrailing.isNil, TagInlineMinimumQueryWidth
  ).height

proc relayoutForHeight(view: View) =
  ## A flow view's height depends on its width, which is known only after
  ## layout. Re-measure it and lay out its containers again.
  view.invalidateIntrinsicContentSize()
  var current = view.superview()
  while not current.isNil:
    current.setNeedsLayout()
    current = current.superview()

proc measureWidth(view: View, layoutWidth: float32): float32 =
  # Layout can measure a view at a provisional width, so prefer the width it
  # was last laid out at.
  if layoutWidth > 0.0'f32: layoutWidth else: view.bounds.size.width

proc refreshHeight(list: TagList) =
  let height = list.flowHeight(list.measureWidth(list.xLayoutWidth))
  if height != list.xMeasuredHeight:
    list.xMeasuredHeight = height
    list.relayoutForHeight()

protocol TagListLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(list: TagList): IntrinsicSize =
    list.xMeasuredHeight = list.flowHeight(list.measureWidth(list.xLayoutWidth))
    initIntrinsicSize(NoIntrinsicMetric, list.xMeasuredHeight)

  method layoutSubviews(list: TagList) =
    list.xLayoutWidth = list.bounds.size.width
    let layout = flowLayout(
      list.flowSizes(),
      list.bounds.size.width,
      not list.xTrailing.isNil,
      TagInlineMinimumQueryWidth,
    )
    for index, chip in list.xChips:
      chip.frame = layout.frames[index]
    if not list.xTrailing.isNil:
      list.xTrailing.frame = layout.frames[^1]
    list.refreshHeight()

proc controller*(list: TagList): TagController =
  list.xController

proc chips*(list: TagList): seq[Chip] =
  list.xChips

proc chipRemoval(controller: TagController, identifier: string): ChipRemoveHandler =
  let owner = controller.unsafeWeakRef()
  result = proc(chip: Chip) =
    if not owner.isNil:
      discard owner[].removeTag(identifier)

proc reloadTags*(list: TagList) =
  ## Rebuild the chips from the selected tags, reusing chips by identifier.
  var next: seq[Chip]
  for item in list.xController.selectedTags():
    var chip: Chip
    for existing in list.xChips:
      if existing.identifier == item.identifier:
        chip = existing
        break
    if chip.isNil:
      chip = newChip(item.displayTitle)
      chip.identifier = item.identifier
      chip.focusable = false
      chip.onRemove = list.xController.chipRemoval(item.identifier)
      list.addSubview(chip)
    elif chip.label != item.displayTitle:
      chip.label = item.displayTitle
    next.add chip
  for chip in list.xChips:
    if chip notin next:
      chip.removeFromSuperview()
  list.xChips = next
  list.refreshHeight()
  list.setNeedsLayout()
  list.needsDisplay = true

proc tagListSelectionChanged(list: TagList, sender: DynamicAgent) {.slot.} =
  list.reloadTags()

proc newTagList*(controller: TagController): TagList =
  ## Chips for the controller's selected tags.
  result = TagList(xController: controller)
  initViewFields(result)
  discard result.withProtocol(TagListLayout)
  connect(
    controller.selected, arrayControllerDidChange, result, tagListSelectionChanged
  )
  result.reloadTags()

proc trailingView*(list: TagList): View =
  list.xTrailing

proc `trailingView=`*(list: TagList, view: View) =
  ## A view placed after the chips, filling the rest of the last line.
  if list.xTrailing == view:
    return
  if not list.xTrailing.isNil:
    list.xTrailing.removeFromSuperview()
  list.xTrailing = view
  if not view.isNil:
    list.addSubview(view)
  list.refreshHeight()
  list.setNeedsLayout()

# TagInput

proc closeList*(input: TagInput)
proc refreshMatches(input: TagInput)
proc dismissHost(input: TagInput)
proc updateList(input: TagInput)

proc controller*(input: TagInput): TagController =
  input.xController

proc field*(input: TagInput): TextField =
  ## The text field the user types into.
  input.xField

proc tagList*(input: TagInput): TagList =
  ## The inline chips, or nil when the tags are shown elsewhere.
  input.xInlineList

proc matches*(input: TagInput): seq[ModelItem] =
  ## The tags the dropdown shows.
  input.xMatches

proc highlightedIndex*(input: TagInput): int =
  input.xHighlight

proc isListOpen*(input: TagInput): bool =
  not input.xHost.isNil

proc popupPresentation*(input: TagInput): PopupPresentation =
  input.xPopupPresentation

proc `popupPresentation=`*(input: TagInput, value: PopupPresentation) =
  ## How the dropdown is shown. The default draws it inside the window, like
  ## TokenField; `ppWindow` uses a native popup window that does not take focus.
  if input.xPopupPresentation != value:
    input.xPopupPresentation = value
    input.dismissHost()
    input.updateList()

proc maxVisibleRows*(input: TagInput): int =
  input.xMaxVisibleRows

proc `maxVisibleRows=`*(input: TagInput, value: int) =
  input.xMaxVisibleRows = max(value, 1)

proc listSize(input: TagInput): Size =
  let popup =
    rowPopupRect(input.bounds, input.xMatches.len, input.xMaxVisibleRows, TagRowHeight)
  initSize(max(popup.size.width, 1.0'f32), max(popup.size.height, 1.0'f32))

proc scrollHighlightToVisible(input: TagInput) =
  let visible = visibleRowItemCount(input.xMatches.len, input.xMaxVisibleRows)
  if input.xHighlight >= 0:
    if input.xHighlight < input.xFirstRow:
      input.xFirstRow = input.xHighlight
    elif input.xHighlight >= input.xFirstRow + visible:
      input.xFirstRow = input.xHighlight - visible + 1
  input.xFirstRow = input.xFirstRow.clampFirstIndex(input.xMatches.len, visible)

protocol TagInputListDataSource of PopupListDataSource:
  method totalCount(input: TagInput, popupList: PopupListView): int =
    input.xMatches.len

  method visibleCount(input: TagInput, popupList: PopupListView): int =
    visibleRowItemCount(input.xMatches.len, input.xMaxVisibleRows)

  method topIndex(input: TagInput, popupList: PopupListView): int =
    input.xFirstRow

  method selectionIndex(input: TagInput, popupList: PopupListView): int =
    -1

  method highlightIndex(input: TagInput, popupList: PopupListView): int =
    input.xHighlight

  method heightOfRow(input: TagInput, popupList: PopupListView): float32 =
    TagRowHeight

  method rowAtIndex(
      input: TagInput, popupList: PopupListView, index: int
  ): PopupListItem =
    if index in 0 ..< input.xMatches.len:
      result = PopupListItem(text: input.xMatches[index].displayTitle)

  method isInteractive(input: TagInput, popupList: PopupListView): bool =
    input.xField.isEnabled()

  method hasFocus(input: TagInput, popupList: PopupListView): bool =
    true

  method isShowing(input: TagInput, popupList: PopupListView): bool =
    input.isListOpen

proc pick(input: TagInput, index: int) =
  if index in 0 ..< input.xMatches.len:
    let item = input.xMatches[index]
    input.xListRequested = false
    discard input.xController.addTag(item)
    input.xController.query = ""
    input.refreshMatches()

protocol TagInputListDelegate of PopupListDelegate:
  method highlightRow(input: TagInput, popupList: PopupListView, index: int) =
    if index in 0 ..< input.xMatches.len and input.xHighlight != index:
      input.xHighlight = index
      popupList.needsDisplay = true

  method activateRow(input: TagInput, popupList: PopupListView, index: int) =
    input.pick(index)

  method dismissList(input: TagInput, popupList: PopupListView) =
    input.closeList()

  method scrollByRows(input: TagInput, popupList: PopupListView, delta: int) =
    let visible = visibleRowItemCount(input.xMatches.len, input.xMaxVisibleRows)
    input.xFirstRow =
      (input.xFirstRow + delta).clampFirstIndex(input.xMatches.len, visible)
    popupList.needsDisplay = true

  method moveFocus(input: TagInput, popupList: PopupListView, delta: int) =
    input.closeList()

proc popupList(input: TagInput): PopupListView =
  if input.xList.isNil:
    input.xList = newPopupListView(dataSource = input, delegate = input)
  input.xList

proc ownerWindow(input: TagInput): Window =
  let owner = input.window()
  if owner of Window:
    result = Window(owner)

proc dismissHost(input: TagInput) =
  let host = input.xHost
  input.xHost = nil
  if not host.isNil:
    discard host.dismissPopup()

proc updateList(input: TagInput) =
  ## Show, resize or hide the dropdown to match the request and the matches.
  let owner = input.ownerWindow()
  if not input.xListRequested or input.xMatches.len == 0 or owner.isNil:
    input.dismissHost()
    return
  let size = input.listSize()
  if not input.xHost.isNil:
    # Resize in place: recreating the popup would interrupt typing.
    input.xHost.resizePopup(size)
  else:
    let weakInput = input.unsafeWeakRef()
    let host = newPopupHost(
      owner,
      input,
      input.popupList(),
      size,
      title = "Tag suggestions",
      presentation = input.xPopupPresentation,
      # The list never takes focus. Closing it restores the responder that was
      # current when it opened: the field's active editor, so typing continues.
      transientOwner = input,
      focusContent = false,
      onDismiss = proc(host: PopupHost, reason: DismissReason) =
        if not weakInput.isNil and weakInput[].xHost == host:
          weakInput[].xHost = nil
          weakInput[].xListRequested = false
      ,
    )
    input.xHost = host
    if not host.presentPopup():
      input.xHost = nil
      return
    input.popupList().setNextResponder(input)
  input.popupList().needsDisplay = true

proc refreshMatches(input: TagInput) =
  let previous =
    if input.xHighlight in 0 ..< input.xMatches.len:
      input.xMatches[input.xHighlight].identifier
    else:
      ""
  input.xMatches = input.xController.matches()
  input.xHighlight = -1
  for index, item in input.xMatches:
    if item.identifier == previous:
      input.xHighlight = index
  # While typing, Return should add the best match without arrowing to it.
  if input.xHighlight < 0 and input.xMatches.len > 0 and
      input.xController.query.strip.len > 0:
    input.xHighlight = 0
  input.scrollHighlightToVisible()
  input.updateList()

proc openList*(input: TagInput) =
  ## Show every match, as clicking the field or its indicator does.
  input.xListRequested = true
  input.refreshMatches()

proc closeList*(input: TagInput) =
  input.xListRequested = false
  input.dismissHost()

proc moveHighlight(input: TagInput, delta: int) =
  if not input.isListOpen:
    input.openList()
    if input.xHighlight < 0 and input.xMatches.len > 0:
      input.xHighlight = if delta > 0: 0 else: input.xMatches.high
  elif input.xMatches.len > 0:
    input.xHighlight =
      if input.xHighlight < 0:
        (if delta > 0: 0 else: input.xMatches.high)
      else:
        (input.xHighlight + delta + input.xMatches.len) mod input.xMatches.len
  input.scrollHighlightToVisible()
  if not input.xList.isNil:
    input.xList.needsDisplay = true

proc showFieldText(input: TagInput, text: string) =
  if input.xField.stringValue != text:
    input.xSyncingText = true
    try:
      input.xField.stringValue = text
    finally:
      input.xSyncingText = false

# Keys typed into the field that drive the list rather than the text.

proc handleDown(input: TagInput): bool =
  input.moveHighlight(1)
  true

proc handleUp(input: TagInput): bool =
  if input.isListOpen:
    input.moveHighlight(-1)
    result = true

proc handleReturn(input: TagInput): bool =
  if input.isListOpen and input.xHighlight >= 0:
    input.pick(input.xHighlight)
    result = true
  elif input.xController.commitQuery():
    result = true

proc handleEscape(input: TagInput): bool =
  if input.isListOpen:
    input.closeList()
    result = true
  elif input.xController.query.len > 0:
    input.xController.query = ""
    result = true

proc handleDelete(input: TagInput): bool =
  if not input.xInlineList.isNil and input.xField.stringValue.len == 0:
    result = input.xController.removeLastTag()

proc handleTab(input: TagInput): bool =
  input.closeList()

proc editorCommand(
    input: TagInput, handle: proc(input: TagInput): bool {.nimcall.}
): dynamicSelectors.AroundMethod =
  let owner = input.unsafeWeakRef()
  result = proc(
      self: DynamicAgent,
      invocation: var dynamicSelectors.Invocation,
      next: dynamicSelectors.DynamicMethod,
  ) =
    if not owner.isNil and handle(owner[]):
      invocation.setResult(())
    elif not next.isNil:
      next(self, invocation)

protocol TagInputFieldCellEditing of CellEditingProtocol:
  method fieldEditorForView(cell: TagInputFieldCell, controlView: View): FieldEditor =
    cell.editor

proc tagFieldTextChanged(input: TagInput, sender: DynamicAgent) {.slot.} =
  if input.xSyncingText:
    return
  let controller = input.xController
  var text = input.xField.stringValue
  if controller.allowsNewTags and controller.separators != {} and
      text.find(controller.separators) >= 0:
    let parts = text.split(controller.separators)
    for part in parts[0 ..^ 2]:
      controller.query = part
      discard controller.commitQuery()
    text = parts[^1]
    input.showFieldText(text)
  input.xListRequested = true
  controller.query = text
  input.refreshMatches()

proc tagFieldIndicatorPressed(input: TagInput, sender: DynamicAgent) {.slot.} =
  if input.isListOpen:
    input.closeList()
  else:
    input.openList()

proc tagQueryChanged(input: TagInput, sender: DynamicAgent) {.slot.} =
  input.showFieldText(input.xController.query)
  input.refreshMatches()

proc tagOptionsChanged(input: TagInput, sender: DynamicAgent) {.slot.} =
  input.refreshMatches()

proc fittingHeight(input: TagInput): float32 =
  if input.xInlineList.isNil:
    input.xField.sizeThatFits().height
  else:
    input.xInlineList.flowHeight(
      input.measureWidth(input.xLayoutWidth) - TagInlineInset * 2
    ) + TagInlineInset * 2

protocol TagInputLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(input: TagInput): IntrinsicSize =
    input.xMeasuredHeight = input.fittingHeight()
    initIntrinsicSize(TagInputDefaultWidth, input.xMeasuredHeight)

  method layoutSubviews(input: TagInput) =
    input.xLayoutWidth = input.bounds.size.width
    if input.xInlineList.isNil:
      input.xField.frame = input.bounds
    else:
      input.xInlineList.frame = input.bounds.inset(insets(TagInlineInset))
      if input.fittingHeight() != input.xMeasuredHeight:
        input.relayoutForHeight()
    if not input.xHost.isNil:
      input.updateList()

protocol TagInputDrawing of ViewDrawingProtocol:
  method draw(input: TagInput, context: DrawContext) =
    # Inline tags share one text-field bezel with the borderless field.
    if input.xInlineList.isNil:
      return
    let
      frame = context.renderRectFor(input.bounds)
      states = input.xField.widgetStateSet()
      styleContext = controlStyle(srTextField, states)
      style = context.appearance.resolveTextFieldStyle(styleContext)
      chrome = chromeContext(
        context.appearance.resolveChromeName(styleContext),
        crTextField,
        cpFace,
        style.box.fill,
        states,
      )
    context.drawChromeBacking(
      chrome,
      initChromeExtras(
        context.renderViewParent(), frame, cornerRadius = style.box.cornerRadius
      ),
    )
    let root = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
    )
    context.drawChromeExtras(
      chrome, initChromeExtras(root, frame, cornerRadius = style.box.cornerRadius)
    )
    if ssFocusVisible in states:
      context.addFocusRing(frame, style.box)

proc newTagInput*(
    controller: TagController, placeholder = "Add tags…", inlineTags = false
): TagInput =
  ## A tag input for `controller`. With `inlineTags`, the selected tags are
  ## shown as chips inside the field.
  result = TagInput(
    xController: controller,
    xHighlight: -1,
    xMaxVisibleRows: 8,
    xPopupPresentation: ppInline,
  )
  initViewFields(result)

  let editor = newFieldEditor()
  for (command, handle) in [
    (moveDown(), handleDown), (moveUp(), handleUp), (deleteBackward(), handleDelete)
  ]:
    discard DynamicAgent(editor).pushMethod(command, result.editorCommand(handle))
  discard
    DynamicAgent(editor).pushMethod(insertNewline(), result.editorCommand(handleReturn))
  discard DynamicAgent(editor).pushMethod(insertTab(), result.editorCommand(handleTab))
  discard DynamicAgent(editor).pushMethod(
      cancelOperation(), result.editorCommand(handleEscape)
    )
  let cell = TagInputFieldCell(editor: editor)
  cell.initTextFieldCellFields()
  discard cell.withProtocol(TagInputFieldCellEditing)

  let field = newTextField()
  field.setCell(cell)
  field.placeholder = placeholder
  field.showsDropdownIndicator = true
  field.accessibilityRole = arComboBox
  result.xField = field
  # Clicking into the field lists every tag, like a web combobox.
  let owner = result.unsafeWeakRef()
  discard DynamicAgent(field).pushMethod(
      mouseDown(),
      proc(
          self: DynamicAgent,
          invocation: var dynamicSelectors.Invocation,
          next: dynamicSelectors.DynamicMethod,
      ) =
        let event = invocation.argsAs(MouseEvent)
        if not next.isNil:
          next(self, invocation)
        if not owner.isNil and not field.dropdownIndicatorRect().contains(
          event.location
        ):
          owner[].openList()
      ,
    )

  if inlineTags:
    field.bezeled = false
    let list = newTagList(controller)
    list.trailingView = field
    result.xInlineList = list
    result.addSubview(list)
  else:
    result.addSubview(field)

  discard result.withProtocol(TagInputListDataSource)
  discard result.withProtocol(TagInputListDelegate)
  discard result.withProtocol(TagInputLayout)
  discard result.withProtocol(TagInputDrawing)
  field.connect(textDidChange, result, tagFieldTextChanged)
  field.connect(dropdownIndicatorPressed, result, tagFieldIndicatorPressed)
  connect(controller, tagQueryDidChange, result, tagQueryChanged)
  connect(controller.available, arrayControllerDidChange, result, tagOptionsChanged)
  connect(controller.selected, arrayControllerDidChange, result, tagOptionsChanged)
  result.xMatches = controller.matches()

# TagPicker

proc input*(picker: TagPicker): TagInput =
  picker.xInput

proc tagList*(picker: TagPicker): TagList =
  ## The chip list, inline or separate.
  if picker.xList.isNil: picker.xInput.tagList else: picker.xList

proc placement*(picker: TagPicker): TagListPlacement =
  picker.xPlacement

proc controller*(picker: TagPicker): TagController =
  picker.xInput.controller

proc newTagPicker*(
    controller: TagController, placement = tlpInline, placeholder = "Add tags…"
): TagPicker =
  ## A tag input with its selected tags inline, above or below it.
  result = TagPicker(xPlacement: placement)
  initStackViewFields(result, laVertical)
  result.spacing = TagSpacing
  result.distribution = svdNatural
  result.alignment = svaFill
  result.xInput =
    newTagInput(controller, placeholder, inlineTags = placement == tlpInline)
  case placement
  of tlpInline:
    result.addArrangedSubview(result.xInput)
  of tlpAbove:
    result.xList = newTagList(controller)
    result.addArrangedSubview(result.xList, result.xInput)
  of tlpBelow:
    result.xList = newTagList(controller)
    result.addArrangedSubview(result.xInput, result.xList)
