import std/[options, strutils, tables]

import sigils/core

import ../accessibility/accessibilityprotocols
import ../containers/listbasics
import ../foundation/selectors
import ../text/textfields
import ../themes
import ../drawing
import ../foundation/events
import ../foundation/types
import ../foundation/undomanagers
import ../app/windows

import ./controls
import ./popuplists

export controls

type
  ComboBoxOption* = object
    identifier*: string
    displayText*: string
    objectValue*: ObjectValue
    enabled*: bool
    hidden*: bool
    separator*: bool
    image*: ImageResource
    tooltip*: string
    searchText*: string
    representedObject*: DynamicAgent

  ComboBoxOptionIndexCache = object
    searchCorpus: seq[string]
    visibleStorageIndexes: seq[int]
    identifierToVisibleIndex: Table[string, int]
    normalizedFilter: string
    corpusValid: bool
    visibleIndexesValid: bool

  ComboBoxOptionList* = ref object of Responder
    xOptions: seq[ComboBoxOption]
    xFilterText: string
    xIndexCache: ComboBoxOptionIndexCache

  ComboBox* = ref object of Control
    xDataSource: DynamicAgent
    xDataSourceItemCount: int
    xDataSourceItemCountValid: bool
    xPopupHighlightedIndex: int
    xPopupHighlightedIdentifier: string
    xPopupWindow: Window
    xPopupPresentation: PopupPresentation
    xPopupViewport: RowViewport
    xPopupList: PopupListView
    xOptionFilterText: string

  ComboBoxCell* = ref object of ActionCell
    xOptions: seq[ComboBoxOption]
    xStringValue: string
    xSelectedIndex: int
    xSelectedIdentifier: string
    xFilterText: string
    xEditable: bool
    xMaxVisibleItems: int
    xItemHeight: float32
    xIndexCache: ComboBoxOptionIndexCache

  ComboBoxStoredItem = object
    option: ComboBoxOption

func initComboBoxOption*(
  identifier = "",
  displayText = "",
  objectValue = emptyObjectValue(),
  enabled = true,
  hidden = false,
  separator = false,
  image: ImageResource = nil,
  tooltip = "",
  searchText = "",
  representedObject: DynamicAgent = nil,
): ComboBoxOption
proc comboBoxCell*(comboBox: ComboBox): ComboBoxCell
proc dataSource*(comboBox: ComboBox): DynamicAgent
proc highlightedIndex*(comboBox: ComboBox): int
proc `highlightedIndex=`*(comboBox: ComboBox, index: int)
proc highlightedOptionIdentifier*(comboBox: ComboBox): string
proc visibleItemCount*(comboBox: ComboBox): int
proc popupItemHeight*(comboBox: ComboBox): float32
proc popupFirstItemIndex*(comboBox: ComboBox): int
proc popupRect*(comboBox: ComboBox, bounds: Rect): Rect
proc popupItemRect*(comboBox: ComboBox, bounds: Rect, itemIndex: int): Rect
proc popupItemIndexAtPoint*(comboBox: ComboBox, bounds: Rect, point: Point): int
proc popupScrollerKnobRect*(comboBox: ComboBox, bounds: Rect): Rect
proc movePopupHighlight*(comboBox: ComboBox, delta: int)

proc scrollPopupItemToVisible(comboBox: ComboBox, itemIndex: int)
proc setPopupNeedsDisplay(comboBox: ComboBox)
proc setHoveredPopupIndex(comboBox: ComboBox, index: int)
proc firstSelectableOptionIndex(comboBox: ComboBox): int
proc nextSelectableOptionIndex(comboBox: ComboBox, start, delta: int): int
proc movePopupHighlightTo(comboBox: ComboBox, index: int)
proc pagePopupHighlight(comboBox: ComboBox, deltaPages: int)
proc canScrollPopupRows(comboBox: ComboBox, delta: int): bool
proc scrollPopupRows(comboBox: ComboBox, delta: int)
proc popupPresentationPreference(comboBox: ComboBox): PopupPresentation
proc popupWindowActive(comboBox: ComboBox): bool
proc shouldUseWindowPopup(comboBox: ComboBox): bool
proc usesInlinePopup(comboBox: ComboBox): bool
proc beginPopupSession(comboBox: ComboBox)
proc endPopupSession(comboBox: ComboBox, reason = tdrProgrammatic): bool
proc dismissPopupFromSession(comboBox: ComboBox, reason: DismissReason)
proc openPopupWindow(comboBox: ComboBox)
proc closePopupWindow(comboBox: ComboBox, restoreOwner = true)
proc reactivateOwnerWindow(comboBox: ComboBox)
proc updatePopupPresentation(comboBox: ComboBox)
proc popupListData(comboBox: ComboBox): PopupListData
proc popupListActions(comboBox: ComboBox): PopupListActions
proc popupList(comboBox: ComboBox): PopupListView
proc itemObjectValueAtIndex*(comboBox: ComboBox, index: int): ObjectValue
proc `selectedOptionIdentifier=`*(comboBox: ComboBox, identifier: string)
proc `optionFilterText=`*(comboBox: ComboBox, text: string)
proc indexOfOptionMatchingText*(comboBox: ComboBox, text: string, startIndex = 0): int
proc insertStoredItem(
  comboBox: ComboBox, title: string, objectValue: ObjectValue, index: int
)

proc insertStoredOption(comboBox: ComboBox, option: ComboBoxOption, index: int)

proc cellStringValue(cell: ComboBoxCell): string
proc setCellSelectedIndex(cell: ComboBoxCell, index: int)
proc cellMaxVisibleItems(cell: ComboBoxCell): int
proc setCellMaxVisibleItems(cell: ComboBoxCell, value: int)
proc cellItemHeight(cell: ComboBoxCell): float32
proc setCellItemHeight(cell: ComboBoxCell, value: float32)
proc cellIsEditable(cell: ComboBoxCell): bool
proc setCellEditable(cell: ComboBoxCell, editable: bool)
proc cellNumberOfItems(cell: ComboBoxCell): int
proc cellItemAtIndex(cell: ComboBoxCell, index: int): string
proc cellOptionAtIndex(cell: ComboBoxCell, index: int): ComboBoxOption
proc cellIndexOfOptionIdentifier(cell: ComboBoxCell, identifier: string): int
proc cellInsertOption(cell: ComboBoxCell, option: ComboBoxOption, index: int)

proc cellRemoveItemAtIndex(cell: ComboBoxCell, index: int)
proc cellRemoveAllItems(cell: ComboBoxCell)

protocol ComboBoxDataSource {.selectorScope: protocol.}:
  method itemCount*(comboBox: ComboBox): int {.optional.}
  method objectValueAtIndex*(comboBox: ComboBox, index: int): string {.optional.}
  method typedObjectValueAtIndex*(
    comboBox: ComboBox, index: int
  ): ObjectValue {.optional.}

  method comboBoxOptionAtIndex*(
    comboBox: ComboBox, index: int
  ): ComboBoxOption {.optional.}

  method indexOfComboBoxOptionIdentifier*(
    comboBox: ComboBox, identifier: string
  ): int {.optional.}

  method setComboBoxOptionFilterText*(comboBox: ComboBox, text: string) {.optional.}

protocol ComboBoxEvents:
  proc selectionIsChanging*(comboBox: ComboBox, sender: DynamicAgent) {.signal.}
  proc selectionDidChange*(comboBox: ComboBox, sender: DynamicAgent) {.signal.}

protocol ComboBoxViewProtocol:
  method pointInside*(point: Point): bool

func initComboBoxOption*(
    identifier = "",
    displayText = "",
    objectValue = emptyObjectValue(),
    enabled = true,
    hidden = false,
    separator = false,
    image: ImageResource = nil,
    tooltip = "",
    searchText = "",
    representedObject: DynamicAgent = nil,
): ComboBoxOption =
  ComboBoxOption(
    identifier: identifier,
    displayText: displayText,
    objectValue: objectValue,
    enabled: enabled,
    hidden: hidden,
    separator: separator,
    image: image,
    tooltip: tooltip,
    searchText: searchText,
    representedObject: representedObject,
  )

proc optionDisplayText(option: ComboBoxOption): string =
  if option.displayText.len > 0:
    option.displayText
  else:
    option.objectValue.formatObjectValue(initObjectFormatContext(role = ovrComboBox))

proc resolvedObjectValue(option: ComboBoxOption): ObjectValue =
  if option.objectValue.isNilOrEmpty() and option.displayText.len > 0:
    toObj(option.displayText)
  else:
    option.objectValue

proc normalizedSearchText(text: string): string =
  text.strip().toLowerAscii()

proc optionSearchCorpus(option: ComboBoxOption): string =
  result = option.searchText
  let displayText = option.optionDisplayText()
  if displayText.len > 0:
    if result.len > 0:
      result.add " "
    result.add displayText
  let objectText =
    option.objectValue.formatObjectValue(initObjectFormatContext(role = ovrComboBox))
  if objectText.len > 0 and objectText != displayText:
    if result.len > 0:
      result.add " "
    result.add objectText

proc optionMatchesFilter(option: ComboBoxOption, filterText: string): bool =
  let normalizedFilter = filterText.normalizedSearchText()
  if normalizedFilter.len == 0:
    return true
  option.optionSearchCorpus().normalizedSearchText().contains(normalizedFilter)

proc optionIsSelectable(option: ComboBoxOption): bool =
  option.enabled and not option.separator and not option.hidden

proc invalidateOptionIndex(cache: var ComboBoxOptionIndexCache, corpusChanged = true) =
  if corpusChanged:
    cache.corpusValid = false
  cache.visibleIndexesValid = false

proc ensureSearchCorpus(
    cache: var ComboBoxOptionIndexCache, options: openArray[ComboBoxOption]
) =
  if cache.corpusValid and cache.searchCorpus.len == options.len:
    return
  cache.searchCorpus.setLen(0)
  for option in options:
    cache.searchCorpus.add option.optionSearchCorpus().normalizedSearchText()
  cache.corpusValid = true
  cache.visibleIndexesValid = false

proc ensureVisibleOptionIndexes(
    cache: var ComboBoxOptionIndexCache,
    options: openArray[ComboBoxOption],
    filterText: string,
) =
  let normalizedFilter = filterText.normalizedSearchText()
  if cache.visibleIndexesValid and cache.normalizedFilter == normalizedFilter:
    return

  if normalizedFilter.len > 0:
    cache.ensureSearchCorpus(options)
  cache.visibleStorageIndexes.setLen(0)
  cache.identifierToVisibleIndex = initTable[string, int]()
  for storageIndex, option in options:
    let matches =
      normalizedFilter.len == 0 or
      cache.searchCorpus[storageIndex].contains(normalizedFilter)
    if not option.hidden and matches:
      let visibleIndex = cache.visibleStorageIndexes.len
      cache.visibleStorageIndexes.add storageIndex
      if option.identifier.len > 0 and
          option.identifier notin cache.identifierToVisibleIndex:
        cache.identifierToVisibleIndex[option.identifier] = visibleIndex
  cache.normalizedFilter = normalizedFilter
  cache.visibleIndexesValid = true

proc visibleOptionCount(
    cache: var ComboBoxOptionIndexCache,
    options: openArray[ComboBoxOption],
    filterText: string,
): int =
  cache.ensureVisibleOptionIndexes(options, filterText)
  cache.visibleStorageIndexes.len

proc visibleOptionStorageIndex(
    cache: var ComboBoxOptionIndexCache,
    options: openArray[ComboBoxOption],
    visibleIndex: int,
    filterText: string,
): int =
  cache.ensureVisibleOptionIndexes(options, filterText)
  if visibleIndex in 0 ..< cache.visibleStorageIndexes.len:
    cache.visibleStorageIndexes[visibleIndex]
  else:
    -1

proc visibleOptionInsertionIndex(
    cache: var ComboBoxOptionIndexCache,
    options: openArray[ComboBoxOption],
    visibleIndex: int,
    filterText: string,
): int =
  cache.ensureVisibleOptionIndexes(options, filterText)
  let target = max(visibleIndex, 0)
  if target < cache.visibleStorageIndexes.len:
    cache.visibleStorageIndexes[target]
  else:
    options.len

proc optionAtVisibleIndex(
    cache: var ComboBoxOptionIndexCache,
    options: openArray[ComboBoxOption],
    index: int,
    filterText: string,
): ComboBoxOption =
  let storageIndex = cache.visibleOptionStorageIndex(options, index, filterText)
  if storageIndex >= 0:
    result = options[storageIndex]

proc indexOfVisibleOptionIdentifier(
    cache: var ComboBoxOptionIndexCache,
    options: openArray[ComboBoxOption],
    identifier, filterText: string,
): int =
  if identifier.len == 0:
    return -1
  cache.ensureVisibleOptionIndexes(options, filterText)
  cache.identifierToVisibleIndex.getOrDefault(identifier, -1)

proc initComboBoxOptionListFields(
    list: ComboBoxOptionList, options: openArray[ComboBoxOption] = []
) =
  initResponder(list)
  list.xOptions = @options

proc options*(list: ComboBoxOptionList): seq[ComboBoxOption] =
  list.xOptions

proc `options=`*(list: ComboBoxOptionList, options: openArray[ComboBoxOption]) =
  list.xOptions = @options
  list.xIndexCache.invalidateOptionIndex()

proc sourceLen*(list: ComboBoxOptionList): int =
  list.xOptions.len

proc len*(list: ComboBoxOptionList): int =
  list.xIndexCache.visibleOptionCount(list.xOptions, list.xFilterText)

proc filterText*(list: ComboBoxOptionList): string =
  list.xFilterText

proc `filterText=`*(list: ComboBoxOptionList, text: string) =
  if list.xFilterText == text:
    return
  list.xFilterText = text
  list.xIndexCache.invalidateOptionIndex(corpusChanged = false)

proc optionListItemAtIndex*(list: ComboBoxOptionList, index: int): ComboBoxOption =
  result = list.xIndexCache.optionAtVisibleIndex(list.xOptions, index, list.xFilterText)

proc optionListIndexOfIdentifier*(list: ComboBoxOptionList, identifier: string): int =
  list.xIndexCache.indexOfVisibleOptionIdentifier(
    list.xOptions, identifier, list.xFilterText
  )

proc add*(list: ComboBoxOptionList, option: ComboBoxOption) =
  list.xOptions.add option
  list.xIndexCache.invalidateOptionIndex()

proc insert*(list: ComboBoxOptionList, option: ComboBoxOption, index: int) =
  let storageIndex =
    list.xIndexCache.visibleOptionInsertionIndex(list.xOptions, index, list.xFilterText)
  list.xOptions.insert(option, storageIndex)
  list.xIndexCache.invalidateOptionIndex()

proc delete*(list: ComboBoxOptionList, index: int) =
  let storageIndex =
    list.xIndexCache.visibleOptionStorageIndex(list.xOptions, index, list.xFilterText)
  if storageIndex >= 0:
    list.xOptions.delete(storageIndex)
    list.xIndexCache.invalidateOptionIndex()

proc delete*(list: ComboBoxOptionList, identifier: string): bool {.discardable.} =
  if identifier.len == 0:
    return false
  var storageIndex = -1
  for index, option in list.xOptions:
    if option.identifier == identifier:
      storageIndex = index
  if storageIndex < 0:
    return false
  list.xOptions.delete(storageIndex)
  list.xIndexCache.invalidateOptionIndex()
  true

proc clear*(list: ComboBoxOptionList) =
  list.xOptions.setLen(0)
  list.xIndexCache.invalidateOptionIndex()

proc addOptionListItem*(list: ComboBoxOptionList, option: ComboBoxOption) =
  list.add(option)

proc insertOptionListItem*(
    list: ComboBoxOptionList, option: ComboBoxOption, index: int
) =
  list.insert(option, index)

proc removeOptionListItemAtIndex*(list: ComboBoxOptionList, index: int) =
  list.delete(index)

proc removeOptionListItemWithIdentifier*(
    list: ComboBoxOptionList, identifier: string
): bool {.discardable.} =
  list.delete(identifier)

proc removeAllOptionListItems*(list: ComboBoxOptionList) =
  list.clear()

protocol ComboBoxOptionListDataSource of ComboBoxDataSource:
  method itemCount(list: ComboBoxOptionList, comboBox: ComboBox): int =
    list.len()

  method comboBoxOptionAtIndex(
      list: ComboBoxOptionList, comboBox: ComboBox, index: int
  ): ComboBoxOption =
    list.optionListItemAtIndex(index)

  method indexOfComboBoxOptionIdentifier(
      list: ComboBoxOptionList, comboBox: ComboBox, identifier: string
  ): int =
    list.optionListIndexOfIdentifier(identifier)

  method setComboBoxOptionFilterText(
      list: ComboBoxOptionList, comboBox: ComboBox, text: string
  ) =
    list.filterText = text

proc newComboBoxOptionList*(
    options: openArray[ComboBoxOption] = []
): ComboBoxOptionList =
  result = ComboBoxOptionList()
  result.initComboBoxOptionListFields(options)
  discard result.withProtocol(ComboBoxOptionListDataSource)

protocol DefaultComboBoxAccessibility of AccessibilityProtocol:
  method accessibilityRole(comboBox: ComboBox): AccessibilityRole =
    arComboBox

  method accessibilityLabel(comboBox: ComboBox): string =
    if comboBox.xAccessibilityLabel.len > 0:
      comboBox.xAccessibilityLabel
    else:
      comboBox.identifier()

  method accessibilityValue(comboBox: ComboBox): string =
    comboBox.stringValue()

  method accessibilityTraits(comboBox: ComboBox): AccessibilityTraits =
    result = comboBox.xAccessibilityTraits + {atSelectable}
    if comboBox.isEditable():
      result.incl atEditable
    if not comboBox.isEnabled():
      result.incl atDisabled
    if comboBox.focused():
      result.incl atFocused

  method isAccessibilityElement(comboBox: ComboBox): bool =
    true

  method accessibilityActionNames(comboBox: ComboBox): seq[string] =
    @[AccessibilityActionShowMenu]

  method accessibilityPerformAction(comboBox: ComboBox, action: string): bool =
    if action != AccessibilityActionShowMenu or not comboBox.isEnabled():
      return false
    comboBox.popupOpen = true
    true

protocol ComboBoxProtocol {.selectorScope: protocol.} from ComboBox:
  property selectedIndex -> int
  property selectedOptionIdentifier -> string
  property popupOpen -> bool
  property maxVisibleItems -> int
  property itemHeight -> float32
  property popupPresentation -> PopupPresentation
  property optionFilterText -> string

  method selectedIndex(comboBox: ComboBox): int =
    comboBox.indexOfSelectedItem()

  method setSelectedIndex(comboBox: ComboBox, index: int) =
    if index < 0:
      comboBox.deselectItem()
    else:
      comboBox.selectItemAtIndex(index)

  method popupOpen(comboBox: ComboBox): bool =
    ssOpen in comboBox.widgetStateSet()

  method setPopupOpen(comboBox: ComboBox, open: bool) =
    let wasOpen = comboBox.popupOpen()
    let shouldOpen = open and comboBox.isEnabled and comboBox.numberOfItems() > 0
    if wasOpen == shouldOpen:
      if shouldOpen:
        comboBox.updatePopupPresentation()
      return
    View(comboBox).setWidgetState(ssOpen, shouldOpen)
    if shouldOpen:
      let selected = comboBox.indexOfSelectedItem()
      comboBox.xPopupHighlightedIndex =
        if selected >= 0 and comboBox.optionAtIndex(selected).optionIsSelectable():
          selected
        else:
          comboBox.firstSelectableOptionIndex()
      comboBox.xPopupHighlightedIdentifier =
        if comboBox.xPopupHighlightedIndex >= 0:
          comboBox.optionIdentifierAtIndex(comboBox.xPopupHighlightedIndex)
        else:
          ""
      comboBox.scrollPopupItemToVisible(comboBox.xPopupHighlightedIndex)
      comboBox.updatePopupPresentation()
    else:
      discard comboBox.endPopupSession()
      comboBox.closePopupWindow()
      comboBox.xPopupHighlightedIndex = -1
      comboBox.xPopupHighlightedIdentifier = ""
      comboBox.setWidgetState(ssPressed, false)
      comboBox.popupList().resetPopupListTracking()
      comboBox.xPopupViewport.reset()

  method maxVisibleItems(comboBox: ComboBox): int =
    comboBox.comboBoxCell().cellMaxVisibleItems()

  method setMaxVisibleItems(comboBox: ComboBox, value: int) =
    comboBox.comboBoxCell().setCellMaxVisibleItems(value)
    if comboBox.popupOpen():
      comboBox.scrollPopupItemToVisible(comboBox.highlightedIndex())
      comboBox.updatePopupPresentation()
      comboBox.setPopupNeedsDisplay()

  method itemHeight(comboBox: ComboBox): float32 =
    comboBox.comboBoxCell().cellItemHeight()

  method setItemHeight(comboBox: ComboBox, value: float32) =
    comboBox.comboBoxCell().setCellItemHeight(value)
    if comboBox.popupOpen():
      comboBox.scrollPopupItemToVisible(comboBox.highlightedIndex())
      comboBox.updatePopupPresentation()
      comboBox.setPopupNeedsDisplay()

  method popupPresentation(comboBox: ComboBox): PopupPresentation =
    comboBox.xPopupPresentation

  method setPopupPresentation(comboBox: ComboBox, presentation: PopupPresentation) =
    if comboBox.xPopupPresentation == presentation:
      return
    comboBox.xPopupPresentation = presentation
    comboBox.updatePopupPresentation()
    comboBox.setNeedsDisplay(true)

  method optionFilterText(comboBox: ComboBox): string =
    comboBox.xOptionFilterText

  method setOptionFilterText(comboBox: ComboBox, text: string) =
    if comboBox.xOptionFilterText == text:
      return
    comboBox.xOptionFilterText = text
    let cell = comboBox.comboBoxCell()
    cell.xFilterText = text
    cell.xIndexCache.invalidateOptionIndex(corpusChanged = false)
    let source = comboBox.dataSource()
    if not source.isNil:
      discard source.trySendLocal(
        setComboBoxOptionFilterText(), (comboBox: comboBox, text: text)
      )
    comboBox.xPopupViewport.reset()
    comboBox.reloadData()

  method numberOfItems*(comboBox: ComboBox): int =
    let source = comboBox.dataSource()
    if not source.isNil:
      if comboBox.xDataSourceItemCountValid:
        return comboBox.xDataSourceItemCount
      let count = source.trySendLocal(itemCount(), comboBox)
      if count.isSome:
        comboBox.xDataSourceItemCount = max(count.get(), 0)
        comboBox.xDataSourceItemCountValid = true
        return comboBox.xDataSourceItemCount
    comboBox.comboBoxCell().cellNumberOfItems()

  method optionAtIndex*(comboBox: ComboBox, index: int): ComboBoxOption =
    if index < 0 or index >= comboBox.numberOfItems():
      return ComboBoxOption()
    let source = comboBox.dataSource()
    if not source.isNil:
      let option =
        source.trySendLocal(comboBoxOptionAtIndex(), (comboBox: comboBox, index: index))
      if option.isSome:
        return option.get()
      let typedItem = source.trySendLocal(
        typedObjectValueAtIndex(), (comboBox: comboBox, index: index)
      )
      if typedItem.isSome:
        let objectValue = typedItem.get()
        return initComboBoxOption(
          displayText = Control(comboBox).formatObjectValue(objectValue, ovrComboBox),
          objectValue = objectValue,
        )
      let item =
        source.trySendLocal(objectValueAtIndex(), (comboBox: comboBox, index: index))
      if item.isSome:
        return
          initComboBoxOption(displayText = item.get(), objectValue = toObj(item.get()))
    comboBox.comboBoxCell().cellOptionAtIndex(index)

  method itemAtIndex*(comboBox: ComboBox, index: int): string =
    if index < 0 or index >= comboBox.numberOfItems():
      return ""
    comboBox.optionAtIndex(index).optionDisplayText()

  method optionIdentifierAtIndex*(comboBox: ComboBox, index: int): string =
    comboBox.optionAtIndex(index).identifier

  method optionObjectValueAtIndex*(comboBox: ComboBox, index: int): ObjectValue =
    if index < 0 or index >= comboBox.numberOfItems():
      return nilObjectValue()
    comboBox.optionAtIndex(index).resolvedObjectValue()

  method optionIsEnabledAtIndex*(comboBox: ComboBox, index: int): bool =
    comboBox.optionAtIndex(index).enabled

  method optionIsSeparatorAtIndex*(comboBox: ComboBox, index: int): bool =
    comboBox.optionAtIndex(index).separator

  method indexOfOptionIdentifier*(comboBox: ComboBox, identifier: string): int =
    if identifier.len == 0:
      return -1
    let source = comboBox.dataSource()
    if not source.isNil:
      let found = source.trySendLocal(
        indexOfComboBoxOptionIdentifier(), (comboBox: comboBox, identifier: identifier)
      )
      if found.isSome:
        return found.get()
    for idx in 0 ..< comboBox.numberOfItems():
      if comboBox.optionIdentifierAtIndex(idx) == identifier:
        return idx
    -1

  method indexOfItem*(comboBox: ComboBox, value: string): int =
    for idx in 0 ..< comboBox.numberOfItems():
      if comboBox.itemAtIndex(idx) == value:
        return idx
    -1

  method indexOfSelectedItem*(comboBox: ComboBox): int =
    let cell = comboBox.comboBoxCell()
    if cell.xSelectedIdentifier.len > 0:
      let identifierIndex = comboBox.indexOfOptionIdentifier(cell.xSelectedIdentifier)
      if identifierIndex >= 0:
        cell.xSelectedIndex = identifierIndex
        cell.xStringValue = comboBox.itemAtIndex(identifierIndex)
        return identifierIndex
      cell.xSelectedIndex = -1
      return -1
    if cell.xSelectedIndex < 0 and cell.xStringValue.len == 0:
      return -1
    if cell.xSelectedIndex >= 0 and cell.xSelectedIndex < comboBox.numberOfItems() and
        comboBox.itemAtIndex(cell.xSelectedIndex) == cell.xStringValue:
      return cell.xSelectedIndex
    cell.xSelectedIndex = comboBox.indexOfItem(cell.xStringValue)
    cell.xSelectedIndex

  method selectedOptionIdentifier*(comboBox: ComboBox): string =
    comboBox.comboBoxCell().xSelectedIdentifier

  method setSelectedOptionIdentifier(comboBox: ComboBox, identifier: string) =
    comboBox.selectOptionWithIdentifier(identifier)

  method selectOptionWithIdentifier*(comboBox: ComboBox, identifier: string) =
    if identifier.len == 0:
      comboBox.deselectItem()
      return
    let index = comboBox.indexOfOptionIdentifier(identifier)
    if index >= 0:
      comboBox.selectItemAtIndex(index)

  method selectItemAtIndex*(comboBox: ComboBox, index: int) =
    if index < 0 or index >= comboBox.numberOfItems():
      return
    let
      cell = comboBox.comboBoxCell()
      option = comboBox.optionAtIndex(index)
      value = option.optionDisplayText()
    if not option.optionIsSelectable():
      return
    if cell.xSelectedIndex == index and cell.xStringValue == value and
        cell.xSelectedIdentifier == option.identifier:
      Control(comboBox).setObjectValue(comboBox.optionObjectValueAtIndex(index))
      return
    let oldValue = cell.xStringValue
    comboBox.findUndoManager().registerValueChange(
      proc(value: string) =
        comboBox.setComboBoxStringValue(value),
      oldValue,
      "Change Choice",
    )
    cell.xSelectedIndex = index
    cell.xStringValue = value
    cell.xSelectedIdentifier = option.identifier
    Control(comboBox).setObjectValue(comboBox.optionObjectValueAtIndex(index))
    cell.invalidateControlMetrics()
    comboBox.postAccessibilityNotification(anSelectionChanged)

  method deselectItem*(comboBox: ComboBox) =
    let cell = comboBox.comboBoxCell()
    if cell.xSelectedIndex < 0 and cell.xStringValue.len == 0 and
        cell.xSelectedIdentifier.len == 0:
      return
    let oldValue = cell.xStringValue
    comboBox.findUndoManager().registerValueChange(
      proc(value: string) =
        comboBox.setComboBoxStringValue(value),
      oldValue,
      "Change Choice",
    )
    cell.xSelectedIndex = -1
    cell.xSelectedIdentifier = ""
    cell.xStringValue = ""
    Control(comboBox).setObjectValue(emptyObjectValue())
    comboBox.highlightedIndex = -1
    cell.invalidateControlMetrics()
    comboBox.postAccessibilityNotification(anSelectionChanged)

  method addOption*(comboBox: ComboBox, option: ComboBoxOption) =
    comboBox.insertStoredOption(option, comboBox.comboBoxCell().cellNumberOfItems())

  method insertOption*(comboBox: ComboBox, option: ComboBoxOption, index: int) =
    comboBox.insertStoredOption(option, index)

  method addItem*(comboBox: ComboBox, value: string) =
    comboBox.addOption(
      initComboBoxOption(displayText = value, objectValue = toObj(value))
    )

  method insertItem*(comboBox: ComboBox, value: string, index: int) =
    comboBox.insertStoredItem(value, toObj(value), index)

  method removeItemAtIndex*(comboBox: ComboBox, index: int) =
    if index >= 0 and index < comboBox.comboBoxCell().cellNumberOfItems():
      let item =
        ComboBoxStoredItem(option: comboBox.comboBoxCell().cellOptionAtIndex(index))
      comboBox.findUndoManager().registerCollectionRemove(
        proc(index: int, item: ComboBoxStoredItem) =
          comboBox.insertStoredOption(item.option, index),
        index,
        item,
        "Remove Choice",
      )
    comboBox.comboBoxCell().cellRemoveItemAtIndex(index)
    let selected = comboBox.indexOfSelectedItem()
    Control(comboBox).setObjectValue(
      if selected >= 0:
        comboBox.optionObjectValueAtIndex(selected)
      else:
        emptyObjectValue()
    )
    if comboBox.numberOfItems() == 0:
      comboBox.closePopup()

  method removeOptionWithIdentifier*(comboBox: ComboBox, identifier: string): bool =
    let index = comboBox.indexOfOptionIdentifier(identifier)
    if index < 0:
      return false
    comboBox.removeItemAtIndex(index)
    true

  method removeAllItems*(comboBox: ComboBox) =
    let
      cell = comboBox.comboBoxCell()
      options = cell.xOptions
      oldValue = cell.xStringValue
      oldIdentifier = cell.xSelectedIdentifier
    if options.len > 0 or oldValue.len > 0 or oldIdentifier.len > 0:
      comboBox.findUndoManager().registerUndo(
        proc() =
          for idx, option in options:
            comboBox.insertStoredOption(option, idx)
          comboBox.setComboBoxStringValue(oldValue)
          comboBox.comboBoxCell().xSelectedIdentifier = oldIdentifier,
        "Remove Choices",
      )
    comboBox.comboBoxCell().cellRemoveAllItems()
    Control(comboBox).setObjectValue(emptyObjectValue())
    comboBox.closePopup()

  method removeAllOptions*(comboBox: ComboBox) =
    comboBox.removeAllItems()

  method activateItemAtIndex*(comboBox: ComboBox, index: int) =
    if index < 0 or index >= comboBox.numberOfItems():
      return
    let option = comboBox.optionAtIndex(index)
    if not option.optionIsSelectable():
      return
    comboBox.selectItemAtIndex(index)
    emit comboBox.selectionDidChange(DynamicAgent(comboBox))
    discard comboBox.sendAction()

  method openPopup*(comboBox: ComboBox) =
    comboBox.setPopupOpen(true)

  method closePopup*(comboBox: ComboBox) =
    comboBox.setPopupOpen(false)

  method togglePopup*(comboBox: ComboBox) =
    comboBox.setPopupOpen(not comboBox.popupOpen())

  method reloadData*(comboBox: ComboBox) =
    comboBox.xDataSourceItemCountValid = false
    let cell = comboBox.comboBoxCell()
    if comboBox.numberOfItems() == 0:
      cell.xSelectedIndex = -1
      if cell.xSelectedIdentifier.len == 0:
        cell.xStringValue = ""
      comboBox.closePopup()
    else:
      cell.xSelectedIndex = comboBox.indexOfSelectedItem()
      if cell.xSelectedIndex < 0 and cell.xStringValue.len > 0 and
          cell.xSelectedIdentifier.len > 0:
        cell.xStringValue = ""
    if comboBox.highlightedOptionIdentifier().len > 0:
      comboBox.xPopupHighlightedIndex =
        comboBox.indexOfOptionIdentifier(comboBox.highlightedOptionIdentifier())
    comboBox.invalidateIntrinsicContentSize()
    comboBox.setNeedsDisplay(true)

protocol DefaultComboBoxView of ComboBoxViewProtocol:
  method pointInside(comboBox: ComboBox, point: Point): bool =
    comboBox.bounds().contains(point) or (
      comboBox.usesInlinePopup() and
      comboBox.popupRect(comboBox.bounds()).contains(point)
    )

  method hitTestLevel(comboBox: ComboBox, point: Point): int =
    if comboBox.usesInlinePopup() and
        comboBox.popupRect(comboBox.bounds()).contains(point):
      PopupDrawLevel.int
    else:
      DefaultDrawLevel.int

protocol DefaultComboBoxAction of ButtonActionProtocol:
  method performClick(comboBox: ComboBox, args: ActionArgs) =
    if comboBox.isEnabled:
      if comboBox.popupOpen() and comboBox.highlightedIndex() >= 0:
        comboBox.activateItemAtIndex(comboBox.highlightedIndex())
        comboBox.closePopup()
      else:
        comboBox.togglePopup()

protocol DefaultComboBoxDrawing of ViewDrawingProtocol:
  method draw(comboBox: ComboBox, context: DrawContext) =
    let absoluteFrame = context.renderRectFor(comboBox.bounds)
    let styleStates = comboBox.widgetStateSet()
    let style = context.appearance.resolveComboBoxStyle(
      controlStyle(
        srComboBox, styleStates, id = comboBox.styleId, classes = comboBox.styleClasses
      )
    )
    let comboChrome =
      chromeContext(style.chrome, crComboBox, cpFace, style.box.fill, styleStates)

    context.drawChromeBacking(
      comboChrome,
      initChromeExtras(
        context.renderParent(),
        absoluteFrame,
        cornerRadius = style.box.cornerRadius,
        cornerRadii = style.box.cornerRadii,
      ),
    )
    let comboRoot = context.addRenderRectangle(
      absoluteFrame,
      context.appearance.chromeFill(comboChrome),
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      lightMaskContent = true,
      cornerRadii = style.box.cornerRadii,
    )
    context.drawChromeExtras(
      comboChrome,
      initChromeExtras(
        comboRoot,
        absoluteFrame,
        cornerRadius = style.box.cornerRadius,
        cornerRadii = style.box.cornerRadii,
      ),
    )
    if comboBox.isFocusVisible:
      context.addFocusRing(absoluteFrame, style.box)

    let
      arrowRect = style.comboBoxArrowRect(comboBox.bounds)
      arrowFrame = context.renderRectFor(arrowRect)
      arrowChrome =
        chromeContext(style.chrome, crComboBox, cpArrow, style.arrowFill, styleStates)
      separatorRect = rect(
        arrowRect.origin.x,
        arrowRect.origin.y + 2.0'f32,
        1.0'f32,
        max(arrowRect.size.height - 4.0'f32, 0.0'f32),
      )
      separatorChrome = chromeContext(
        style.chrome, crComboBox, cpSeparator, fill(style.box.borderColor), styleStates
      )
    let arrowRoot = context.addRenderRectangle(
      comboRoot,
      arrowFrame,
      context.appearance.chromeFill(arrowChrome),
      color(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
    )
    context.drawChromeExtras(
      arrowChrome, initChromeExtras(arrowRoot, arrowFrame, cornerRadius = 0.0'f32)
    )
    discard context.addRenderRectangle(
      comboRoot,
      context.renderRectFor(separatorRect),
      context.appearance.chromeFill(separatorChrome),
    )
    context.addComboBoxArrow(arrowRoot, arrowFrame, style.arrowColor)
    context.addText(
      style.comboBoxTextRect(comboBox.bounds), comboBox.stringValue, style.text
    )

    if comboBox.usesInlinePopup:
      comboBox.popupList().drawPopupList(
        context, comboBox.popupRect(comboBox.bounds), PopupDrawLevel
      )

protocol DefaultComboBoxEvents of ResponderEventProtocol:
  method mouseDown(comboBox: ComboBox, event: MouseEvent): bool =
    if not comboBox.isEnabled or event.button != mbPrimary:
      return false
    if comboBox.popupOpen() and
        comboBox.popupRect(comboBox.bounds()).contains(event.location):
      comboBox.popupList().beginPopupListTracking(
        comboBox.popupRect(comboBox.bounds()), event.location
      )
    else:
      comboBox.popupList().resetPopupListTracking()
      comboBox.setWidgetState(ssPressed, true)
      comboBox.togglePopup()
      comboBox.setNeedsDisplay(true)
    true

  method mouseDragged(comboBox: ComboBox, event: MouseEvent): bool =
    if comboBox.popupOpen():
      comboBox.popupList().trackPopupListPoint(
        comboBox.popupRect(comboBox.bounds()), event.location
      )
      return true
    false

  method mouseMoved(comboBox: ComboBox, event: MouseEvent): bool =
    if comboBox.popupOpen():
      comboBox.popupList().trackPopupListPoint(
        comboBox.popupRect(comboBox.bounds()), event.location
      )
      return true
    false

  method mouseUp(comboBox: ComboBox, event: MouseEvent): bool =
    if not comboBox.isEnabled or event.button != mbPrimary:
      return false
    comboBox.setWidgetState(ssPressed, false)
    if comboBox.popupOpen() and
        comboBox.popupRect(comboBox.bounds()).contains(event.location):
      comboBox.popupList().finishPopupListTracking(
        comboBox.popupRect(comboBox.bounds()), event.location, closeWhenDone = false
      )
    comboBox.setNeedsDisplay(true)
    true

  method wantsForwardedScrollEvents(comboBox: ComboBox, event: ScrollEvent): bool =
    not comboBox.popupOpen() or
      not comboBox.canScrollPopupRows(popupListScrollRows(event))

  method scrollWheel(comboBox: ComboBox, event: ScrollEvent): bool =
    let delta = popupListScrollRows(event)
    if comboBox.popupOpen() and comboBox.canScrollPopupRows(delta):
      comboBox.scrollPopupRows(delta)
      return true

  method keyDown(comboBox: ComboBox, event: KeyEvent): bool =
    if not comboBox.isEnabled:
      return false
    result = true
    case event.key
    of keyArrowDown:
      if not comboBox.popupOpen():
        comboBox.openPopup()
      else:
        comboBox.movePopupHighlight(1)
    of keyArrowUp:
      if not comboBox.popupOpen():
        comboBox.openPopup()
      else:
        comboBox.movePopupHighlight(-1)
    of keyPageDown:
      if comboBox.popupOpen():
        comboBox.pagePopupHighlight(1)
    of keyPageUp:
      if comboBox.popupOpen():
        comboBox.pagePopupHighlight(-1)
    of keyHome:
      if comboBox.popupOpen():
        let first = comboBox.firstSelectableOptionIndex()
        if first >= 0:
          comboBox.highlightedIndex = first
    of keyEnd:
      if comboBox.popupOpen():
        let last = comboBox.nextSelectableOptionIndex(comboBox.numberOfItems() - 1, -1)
        if last >= 0:
          comboBox.highlightedIndex = last
    of keyEnter:
      if comboBox.popupOpen() and comboBox.highlightedIndex() >= 0:
        comboBox.activateItemAtIndex(comboBox.highlightedIndex())
        comboBox.closePopup()
      elif comboBox.indexOfSelectedItem() >= 0:
        discard comboBox.sendAction()
    of keyEscape:
      comboBox.closePopup()
    else:
      if comboBox.isEditable and event.text.len > 0:
        comboBox.setStringValue(event.text)
      elif event.text.len > 0:
        let start =
          if comboBox.highlightedIndex() >= 0:
            comboBox.highlightedIndex() + 1
          else:
            0
        let matchIndex = comboBox.indexOfOptionMatchingText(event.text, start)
        if matchIndex >= 0:
          if comboBox.popupOpen():
            comboBox.highlightedIndex = matchIndex
          else:
            comboBox.selectItemAtIndex(matchIndex)
        else:
          result = false
      else:
        result = false

proc cellStringValue(cell: ComboBoxCell): string =
  cell.xStringValue

proc setCellSelectedIndex(cell: ComboBoxCell, index: int) =
  if index < 0:
    if cell.xSelectedIndex < 0 and cell.xStringValue.len == 0 and
        cell.xSelectedIdentifier.len == 0:
      return
    cell.xSelectedIndex = -1
    cell.xSelectedIdentifier = ""
    cell.xStringValue = ""
    cell.invalidateControlMetrics()
    return
  let option = cell.cellOptionAtIndex(index)
  if option.displayText.len == 0 and option.objectValue.isNilOrEmpty():
    return
  cell.xSelectedIndex = index
  cell.xSelectedIdentifier = option.identifier
  cell.xStringValue = option.optionDisplayText()
  cell.invalidateControlMetrics()

proc cellMaxVisibleItems(cell: ComboBoxCell): int =
  cell.xMaxVisibleItems

proc setCellMaxVisibleItems(cell: ComboBoxCell, value: int) =
  let count = max(value, 1)
  if cell.xMaxVisibleItems == count:
    return
  cell.xMaxVisibleItems = count
  cell.invalidateControlMetrics()

proc cellItemHeight(cell: ComboBoxCell): float32 =
  cell.xItemHeight

proc setCellItemHeight(cell: ComboBoxCell, value: float32) =
  let height = max(value, 1.0'f32)
  if cell.xItemHeight == height:
    return
  cell.xItemHeight = height
  cell.invalidateControlMetrics()

proc cellIsEditable(cell: ComboBoxCell): bool =
  cell.xEditable

proc setCellEditable(cell: ComboBoxCell, editable: bool) =
  if cell.xEditable == editable:
    return
  cell.xEditable = editable
  cell.invalidateControlMetrics()

proc cellNumberOfItems(cell: ComboBoxCell): int =
  cell.xIndexCache.visibleOptionCount(cell.xOptions, cell.xFilterText)

proc cellItemAtIndex(cell: ComboBoxCell, index: int): string =
  cell.cellOptionAtIndex(index).optionDisplayText()

proc cellOptionAtIndex(cell: ComboBoxCell, index: int): ComboBoxOption =
  result = cell.xIndexCache.optionAtVisibleIndex(cell.xOptions, index, cell.xFilterText)

proc cellIndexOfOptionIdentifier(cell: ComboBoxCell, identifier: string): int =
  cell.xIndexCache.indexOfVisibleOptionIdentifier(
    cell.xOptions, identifier, cell.xFilterText
  )

proc cellInsertOption(cell: ComboBoxCell, option: ComboBoxOption, index: int) =
  let oldSelectedIdentifier = cell.xSelectedIdentifier
  let oldSelectedIndex = cell.xSelectedIndex
  let boundedIndex =
    cell.xIndexCache.visibleOptionInsertionIndex(cell.xOptions, index, cell.xFilterText)
  cell.xOptions.insert(option, boundedIndex)
  cell.xIndexCache.invalidateOptionIndex()
  if oldSelectedIdentifier.len > 0:
    cell.xSelectedIndex = cell.cellIndexOfOptionIdentifier(oldSelectedIdentifier)
  elif oldSelectedIndex >= max(index, 0):
    cell.xSelectedIndex = oldSelectedIndex + 1
  cell.invalidateControlMetrics()

proc cellRemoveItemAtIndex(cell: ComboBoxCell, index: int) =
  if index < 0 or index >= cell.cellNumberOfItems():
    return
  let storageIndex =
    cell.xIndexCache.visibleOptionStorageIndex(cell.xOptions, index, cell.xFilterText)
  if storageIndex < 0:
    return
  let removedIdentifier = cell.xOptions[storageIndex].identifier
  cell.xOptions.delete(storageIndex)
  cell.xIndexCache.invalidateOptionIndex()
  if cell.cellNumberOfItems() == 0:
    cell.xSelectedIndex = -1
    cell.xSelectedIdentifier = ""
    cell.xStringValue = ""
  elif removedIdentifier.len > 0 and removedIdentifier == cell.xSelectedIdentifier:
    cell.setCellSelectedIndex(min(index, cell.cellNumberOfItems() - 1))
  elif cell.xSelectedIdentifier.len > 0:
    cell.xSelectedIndex = cell.cellIndexOfOptionIdentifier(cell.xSelectedIdentifier)
  elif cell.xSelectedIndex == index:
    cell.setCellSelectedIndex(min(index, cell.cellNumberOfItems() - 1))
  elif index < cell.xSelectedIndex:
    dec cell.xSelectedIndex
  cell.invalidateControlMetrics()

proc cellRemoveAllItems(cell: ComboBoxCell) =
  cell.xOptions.setLen(0)
  cell.xStringValue = ""
  cell.xSelectedIndex = -1
  cell.xSelectedIdentifier = ""
  cell.xIndexCache.invalidateOptionIndex()
  cell.invalidateControlMetrics()

proc comboBoxStyleContext(comboBox: ComboBox): StyleContext =
  controlStyle(
    srComboBox,
    comboBox.widgetStateSet(),
    id = comboBox.styleId,
    classes = comboBox.styleClasses,
  )

proc comboBoxMeasuredTextSize(cell: ComboBoxCell, style: TextStyle): Size =
  let view = cell.controlView()
  if view of ComboBox:
    let comboBox = ComboBox(view)
    result = textNaturalSize(comboBox.stringValue(), style)
    for idx in 0 ..< comboBox.numberOfItems():
      let itemSize = textNaturalSize(comboBox.itemAtIndex(idx), style)
      result.width = max(result.width, itemSize.width)
      result.height = max(result.height, itemSize.height)
    return

  result = textNaturalSize(cell.cellStringValue(), style)
  for idx in 0 ..< cell.cellNumberOfItems():
    let item = cell.cellItemAtIndex(idx)
    let itemSize = textNaturalSize(item, style)
    result.width = max(result.width, itemSize.width)
    result.height = max(result.height, itemSize.height)

protocol DefaultComboBoxCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: ComboBoxCell): IntrinsicSize =
    let
      view = cell.controlView()
      appearance =
        if view.isNil:
          initAppearance()
        else:
          view.effectiveAppearance()
      context =
        if view of ComboBox:
          ComboBox(view).comboBoxStyleContext()
        else:
          controlStyle(srComboBox)
      style = appearance.resolveComboBoxStyle(context)
    initIntrinsicSize(
      style.comboBoxControlSize(cell.comboBoxMeasuredTextSize(style.text))
    )

  method cellSizeForBounds(cell: ComboBoxCell, bounds: Rect): Size =
    cell.cellSize().resolveIntrinsicSize(bounds.size)

proc setComboBoxStringValue(comboBox: ComboBox, value: string) =
  let
    cell = comboBox.comboBoxCell()
    index = comboBox.indexOfItem(value)
  if cell.xStringValue == value and cell.xSelectedIndex == index and
      cell.xSelectedIdentifier.len == 0:
    return
  let oldValue = cell.xStringValue
  comboBox.findUndoManager().registerValueChange(
    proc(value: string) =
      comboBox.setComboBoxStringValue(value),
    oldValue,
    "Change Choice",
  )
  cell.xStringValue = value
  cell.xSelectedIndex = index
  cell.xSelectedIdentifier = ""
  Control(comboBox).setObjectValue(toObj(value))
  cell.invalidateControlMetrics()

proc comboBoxStringValueMethod(self: DynamicAgent, invocation: var Invocation) =
  invocation.setResult(ComboBox(self).comboBoxCell().cellStringValue())

proc comboBoxSetStringValueMethod(self: DynamicAgent, invocation: var Invocation) =
  ComboBox(self).setComboBoxStringValue(invocation.argsAs(string))
  invocation.setResult(())

proc comboBoxIsEditableMethod(self: DynamicAgent, invocation: var Invocation) =
  invocation.setResult(ComboBox(self).comboBoxCell().cellIsEditable())

proc comboBoxSetEditableMethod(self: DynamicAgent, invocation: var Invocation) =
  ComboBox(self).comboBoxCell().setCellEditable(invocation.argsAs(bool))
  invocation.setResult(())

proc installComboBoxTextSelectors(comboBox: ComboBox) =
  discard
    comboBox.replaceMethod(stringValue(), DynamicMethod(comboBoxStringValueMethod))
  discard comboBox.replaceMethod(
    setStringValue(), DynamicMethod(comboBoxSetStringValueMethod)
  )
  discard comboBox.replaceMethod(isEditable(), DynamicMethod(comboBoxIsEditableMethod))
  discard
    comboBox.replaceMethod(setEditable(), DynamicMethod(comboBoxSetEditableMethod))

proc initComboBoxCellFields*(cell: ComboBoxCell) =
  initActionCellFields(cell)
  cell.xSelectedIndex = -1
  cell.xEditable = true
  cell.xMaxVisibleItems = 5
  cell.xItemHeight = 22.0
  discard cell.withProtocol(DefaultComboBoxCellMeasurement)

proc newComboBoxCell*(): ComboBoxCell =
  result = ComboBoxCell()
  initComboBoxCellFields(result)

proc comboBoxCell*(comboBox: ComboBox): ComboBoxCell =
  let controlCell = comboBox.cell()
  if controlCell of ComboBoxCell:
    return ComboBoxCell(controlCell)
  let replacement = newComboBoxCell()
  comboBox.setCell(replacement)
  replacement

proc text*(comboBox: ComboBox): string =
  comboBox.stringValue()

proc `text=`*(comboBox: ComboBox, value: string) =
  comboBox.setStringValue(value)

proc `stringValue=`*(comboBox: ComboBox, value: string) =
  comboBox.setStringValue(value)

proc editable*(comboBox: ComboBox): bool =
  comboBox.isEditable()

proc `editable=`*(comboBox: ComboBox, editable: bool) =
  comboBox.setEditable(editable)

proc `selectedIndex=`*(comboBox: ComboBox, index: int) =
  comboBox.setSelectedIndex(index)

proc `popupOpen=`*(comboBox: ComboBox, open: bool) =
  comboBox.setPopupOpen(open)

proc `maxVisibleItems=`*(comboBox: ComboBox, value: int) =
  comboBox.setMaxVisibleItems(value)

proc `itemHeight=`*(comboBox: ComboBox, value: float32) =
  comboBox.setItemHeight(value)

proc `popupPresentation=`*(comboBox: ComboBox, popupPresentation: PopupPresentation) =
  comboBox.setPopupPresentation(popupPresentation)

proc dataSource*(comboBox: ComboBox): DynamicAgent =
  comboBox.xDataSource

proc `dataSource=`*(comboBox: ComboBox, dataSource: DynamicAgent) =
  if comboBox.xDataSource == dataSource:
    return
  comboBox.xDataSource = dataSource
  if not dataSource.isNil and comboBox.xOptionFilterText.len > 0:
    discard dataSource.trySendLocal(
      setComboBoxOptionFilterText(),
      (comboBox: comboBox, text: comboBox.xOptionFilterText),
    )
  comboBox.reloadData()

proc `dataSource=`*(comboBox: ComboBox, dataSource: Responder) =
  comboBox.dataSource = DynamicAgent(dataSource)

proc insertStoredItem(
    comboBox: ComboBox, title: string, objectValue: ObjectValue, index: int
) =
  comboBox.insertStoredOption(
    initComboBoxOption(displayText = title, objectValue = objectValue), index
  )

proc insertStoredOption(comboBox: ComboBox, option: ComboBoxOption, index: int) =
  let boundedIndex = max(0, min(index, comboBox.comboBoxCell().cellNumberOfItems()))
  comboBox.findUndoManager().registerCollectionInsert(
    proc(index: int) =
      comboBox.removeItemAtIndex(index),
    boundedIndex,
    "Insert Choice",
  )
  comboBox.comboBoxCell().cellInsertOption(option, boundedIndex)

proc itemObjectValueAtIndex*(comboBox: ComboBox, index: int): ObjectValue =
  comboBox.optionObjectValueAtIndex(index)

proc highlightedIndex*(comboBox: ComboBox): int =
  if comboBox.xPopupHighlightedIdentifier.len > 0:
    let index = comboBox.indexOfOptionIdentifier(comboBox.xPopupHighlightedIdentifier)
    if index >= 0:
      comboBox.xPopupHighlightedIndex = index
      return index
    comboBox.xPopupHighlightedIndex = -1
    return -1
  comboBox.xPopupHighlightedIndex

proc highlightedOptionIdentifier*(comboBox: ComboBox): string =
  if comboBox.xPopupHighlightedIdentifier.len > 0:
    comboBox.xPopupHighlightedIdentifier
  elif comboBox.xPopupHighlightedIndex >= 0:
    comboBox.optionIdentifierAtIndex(comboBox.xPopupHighlightedIndex)
  else:
    ""

proc setPopupNeedsDisplay(comboBox: ComboBox) =
  comboBox.setNeedsDisplay(true)
  if not comboBox.xPopupWindow.isNil:
    let contentView = comboBox.xPopupWindow.contentView()
    if not contentView.isNil:
      contentView.setNeedsDisplay(true)

proc `highlightedIndex=`*(comboBox: ComboBox, index: int) =
  let boundedIndex = if index < 0 or index >= comboBox.numberOfItems(): -1 else: index
  let oldFirst = comboBox.popupFirstItemIndex()
  comboBox.scrollPopupItemToVisible(boundedIndex)
  let firstChanged = comboBox.popupFirstItemIndex() != oldFirst
  if comboBox.xPopupHighlightedIndex == boundedIndex:
    if firstChanged:
      comboBox.setPopupNeedsDisplay()
    return
  comboBox.xPopupHighlightedIndex = boundedIndex
  comboBox.xPopupHighlightedIdentifier =
    if boundedIndex >= 0:
      comboBox.optionIdentifierAtIndex(boundedIndex)
    else:
      ""
  emit comboBox.selectionIsChanging(DynamicAgent(comboBox))
  comboBox.setPopupNeedsDisplay()

proc `selectedOptionIdentifier=`*(comboBox: ComboBox, identifier: string) =
  comboBox.selectOptionWithIdentifier(identifier)

proc `optionFilterText=`*(comboBox: ComboBox, text: string) =
  comboBox.setOptionFilterText(text)

proc indexOfOptionMatchingText*(comboBox: ComboBox, text: string, startIndex = 0): int =
  if text.normalizedSearchText().len == 0:
    return -1
  let count = comboBox.numberOfItems()
  if count == 0:
    return -1
  let first = max(0, min(startIndex, count - 1))
  for offset in 0 ..< count:
    let index = (first + offset) mod count
    let option = comboBox.optionAtIndex(index)
    if option.optionIsSelectable() and option.optionMatchesFilter(text):
      return index
  -1

proc popupListData(comboBox: ComboBox): PopupListData =
  PopupListData(
    itemCount: proc(): int =
      comboBox.numberOfItems(),
    visibleCount: proc(): int =
      comboBox.visibleItemCount(),
    firstIndex: proc(): int =
      comboBox.popupFirstItemIndex(),
    selectedIndex: proc(): int =
      comboBox.indexOfSelectedItem(),
    highlightedIndex: proc(): int =
      comboBox.highlightedIndex(),
    rowHeight: proc(): float32 =
      comboBox.popupItemHeight(),
    itemText: proc(index: int): string =
      comboBox.itemAtIndex(index),
    itemIsSeparator: proc(index: int): bool =
      comboBox.optionIsSeparatorAtIndex(index),
    itemIsEnabled: proc(index: int): bool =
      comboBox.optionIsEnabledAtIndex(index),
    enabled: proc(): bool =
      comboBox.isEnabled(),
    focused: proc(): bool =
      comboBox.isFocused(),
    opened: proc(): bool =
      comboBox.popupOpen(),
    styleId: proc(): string =
      comboBox.styleId(),
    styleClasses: proc(): seq[string] =
      comboBox.styleClasses(),
  )

proc popupListActions(comboBox: ComboBox): PopupListActions =
  PopupListActions(
    highlight: proc(index: int) =
      comboBox.setHoveredPopupIndex(index),
    activate: proc(index: int) =
      comboBox.activateItemAtIndex(index)
      comboBox.closePopup(),
    close: proc() =
      comboBox.closePopup(),
    scroll: proc(delta: int) =
      comboBox.scrollPopupRows(delta),
    keyDown: proc(event: KeyEvent) =
      discard comboBox.keyDown(event),
  )

proc popupList(comboBox: ComboBox): PopupListView =
  if comboBox.xPopupList.isNil:
    comboBox.xPopupList =
      newPopupListView(comboBox.popupListData(), comboBox.popupListActions())
  comboBox.xPopupList

proc setHoveredPopupIndex(comboBox: ComboBox, index: int) =
  if index < 0:
    return
  if comboBox.optionAtIndex(index).optionIsSelectable():
    comboBox.highlightedIndex = index

proc isButtonPressed*(comboBox: ComboBox): bool =
  ssPressed in comboBox.widgetStateSet()

proc visibleItemCount*(comboBox: ComboBox): int =
  visibleRowItemCount(comboBox.numberOfItems(), comboBox.maxVisibleItems())

proc popupItemHeight*(comboBox: ComboBox): float32 =
  max(comboBox.itemHeight(), 18.0'f32).normalizedRowHeight()

proc popupFirstItemIndex*(comboBox: ComboBox): int =
  let
    total = comboBox.numberOfItems()
    visible = comboBox.visibleItemCount()
  comboBox.xPopupViewport.firstIndex.clampFirstIndex(total, visible)

proc scrollPopupItemToVisible(comboBox: ComboBox, itemIndex: int) =
  comboBox.xPopupViewport.scrollToVisible(
    itemIndex, comboBox.numberOfItems(), comboBox.visibleItemCount()
  )

proc scrollPopupRows(comboBox: ComboBox, delta: int) =
  if delta == 0:
    return
  let oldFirst = comboBox.popupFirstItemIndex()
  comboBox.xPopupViewport.scrollBy(
    delta, comboBox.numberOfItems(), comboBox.visibleItemCount()
  )
  if comboBox.popupFirstItemIndex() != oldFirst:
    comboBox.setPopupNeedsDisplay()

proc canScrollPopupRows(comboBox: ComboBox, delta: int): bool =
  comboBox.xPopupViewport.canScrollBy(
    delta, comboBox.numberOfItems(), comboBox.visibleItemCount()
  )

proc popupRect*(comboBox: ComboBox, bounds: Rect): Rect =
  rowPopupRect(
    bounds,
    comboBox.numberOfItems(),
    comboBox.maxVisibleItems(),
    comboBox.popupItemHeight(),
  )

proc popupItemRect*(comboBox: ComboBox, bounds: Rect, itemIndex: int): Rect =
  let
    first = comboBox.popupFirstItemIndex()
    visible = comboBox.visibleItemCount()
    popup = comboBox.popupRect(bounds)
  rowItemRect(popup, first, visible, itemIndex, comboBox.popupItemHeight())

proc popupItemIndexAtPoint*(comboBox: ComboBox, bounds: Rect, point: Point): int =
  let
    popup = comboBox.popupRect(bounds)
    first = comboBox.popupFirstItemIndex()
  rowItemIndexAtPoint(
    popup,
    point,
    first,
    comboBox.visibleItemCount(),
    comboBox.numberOfItems(),
    comboBox.popupItemHeight(),
  )

proc popupScrollerKnobRect*(comboBox: ComboBox, bounds: Rect): Rect =
  rowScrollerKnobRect(
    comboBox.popupRect(bounds),
    comboBox.popupFirstItemIndex(),
    comboBox.visibleItemCount(),
    comboBox.numberOfItems(),
  )

proc popupWindowSize(comboBox: ComboBox): Size =
  let popup = comboBox.popupRect(comboBox.bounds)
  initSize(max(popup.size.width, 1.0'f32), max(popup.size.height, 1.0'f32))

proc ownerWindow(comboBox: ComboBox): Window =
  let owner = comboBox.window()
  if owner of Window:
    result = Window(owner)

proc dismissPopupFromSession(comboBox: ComboBox, reason: DismissReason) =
  case reason
  of tdrProgrammatic, tdrOutsideClick, tdrEscape, tdrFocusChange, tdrOwnerClosed,
      tdrNativeDone:
    if comboBox.popupOpen():
      comboBox.closePopup()

proc beginPopupSession(comboBox: ComboBox) =
  let owner = comboBox.ownerWindow()
  if owner.isNil:
    return
  let popupWindow = if comboBox.popupWindowActive(): comboBox.xPopupWindow else: nil
  owner.beginTransientSession(
    owner = Responder(comboBox),
    transientWindow = popupWindow,
    restoreResponder = Responder(comboBox),
    onDismiss = proc(reason: DismissReason) =
      comboBox.dismissPopupFromSession(reason),
  )

proc endPopupSession(comboBox: ComboBox, reason = tdrProgrammatic): bool =
  let owner = comboBox.ownerWindow()
  if owner.isNil:
    return false
  owner.endTransientSession(reason)

proc popupWindowActive(comboBox: ComboBox): bool =
  not comboBox.xPopupWindow.isNil and not comboBox.xPopupWindow.isClosed and
    comboBox.xPopupWindow.nativeReady

proc popupPresentationPreference(comboBox: ComboBox): PopupPresentation =
  if comboBox.xPopupPresentation == ppAutomatic:
    let owner = comboBox.ownerWindow()
    if owner.isNil:
      return platformDefaultPopupPresentation()
    return owner.effectivePopupPresentation()
  comboBox.xPopupPresentation

proc canUseWindowPopup(comboBox: ComboBox): bool =
  if not nativePopupWindowsSupported():
    return false
  let owner = comboBox.ownerWindow()
  not owner.isNil and owner.nativeReady

proc wantsWindowPopup(comboBox: ComboBox): bool =
  case comboBox.popupPresentationPreference()
  of ppAutomatic:
    nativePopupWindowsSupported()
  of ppWindow:
    true
  of ppInline:
    false

proc shouldUseWindowPopup(comboBox: ComboBox): bool =
  comboBox.wantsWindowPopup() and comboBox.canUseWindowPopup()

proc usesInlinePopup(comboBox: ComboBox): bool =
  if not comboBox.popupOpen():
    return false
  case comboBox.popupPresentationPreference()
  of ppInline:
    true
  of ppAutomatic:
    not comboBox.shouldUseWindowPopup()
  of ppWindow:
    false

proc openPopupWindow(comboBox: ComboBox) =
  if not comboBox.popupOpen():
    return
  if comboBox.popupWindowActive():
    return
  if not comboBox.shouldUseWindowPopup():
    return
  if not comboBox.xPopupWindow.isNil:
    discard comboBox.endPopupSession()
    comboBox.closePopupWindow(restoreOwner = false)
  let owner = comboBox.ownerWindow()
  if owner.isNil or not owner.nativeReady:
    return

  let
    anchorFrame = comboBox.rectToWindow(comboBox.bounds)
    size = comboBox.popupWindowSize()
    popupWindow = owner.newPopupWindow(anchorFrame, size, "ComboBox Popup")
    popupView = comboBox.popupList()

  popupView.setFrame(rect(0.0, 0.0, size.width, size.height))
  popupWindow.setContentView(popupView)
  popupWindow.setPopupDoneHandler(
    proc() =
      if owner.hasActiveTransientSession():
        discard owner.dismissTransientSession(tdrNativeDone)
      elif comboBox.xPopupWindow == popupWindow:
        comboBox.closePopup()
  )
  comboBox.xPopupWindow = popupWindow
  popupWindow.makeKeyAndOrderFront()
  popupWindow.ensureNativeWindow()
  if popupWindow.nativeReady:
    discard popupWindow.makeFirstResponder(popupView)
  else:
    comboBox.xPopupWindow = nil
    popupWindow.close()

proc closePopupWindow(comboBox: ComboBox, restoreOwner = true) =
  let popupWindow = comboBox.xPopupWindow
  comboBox.xPopupWindow = nil
  if not popupWindow.isNil and not popupWindow.isClosed:
    popupWindow.close()
  if restoreOwner and not popupWindow.isNil:
    comboBox.reactivateOwnerWindow()

proc reactivateOwnerWindow(comboBox: ComboBox) =
  let owner = comboBox.ownerWindow()
  if owner.isNil or owner.isClosed:
    return
  if owner.isVisible:
    owner.makeKeyAndOrderFront()
  discard owner.makeFirstResponder(comboBox)

proc updatePopupPresentation(comboBox: ComboBox) =
  if not comboBox.popupOpen():
    comboBox.closePopupWindow()
    return
  if comboBox.shouldUseWindowPopup():
    comboBox.openPopupWindow()
  elif not comboBox.xPopupWindow.isNil:
    discard comboBox.endPopupSession()
    comboBox.closePopupWindow(restoreOwner = false)
  if comboBox.popupOpen():
    comboBox.beginPopupSession()

proc nextSelectableOptionIndex(comboBox: ComboBox, start, delta: int): int =
  if delta == 0:
    return -1
  let count = comboBox.numberOfItems()
  if count == 0:
    return -1
  var index = max(0, min(start, count - 1))
  while index >= 0 and index < count:
    if comboBox.optionAtIndex(index).optionIsSelectable():
      return index
    index += delta
  -1

proc firstSelectableOptionIndex(comboBox: ComboBox): int =
  comboBox.nextSelectableOptionIndex(0, 1)

proc movePopupHighlight*(comboBox: ComboBox, delta: int) =
  if comboBox.numberOfItems() == 0:
    return
  let current =
    if comboBox.highlightedIndex() >= 0:
      comboBox.highlightedIndex()
    elif comboBox.indexOfSelectedItem() >= 0:
      comboBox.indexOfSelectedItem()
    else:
      0
  let direction = if delta < 0: -1 else: 1
  let next = comboBox.nextSelectableOptionIndex(current + delta, direction)
  if next >= 0:
    comboBox.highlightedIndex = next

proc movePopupHighlightTo(comboBox: ComboBox, index: int) =
  if comboBox.numberOfItems() == 0:
    return
  let bounded = max(0, min(index, comboBox.numberOfItems() - 1))
  let direction = if bounded < comboBox.highlightedIndex(): -1 else: 1
  let next = comboBox.nextSelectableOptionIndex(bounded, direction)
  if next >= 0:
    comboBox.highlightedIndex = next

proc pagePopupHighlight(comboBox: ComboBox, deltaPages: int) =
  if comboBox.numberOfItems() == 0 or deltaPages == 0:
    return

  let
    total = comboBox.numberOfItems()
    visible = comboBox.visibleItemCount()
    current =
      if comboBox.highlightedIndex() >= 0:
        comboBox.highlightedIndex()
      elif comboBox.indexOfSelectedItem() >= 0:
        comboBox.indexOfSelectedItem()
      else:
        0
  if visible <= 0:
    comboBox.movePopupHighlightTo(current)
    return

  let target = max(0, min(current + deltaPages * visible, total - 1))
  comboBox.xPopupViewport.firstIndex = clampFirstIndex(target, total, visible)
  comboBox.movePopupHighlightTo(target)

proc replaceStoredOptions(comboBox: ComboBox, options: openArray[ComboBoxOption]) =
  let
    cell = comboBox.comboBoxCell()
    oldSelectedIdentifier = cell.xSelectedIdentifier
    oldStringValue = cell.xStringValue
    oldHighlightedIdentifier = comboBox.xPopupHighlightedIdentifier

  cell.xOptions = @options
  cell.xIndexCache.invalidateOptionIndex()
  cell.xSelectedIndex = -1

  if oldSelectedIdentifier.len > 0:
    cell.xSelectedIndex = cell.cellIndexOfOptionIdentifier(oldSelectedIdentifier)
    if cell.xSelectedIndex >= 0:
      let option = cell.cellOptionAtIndex(cell.xSelectedIndex)
      cell.xStringValue = option.optionDisplayText()
      Control(comboBox).setObjectValue(option.resolvedObjectValue())
    else:
      cell.xSelectedIdentifier = ""
      cell.xStringValue = ""
      Control(comboBox).setObjectValue(emptyObjectValue())
  elif oldStringValue.len > 0:
    for index in 0 ..< cell.cellNumberOfItems():
      if cell.cellItemAtIndex(index) == oldStringValue:
        cell.xSelectedIndex = index
        break
    Control(comboBox).setObjectValue(toObj(oldStringValue))
  else:
    Control(comboBox).setObjectValue(emptyObjectValue())

  comboBox.xPopupHighlightedIndex =
    cell.cellIndexOfOptionIdentifier(oldHighlightedIdentifier)
  if comboBox.xPopupHighlightedIndex < 0:
    comboBox.xPopupHighlightedIdentifier = ""
  comboBox.xPopupViewport.reset()
  if cell.cellNumberOfItems() == 0:
    comboBox.closePopup()
  cell.invalidateControlMetrics()

proc setOptions*(comboBox: ComboBox, options: openArray[ComboBoxOption]) =
  comboBox.replaceStoredOptions(options)

proc setItems*(comboBox: ComboBox, values: openArray[string]) =
  var options = newSeqOfCap[ComboBoxOption](values.len)
  for value in values:
    options.add initComboBoxOption(displayText = value, objectValue = toObj(value))
  comboBox.replaceStoredOptions(options)

proc setItems*(comboBox: ComboBox, values: openArray[ObjectValue]) =
  var options = newSeqOfCap[ComboBoxOption](values.len)
  for value in values:
    options.add initComboBoxOption(
      displayText = Control(comboBox).formatObjectValue(value, ovrComboBox),
      objectValue = value,
    )
  comboBox.replaceStoredOptions(options)

proc addItems*(comboBox: ComboBox, values: openArray[string]) =
  for value in values:
    comboBox.addItem(value)

proc addItem*(comboBox: ComboBox, value: ObjectValue) =
  comboBox.insertStoredItem(
    Control(comboBox).formatObjectValue(value, ovrComboBox),
    value,
    comboBox.comboBoxCell().cellNumberOfItems(),
  )

proc insertItem*(comboBox: ComboBox, value: ObjectValue, index: int) =
  comboBox.insertStoredItem(
    Control(comboBox).formatObjectValue(value, ovrComboBox), value, index
  )

proc addItems*(comboBox: ComboBox, values: openArray[ObjectValue]) =
  for value in values:
    comboBox.addItem(value)

proc initComboBoxFields*(
    comboBox: ComboBox, items: openArray[string] = [], frame: Rect = AutoRect
) =
  initControlFields(comboBox, frame, newComboBoxCell())
  comboBox.xPopupHighlightedIndex = -1
  comboBox.setAcceptsFirstResponder(true)
  discard comboBox.withProto()
  comboBox.installComboBoxTextSelectors()
  discard comboBox.withProtocol(DefaultComboBoxView)
  discard comboBox.withProtocol(DefaultComboBoxAction)
  discard comboBox.withProtocol(DefaultComboBoxDrawing)
  discard comboBox.withProtocol(DefaultComboBoxEvents)
  discard comboBox.withProtocol(DefaultComboBoxAccessibility)
  comboBox.setItems(items)
  comboBox.applyInitialFrame(frame)

proc newComboBox*(items: openArray[string] = [], frame: Rect = AutoRect): ComboBox =
  result = ComboBox()
  initComboBoxFields(result, items, frame)
