import std/[strutils, tables, unicode]

import sigils/core
import sigils/selectors as dynamicSelectors

import ../accessibility/accessibility
import ../containers/scrollviews
import ../containers/stackviews
import ../drawing
import ../foundation/events
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types

import ./chips
import ./comboboxes

export chips
export comboboxes

type
  TokenFieldSelectionHandler* = proc(option: ComboBoxOption) {.closure.}
  TokenFieldRemovalHandler* = proc(option: ComboBoxOption) {.closure.}
  TokenFieldChangeHandler* = proc(field: TokenField) {.closure.}

  TokenField* = ref object of Control
    xOptions: ComboBoxOptionList
    xSelectedOptions: seq[ComboBoxOption]
    xSelectedIdentifiers: seq[string]
    xOriginalEnabled: Table[string, bool]
    xInput: ComboBox
    xChipScroll: ScrollView
    xChipRow: StackView
    xChips: seq[Chip]
    xQuery: string
    xPlaceholder: string
    xAllowDuplicates: bool
    xRemovesLastTokenOnBackspace: bool
    xInputStyleId: string
    xInputStyleClasses: seq[string]
    xChipStyleClasses: seq[string]
    xOnSelect: TokenFieldSelectionHandler
    xOnRemove: TokenFieldRemovalHandler
    xOnChange: TokenFieldChangeHandler

  MultiSelectComboBox* = TokenField

const
  TokenFieldDefaultWidth* = 280.0'f32
  TokenFieldDefaultHeight* = 30.0'f32
  TokenFieldMinimumQueryWidth = 96.0'f32
  TokenFieldChipSpacing = 6.0'f32

proc rebuildChips(field: TokenField)
proc setTokenQuery(field: TokenField, value: string, openPopup = true)
proc clearTokenQuery(field: TokenField)
proc selectInputOption(field: TokenField)
proc updateEnabledOptions(field: TokenField)
proc setTokenFieldEnabled(field: TokenField, value: bool)
proc removeSelectedOptionAtIndex(field: TokenField, index: int, notify: bool): bool
proc removeSelectedOptionWithIdentifier*(field: TokenField, identifier: string): bool

proc tokenOptionDisplayText(option: ComboBoxOption): string =
  if option.displayText.len > 0:
    return option.displayText
  option.objectValue.formatObjectValue(initObjectFormatContext(role = ovrComboBox))

proc tokenOptionKey(option: ComboBoxOption): string =
  if option.identifier.len > 0:
    option.identifier
  else:
    option.tokenOptionDisplayText()

proc tokenOptionSelectable(option: ComboBoxOption): bool =
  option.enabled and not option.hidden and not option.separator and
    option.tokenOptionKey().len > 0

proc selectedIndexForKey(field: TokenField, key: string): int =
  for index, selected in field.xSelectedIdentifiers:
    if selected == key:
      return index
  -1

proc storageIndexForKey(field: TokenField, key: string): int =
  if key.len == 0:
    return -1
  for index, option in field.xOptions.options:
    if option.tokenOptionKey() == key:
      return index
  -1

proc selectedOptions*(field: TokenField): seq[ComboBoxOption] =
  field.xSelectedOptions

proc selectedOptionIdentifiers*(field: TokenField): seq[string] =
  field.xSelectedIdentifiers

proc selectedCount*(field: TokenField): int =
  field.xSelectedOptions.len

proc isSelected*(field: TokenField, identifier: string): bool =
  field.selectedIndexForKey(identifier) >= 0

proc selectedOptionAtIndex*(field: TokenField, index: int): ComboBoxOption =
  if index in 0 ..< field.xSelectedOptions.len:
    return field.xSelectedOptions[index]

proc optionList*(field: TokenField): ComboBoxOptionList =
  field.xOptions

proc options*(field: TokenField): seq[ComboBoxOption] =
  field.xOptions.options

proc `options=`*(field: TokenField, values: openArray[ComboBoxOption]) =
  let oldIdentifiers = field.xSelectedIdentifiers
  field.xOptions.options = values
  field.xSelectedOptions.setLen(0)
  field.xSelectedIdentifiers.setLen(0)
  for key in oldIdentifiers:
    let index = field.storageIndexForKey(key)
    if index >= 0:
      field.xSelectedOptions.add field.xOptions.options[index]
      field.xSelectedIdentifiers.add key
      if key notin field.xOriginalEnabled:
        field.xOriginalEnabled[key] = field.xOptions.options[index].enabled
  field.updateEnabledOptions()
  if not field.xInput.isNil:
    field.xInput.reloadData()
  field.rebuildChips()

proc setOptions*(field: TokenField, values: openArray[ComboBoxOption]) =
  field.options = values

proc optionCount*(field: TokenField): int =
  field.xOptions.sourceLen()

proc numberOfOptions*(field: TokenField): int =
  field.optionCount()

proc filteredOptionCount*(field: TokenField): int =
  if field.xInput.isNil:
    return 0
  field.xInput.numberOfItems()

proc optionAtIndex*(field: TokenField, index: int): ComboBoxOption =
  if not field.xInput.isNil:
    return field.xInput.optionAtIndex(index)

proc optionIsEnabledAtIndex*(field: TokenField, index: int): bool =
  if not field.xInput.isNil:
    return field.xInput.optionIsEnabledAtIndex(index)

proc addOption*(field: TokenField, option: ComboBoxOption) =
  field.xOptions.add option
  if not field.xInput.isNil:
    field.xInput.reloadData()

proc insertOption*(field: TokenField, option: ComboBoxOption, index: int) =
  field.xOptions.insert(option, index)
  if not field.xInput.isNil:
    field.xInput.reloadData()

proc query*(field: TokenField): string =
  field.xQuery

proc `query=`*(field: TokenField, value: string) =
  field.setTokenQuery(value)

proc placeholder*(field: TokenField): string =
  field.xPlaceholder

proc `placeholder=`*(field: TokenField, value: string) =
  if field.xPlaceholder == value:
    return
  field.xPlaceholder = value
  if field.xQuery.len == 0 and not field.xInput.isNil:
    field.xInput.text = value
    field.xInput.needsDisplay = true

proc allowDuplicates*(field: TokenField): bool =
  field.xAllowDuplicates

proc `allowDuplicates=`*(field: TokenField, value: bool) =
  if field.xAllowDuplicates == value:
    return
  field.xAllowDuplicates = value
  field.updateEnabledOptions()
  if not field.xInput.isNil:
    field.xInput.reloadData()

proc removesLastTokenOnBackspace*(field: TokenField): bool =
  field.xRemovesLastTokenOnBackspace

proc `removesLastTokenOnBackspace=`*(field: TokenField, value: bool) =
  field.xRemovesLastTokenOnBackspace = value

proc queryComboBox*(field: TokenField): ComboBox =
  field.xInput

proc input*(field: TokenField): ComboBox =
  field.queryComboBox()

proc comboBox*(field: TokenField): ComboBox =
  field.queryComboBox()

proc chipScrollView*(field: TokenField): ScrollView =
  field.xChipScroll

proc chipRow*(field: TokenField): StackView =
  field.xChipRow

proc chips*(field: TokenField): seq[Chip] =
  field.xChips

proc chipCount*(field: TokenField): int =
  field.xChips.len

proc chipAtIndex*(field: TokenField, index: int): Chip =
  if index in 0 ..< field.xChips.len:
    return field.xChips[index]

proc inputStyleId*(field: TokenField): string =
  field.xInputStyleId

proc `inputStyleId=`*(field: TokenField, value: string) =
  if field.xInputStyleId == value:
    return
  field.xInputStyleId = value
  if not field.xInput.isNil:
    field.xInput.styleId = value

proc inputStyleClasses*(field: TokenField): seq[string] =
  field.xInputStyleClasses

proc `inputStyleClasses=`*(field: TokenField, value: openArray[string]) =
  field.xInputStyleClasses = @value
  if not field.xInput.isNil:
    field.xInput.styleClasses = field.xInputStyleClasses

proc chipStyleClasses*(field: TokenField): seq[string] =
  field.xChipStyleClasses

proc `chipStyleClasses=`*(field: TokenField, value: openArray[string]) =
  field.xChipStyleClasses = @value
  for chip in field.xChips:
    chip.styleClasses = field.xChipStyleClasses

proc onSelect*(field: TokenField): TokenFieldSelectionHandler =
  field.xOnSelect

proc `onSelect=`*(field: TokenField, handler: TokenFieldSelectionHandler) =
  field.xOnSelect = handler

proc onRemove*(field: TokenField): TokenFieldRemovalHandler =
  field.xOnRemove

proc `onRemove=`*(field: TokenField, handler: TokenFieldRemovalHandler) =
  field.xOnRemove = handler

proc onChange*(field: TokenField): TokenFieldChangeHandler =
  field.xOnChange

proc `onChange=`*(field: TokenField, handler: TokenFieldChangeHandler) =
  field.xOnChange = handler

proc popupOpen*(field: TokenField): bool =
  not field.xInput.isNil and field.xInput.popupOpen()

proc `popupOpen=`*(field: TokenField, value: bool) =
  if field.xInput.isNil:
    return
  field.xInput.popupOpen = value

proc popupPresentation*(field: TokenField): PopupPresentation =
  field.xInput.popupPresentation()

proc `popupPresentation=`*(field: TokenField, value: PopupPresentation) =
  field.xInput.popupPresentation = value

proc maxVisibleItems*(field: TokenField): int =
  field.xInput.maxVisibleItems()

proc `maxVisibleItems=`*(field: TokenField, value: int) =
  field.xInput.maxVisibleItems = value

proc itemHeight*(field: TokenField): float32 =
  field.xInput.itemHeight()

proc `itemHeight=`*(field: TokenField, value: float32) =
  field.xInput.itemHeight = value

proc setOptionEnabled(field: TokenField, key: string, value: bool) =
  let index = field.storageIndexForKey(key)
  if index < 0:
    return
  var values = field.xOptions.options
  values[index].enabled = value
  field.xOptions.options = values

proc updateEnabledOptions(field: TokenField) =
  if field.xOptions.isNil:
    return
  var values = field.xOptions.options
  if field.xAllowDuplicates:
    for index, option in values:
      let key = option.tokenOptionKey()
      if key in field.xOriginalEnabled:
        values[index].enabled = field.xOriginalEnabled[key]
    field.xOptions.options = values
    return
  for index, option in values:
    let key = option.tokenOptionKey()
    if field.selectedIndexForKey(key) >= 0:
      if key notin field.xOriginalEnabled:
        field.xOriginalEnabled[key] = option.enabled
      values[index].enabled = false
    elif key in field.xOriginalEnabled:
      values[index].enabled = field.xOriginalEnabled[key]
  field.xOptions.options = values

proc chipRemovalHandler(fieldRef: WeakRef[TokenField], key: string): ChipRemoveHandler =
  result = proc(sender: Chip) =
    discard sender
    if not fieldRef.isNil:
      discard fieldRef[].removeSelectedOptionWithIdentifier(key)

proc rebuildChips(field: TokenField) =
  for chip in field.xChips:
    chip.removeFromSuperview()
  field.xChips.setLen(0)
  for child in field.xChipRow.arrangedSubviews:
    child.removeFromSuperview()

  let fieldRef = field.unsafeWeakRef()
  for index, option in field.xSelectedOptions:
    let
      chip = newChip(tokenOptionDisplayText(option), removable = true)
      key = field.xSelectedIdentifiers[index]
    chip.identifier = key
    chip.selected = true
    chip.enabled = field.isEnabled()
    chip.styleClasses = field.xChipStyleClasses
    chip.onRemove = chipRemovalHandler(fieldRef, key)
    field.xChipRow.addArrangedSubview(chip)
    field.xChips.add chip
  field.xChipRow.sizeToFit()
  field.xChipScroll.tile()
  field.invalidateContainerMetrics()
  field.setNeedsLayout()
  field.needsDisplay = true

proc notifyTokenChange(
    field: TokenField, option: ComboBoxOption, selected: bool, notify = true
) =
  if selected:
    if not field.xOnSelect.isNil:
      field.xOnSelect(option)
  elif not field.xOnRemove.isNil:
    field.xOnRemove(option)
  if notify:
    if not field.xOnChange.isNil:
      field.xOnChange(field)
    discard field.sendAction()
  field.postAccessibilityNotification(anValueChanged)

proc selectOption(field: TokenField, option: ComboBoxOption, notify = true): bool =
  let key = option.tokenOptionKey()
  if not option.tokenOptionSelectable() or
      (not field.xAllowDuplicates and field.selectedIndexForKey(key) >= 0):
    return false
  if key notin field.xOriginalEnabled:
    field.xOriginalEnabled[key] = option.enabled
  field.xSelectedOptions.add option
  field.xSelectedIdentifiers.add key
  field.updateEnabledOptions()
  if not field.xInput.isNil:
    field.xInput.reloadData()
  field.clearTokenQuery()
  field.rebuildChips()
  field.notifyTokenChange(option, selected = true, notify = notify)
  true

proc selectOptionAtIndex*(field: TokenField, index: int, notify = true): bool =
  if field.xInput.isNil:
    return false
  field.selectOption(field.xInput.optionAtIndex(index), notify)

proc selectOptionWithIdentifier*(
    field: TokenField, identifier: string, notify = true
): bool =
  let index = field.storageIndexForKey(identifier)
  if index < 0:
    return false
  field.selectOption(field.xOptions.options[index], notify)

proc removeSelectedOptionAtIndex(field: TokenField, index: int, notify: bool): bool =
  if index < 0 or index >= field.xSelectedOptions.len:
    return false
  let
    option = field.xSelectedOptions[index]
    key = field.xSelectedIdentifiers[index]
  field.xSelectedOptions.delete(index)
  field.xSelectedIdentifiers.delete(index)
  if field.selectedIndexForKey(key) < 0:
    let enabled = field.xOriginalEnabled.getOrDefault(key, true)
    field.setOptionEnabled(key, enabled)
    field.xOriginalEnabled.del(key)
  field.updateEnabledOptions()
  if not field.xInput.isNil:
    field.xInput.reloadData()
  field.rebuildChips()
  field.notifyTokenChange(option, selected = false, notify = notify)
  true

proc removeSelectedOptionAtIndex*(field: TokenField, index: int): bool =
  field.removeSelectedOptionAtIndex(index, notify = true)

proc removeSelectedOptionWithIdentifier*(field: TokenField, identifier: string): bool =
  let index = field.selectedIndexForKey(identifier)
  if index < 0:
    return false
  field.removeSelectedOptionAtIndex(index)

proc removeOptionWithIdentifier*(field: TokenField, identifier: string): bool =
  let removedSelection = field.removeSelectedOptionWithIdentifier(identifier)
  let removedOption = field.xOptions.delete(identifier)
  if removedOption and not field.xInput.isNil:
    field.xInput.reloadData()
  removedSelection or removedOption

proc clearSelection*(field: TokenField) =
  while field.xSelectedOptions.len > 0:
    discard field.removeSelectedOptionAtIndex(field.xSelectedOptions.high)

proc clearQuery*(field: TokenField) =
  field.clearTokenQuery()

proc setTokenQuery(field: TokenField, value: string, openPopup = true) =
  let displayedQuery = if value.len > 0: value else: field.xPlaceholder
  if field.xQuery == value and
      (field.xInput.isNil or field.xInput.text == displayedQuery):
    if openPopup and not field.xInput.isNil:
      field.xInput.openPopup()
    return
  field.xQuery = value
  if field.xInput.isNil:
    return
  field.xInput.optionFilterText = value
  field.xInput.text = if value.len > 0: value else: field.xPlaceholder
  if openPopup and field.xInput.numberOfItems() > 0:
    field.xInput.openPopup()
  elif not openPopup:
    field.xInput.closePopup()
  field.needsDisplay = true

proc clearTokenQuery(field: TokenField) =
  field.xQuery.setLen(0)
  if field.xInput.isNil:
    return
  field.xInput.closePopup()
  field.xInput.optionFilterText = ""
  field.xInput.deselectItem()
  field.xInput.text = field.xPlaceholder
  field.xInput.needsDisplay = true

proc selectInputOption(field: TokenField) =
  if field.xInput.isNil:
    return
  let index = field.xInput.indexOfSelectedItem()
  if index >= 0:
    discard field.selectOptionAtIndex(index)

protocol DefaultTokenFieldControl of ControlProtocol:
  method enabled(field: TokenField): bool =
    field.cell().isEnabled()

  method `enabled=`(field: TokenField, value: bool) =
    field.setTokenFieldEnabled(value)

proc setTokenFieldEnabled(field: TokenField, value: bool) =
  field.cell().setEnabled(value)
  if not field.xInput.isNil:
    field.xInput.enabled = value
  for chip in field.xChips:
    chip.enabled = value
  field.needsDisplay = true

protocol DefaultTokenFieldLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(field: TokenField): IntrinsicSize =
    initIntrinsicSize(TokenFieldDefaultWidth, TokenFieldDefaultHeight)

  method layoutSubviews(field: TokenField) =
    let
      bounds = field.bounds()
      height = max(bounds.size.height, TokenFieldDefaultHeight)
      hasChips = field.xChips.len > 0
      queryWidth =
        if hasChips:
          min(
            max(TokenFieldMinimumQueryWidth, bounds.size.width * 0.45'f32),
            bounds.size.width,
          )
        else:
          bounds.size.width
      chipWidth = max(bounds.size.width - queryWidth, 0.0'f32)
      rowSize = field.xChipRow.sizeThatFits(UnconstrainedFittingSize)
    if hasChips:
      field.xChipScroll.hidden = chipWidth <= 0.0'f32
      field.xChipScroll.frame = rect(0.0, 0.0, chipWidth, height)
      field.xInput.frame = rect(chipWidth, 0.0, queryWidth, height)
      field.xChipRow.frame = rect(0.0, 0.0, max(rowSize.width, chipWidth), height)
    else:
      field.xChipScroll.hidden = true
      field.xChipScroll.frame = rect(0.0, 0.0, 0.0, 0.0)
      field.xInput.frame = rect(0.0, 0.0, bounds.size.width, height)
      field.xChipRow.frame = rect(0.0, 0.0, 0.0, height)
    field.xChipScroll.tile()

protocol DefaultTokenFieldView of ViewProtocol:
  method pointInside(field: TokenField, point: Point): bool =
    if field.bounds().contains(point):
      return true
    if field.xInput.isNil or not field.xInput.popupOpen():
      return false
    let inputPoint = field.xInput.pointFromView(point, field)
    field.xInput.popupRect(field.xInput.bounds()).contains(inputPoint)

  method hitTestLevel(field: TokenField, point: Point): int =
    if not field.xInput.isNil and field.xInput.popupOpen():
      let inputPoint = field.xInput.pointFromView(point, field)
      if field.xInput.popupRect(field.xInput.bounds()).contains(inputPoint):
        return PopupDrawLevel.int
    DefaultDrawLevel.int

protocol DefaultTokenFieldAccessibility of AccessibilityProtocol:
  method accessibilityRole(field: TokenField): AccessibilityRole =
    arComboBox

  method accessibilityLabel(field: TokenField): string =
    if field.xAccessibilityLabel.len > 0:
      field.xAccessibilityLabel
    elif field.identifier().len > 0:
      field.identifier()
    else:
      "Token field"

  method accessibilityValue(field: TokenField): string =
    if field.xSelectedOptions.len == 0:
      "No tokens selected"
    else:
      var values: seq[string]
      for option in field.xSelectedOptions:
        values.add option.tokenOptionDisplayText()
      values.join(", ")

  method accessibilityTraits(field: TokenField): AccessibilityTraits =
    result = field.xAccessibilityTraits + {atSelectable, atEditable}
    if not field.isEnabled():
      result.incl atDisabled
    if field.focused():
      result.incl atFocused

  method isAccessibilityElement(field: TokenField): bool =
    true

  method accessibilityActionNames(field: TokenField): seq[string] =
    result = @[AccessibilityActionShowMenu]
    if field.xSelectedOptions.len > 0:
      result.add AccessibilityActionDelete

  method accessibilityPerformAction(field: TokenField, action: string): bool =
    if not field.isEnabled():
      return false
    case action
    of AccessibilityActionShowMenu:
      field.popupOpen = true
      true
    of AccessibilityActionDelete:
      field.removeSelectedOptionAtIndex(field.xSelectedOptions.high)
    else:
      false

protocol DefaultTokenFieldEvents of ResponderEventProtocol:
  method keyDown(field: TokenField, event: KeyEvent): bool =
    if not field.isEnabled():
      return false
    if event.modifiers == {} and event.key in {keyBackspace, keyDelete}:
      if field.xQuery.len > 0:
        field.setTokenQuery(field.xQuery.runeSubStr(0, field.xQuery.runeLen - 1))
        return true
      if field.xRemovesLastTokenOnBackspace and field.xSelectedOptions.len > 0:
        return field.removeSelectedOptionAtIndex(field.xSelectedOptions.high)
    if event.modifiers == {} and event.text.len > 0:
      field.setTokenQuery(field.xQuery & event.text)
      return true
    if event.modifiers == {} and event.key == keyEnter:
      field.selectInputOption()
      return true
    false

proc initTokenFieldFields*(
    field: TokenField,
    options: openArray[ComboBoxOption] = [],
    placeholder = "Add items...",
    frame: Rect = AutoRect,
) =
  initControlFields(field, frame, newActionCell())
  field.clipsToBounds = false
  field.xOptions = newComboBoxOptionList(options)
  field.xOriginalEnabled = initTable[string, bool]()
  field.xPlaceholder = placeholder
  field.xAllowDuplicates = false
  field.xRemovesLastTokenOnBackspace = true
  field.xInput =
    newComboBox(frame = rect(0.0, 0.0, TokenFieldDefaultWidth, TokenFieldDefaultHeight))
  field.xInput.editable = false
  field.xInput.maxVisibleItems = 6
  field.xInput.popupPresentation = ppInline
  field.xInput.dataSource = field.xOptions
  field.xInput.text = placeholder
  field.xInput.accessibilityIgnored = true
  field.xChipScroll = newScrollView()
  field.xChipScroll.hasHorizontalScroller = false
  field.xChipScroll.hasVerticalScroller = false
  field.xChipScroll.drawsBackground = false
  field.xChipRow = newStackView(laHorizontal)
  field.xChipRow.spacing = TokenFieldChipSpacing
  field.xChipRow.alignment = svaCenter
  field.xChipRow.distribution = svdNatural
  field.xChipScroll.documentView = field.xChipRow
  field.addSubview(field.xChipScroll)
  field.addSubview(field.xInput)

  let
    fieldRef = field.unsafeWeakRef()
    action = actionSelector("nimkit.tokenFieldSelect")
  field.xInput.target = newActionTarget(action) do(sender: DynamicAgent):
    discard sender
    if not fieldRef.isNil:
      fieldRef[].selectInputOption()
  field.xInput.action = action

  let keyWrapper: dynamicSelectors.AroundMethod = proc(
      self: DynamicAgent,
      invocation: var dynamicSelectors.Invocation,
      next: dynamicSelectors.DynamicMethod,
  ) =
    let event = invocation.argsAs(KeyEvent)
    if not fieldRef.isNil and event.modifiers == {} and
        event.key in {keyBackspace, keyDelete}:
      let target = fieldRef[]
      if target.xQuery.len > 0:
        target.setTokenQuery(target.xQuery.runeSubStr(0, target.xQuery.runeLen - 1))
      elif target.xRemovesLastTokenOnBackspace and target.xSelectedOptions.len > 0:
        discard target.removeSelectedOptionAtIndex(target.xSelectedOptions.high)
      invocation.setResult(true)
      return
    if not fieldRef.isNil and event.modifiers == {} and event.text.len > 0:
      fieldRef[].setTokenQuery(fieldRef[].xQuery & event.text)
      invocation.setResult(true)
      return
    if not next.isNil:
      next(self, invocation)
    elif not invocation.handled:
      invocation.setResult(false)
  discard DynamicAgent(field.xInput).pushMethod(keyDown(), keyWrapper)

  field.acceptsFirstResponder = true
  field.accessibilityRole = arComboBox
  field.accessibilityLabel = "Token field"
  discard field.withProtocol(DefaultTokenFieldControl)
  discard field.withProtocol(DefaultTokenFieldLayout)
  discard field.withProtocol(DefaultTokenFieldView)
  discard field.withProtocol(DefaultTokenFieldEvents)
  discard field.withProtocol(DefaultTokenFieldAccessibility)
  field.applyInitialFrame(frame)
  field.rebuildChips()

proc newTokenField*(
    options: openArray[ComboBoxOption] = [],
    placeholder = "Add items...",
    frame: Rect = AutoRect,
): TokenField =
  result = TokenField()
  result.initTokenFieldFields(options, placeholder, frame)

proc newTokenField*(placeholder: string, frame: Rect = AutoRect): TokenField =
  newTokenField([], placeholder, frame)

proc initMultiSelectComboBoxFields*(
    field: MultiSelectComboBox,
    options: openArray[ComboBoxOption] = [],
    placeholder = "Add items...",
    frame: Rect = AutoRect,
) =
  field.initTokenFieldFields(options, placeholder, frame)

proc newMultiSelectComboBox*(
    options: openArray[ComboBoxOption] = [],
    placeholder = "Add items...",
    frame: Rect = AutoRect,
): MultiSelectComboBox =
  newTokenField(options, placeholder, frame)

proc newMultiSelectComboBox*(
    placeholder: string, frame: Rect = AutoRect
): MultiSelectComboBox =
  newTokenField([], placeholder, frame)
