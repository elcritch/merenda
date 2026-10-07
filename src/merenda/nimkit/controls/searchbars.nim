## Floating find controls with optional Reni expressions and replacement actions.

import std/[options, strutils, unicode]

import sigils/core

import ../accessibility/accessibility
import ../app/windows except performKeyEquivalent
import ../containers/boxes
import ../foundation/[events, selectors, types]
from ../foundation/selectors import performKeyEquivalent
import ../responder/keybindings
import ../text/textfields
import ../themes
import ../view/[viewgeometry, views]
import ./[buttons, searchbuttons]

const
  SearchBarWidth* = 520.0'f32
  SearchBarHeight* = 48.0'f32
  SearchBarInset* = 16.0'f32
  SearchBarContentInset = 6.0'f32
  SearchControlSpacing = 6.0'f32
  SearchButtonWidth = 28.0'f32

type
  SearchQueryAction* = proc(query: string) {.closure.}
  SearchAction* = proc() {.closure.}

  SearchBar* = ref object of Box
    backwardsSearch*: bool ## Find-next follows older output; arrows remain spatial.
    xQueryField: TextField
    xReplacementField: TextField
    xReplacementVisible: bool
    disclosureButton: Button
    expressionButton: Button
    xRegularExpression, xHasMatches: bool
    errorLabel: Label
    xErrorMessage: string
    replaceButton, replaceAllButton: Button
    onReplace, onReplaceAll: SearchAction
    previousButton, nextButton, closeButton: Button
    onQueryChanged: SearchQueryAction
    onPrevious, onNext, onClose: SearchAction

proc focusSearch(bar: SearchBar, replacing: bool): bool

proc activatePrevious(bar: SearchBar) =
  if not bar.isNil and not bar.onPrevious.isNil:
    bar.onPrevious()

proc activateNext(bar: SearchBar) =
  if not bar.isNil and not bar.onNext.isNil:
    bar.onNext()

proc activateClose(bar: SearchBar) =
  if not bar.isNil and not bar.onClose.isNil:
    bar.onClose()

protocol SearchBarKeyEquivalents of ResponderCommandDispatchProtocol:
  method performKeyEquivalent(bar: SearchBar, event: KeyEvent): bool =
    if event.key == keyF:
      if event.modifiers == shortcutModifiers():
        return bar.focusSearch(replacing = false)
      if event.modifiers == shortcutModifiers() + {kmOption}:
        return bar.focusSearch(replacing = true)
    if event.key == keyG:
      if event.modifiers == shortcutModifiers():
        if bar.backwardsSearch:
          bar.activatePrevious()
        else:
          bar.activateNext()
        return true
      if event.modifiers == shortcutModifiers() + {kmShift}:
        if bar.backwardsSearch:
          bar.activateNext()
        else:
          bar.activatePrevious()
        return true
    let owner = bar.window()
    if not (owner of Window):
      return
    let window = Window(owner)
    let command = window.keyBindings().commandFor(event)
    if command.isNone:
      return
    if command.get().name == cancelOperation().name:
      bar.activateClose()
      return true
    let field = window.fieldEditorClient()
    if field.isNil or (field != bar.xQueryField and field != bar.xReplacementField):
      return
    if command.get().name == moveUp().name:
      bar.activatePrevious()
    elif command.get().name == moveDown().name:
      bar.activateNext()
    elif command.get().name == insertNewline().name:
      if field == bar.xReplacementField:
        if not bar.onReplace.isNil:
          bar.onReplace()
      elif bar.backwardsSearch:
        bar.activatePrevious()
      else:
        bar.activateNext()
    else:
      return
    true

protocol SearchBarMouseEvents of ResponderEventProtocol:
  # Children handle their own events. Consume unhandled panel clicks here so
  # padding and disabled controls cannot move the underlying editor's cursor.
  method mouseDown(bar: SearchBar, event: MouseEvent): bool =
    true

  method mouseUp(bar: SearchBar, event: MouseEvent): bool =
    true

  method mouseDragged(bar: SearchBar, event: MouseEvent): bool =
    true

  method rightMouseDown(bar: SearchBar, event: MouseEvent): bool =
    true

  method rightMouseUp(bar: SearchBar, event: MouseEvent): bool =
    true

proc searchQueryDidChange(bar: SearchBar, sender: DynamicAgent) {.slot.} =
  discard sender
  if not bar.onQueryChanged.isNil:
    bar.onQueryChanged(bar.xQueryField.text())

protocol SearchBarLayout of ViewLayoutProtocol:
  method layoutSubviews(bar: SearchBar) =
    let
      contentFrame = bar.bounds().inset(insets(SearchBarContentInset))
      availableWidth = contentFrame.size.width
      availableHeight = min(contentFrame.size.height, SearchBarHeight - 12)
      controlHeight = min(max(availableHeight, 1.0'f32), 34.0'f32)
      buttonWidth = min(SearchButtonWidth, availableWidth / 4.0'f32)
      disclosureWidth =
        if bar.disclosureButton.isNil:
          0.0'f32
        else:
          min(24.0'f32, availableWidth / 8)
      fieldX =
        if bar.disclosureButton.isNil:
          0.0'f32
        else:
          disclosureWidth + SearchControlSpacing
      expressionWidth = if bar.expressionButton.isNil: 0.0'f32 else: 34.0'f32
      buttonsWidth = buttonWidth * 3.0'f32 + SearchControlSpacing * 3.0'f32
      fieldWidth =
        max(availableWidth - buttonsWidth - fieldX - expressionWidth, 1.0'f32)
      controlY = max((availableHeight - controlHeight) * 0.5'f32, 0.0'f32)
      buttonHeight = min(controlHeight, 28.0'f32)
      buttonY = controlY + (controlHeight - buttonHeight) / 2
      firstButtonX = fieldX + fieldWidth + expressionWidth + SearchControlSpacing
    bar.contentView().setFrameFromLayout(contentFrame)
    if not bar.disclosureButton.isNil:
      bar.disclosureButton.setFrameFromLayout(
        rect(0, buttonY, disclosureWidth, buttonHeight)
      )
    bar.xQueryField.setFrameFromLayout(
      rect(fieldX, controlY, fieldWidth, controlHeight)
    )
    if not bar.expressionButton.isNil:
      bar.expressionButton.setFrameFromLayout(
        rect(fieldX + fieldWidth + SearchControlSpacing, buttonY, 28, buttonHeight)
      )
    if bar.xErrorMessage.len > 0:
      bar.errorLabel.setFrameFromLayout(
        rect(0, (if bar.xReplacementVisible: 80 else: 40), availableWidth, 18)
      )
    bar.previousButton.setFrameFromLayout(
      rect(firstButtonX, buttonY, buttonWidth, buttonHeight)
    )
    bar.nextButton.setFrameFromLayout(
      rect(
        firstButtonX + buttonWidth + SearchControlSpacing,
        buttonY,
        buttonWidth,
        buttonHeight,
      )
    )
    bar.closeButton.setFrameFromLayout(
      rect(
        firstButtonX + (buttonWidth + SearchControlSpacing) * 2.0'f32,
        buttonY,
        buttonWidth,
        buttonHeight,
      )
    )

    if bar.xReplacementVisible:
      let y = controlY + 40.0'f32
      let actionWidth = min(90.0'f32, availableWidth / 3)
      let replacementWidth =
        max(availableWidth - fieldX - 2 * (actionWidth + SearchControlSpacing), 1)
      bar.xReplacementField.setFrameFromLayout(
        rect(fieldX, y, replacementWidth, controlHeight)
      )
      bar.replaceButton.setFrameFromLayout(
        rect(
          fieldX + replacementWidth + SearchControlSpacing,
          y,
          actionWidth,
          controlHeight,
        )
      )
      bar.replaceAllButton.setFrameFromLayout(
        rect(
          fieldX + replacementWidth + actionWidth + 2 * SearchControlSpacing,
          y,
          actionWidth,
          controlHeight,
        )
      )

proc newSearchBar*(
    accessibilitySubject = "text",
    onQueryChanged: SearchQueryAction = nil,
    onPrevious: SearchAction = nil,
    onNext: SearchAction = nil,
    onClose: SearchAction = nil,
): SearchBar =
  ## Construct floating find controls. Call enableExpressions and optionally
  ## enableReplacement, or use TextSearchController to wire a data adapter.
  result = SearchBar(
    onQueryChanged: onQueryChanged,
    onPrevious: onPrevious,
    onNext: onNext,
    onClose: onClose,
  )
  result.initBoxFields()
  result.addStyleClass(PopoverBoxStyleClass)
  result.backdropBlurRadius = 20
  result.backdropTintOpacity = 0.78
  discard result.withProtocol(SearchBarKeyEquivalents)
  discard result.withProtocol(SearchBarMouseEvents)
  let searchBar = result.unsafeWeakRef()

  result.xQueryField = newTextField()
  result.xQueryField.accessibilityLabel = "Search " & accessibilitySubject
  result.xQueryField.placeholder = "Search"
  result.previousButton = newSearchButton("↑", symbol = true)
  result.nextButton = newSearchButton("↓", symbol = true)
  result.previousButton.enabled = false
  result.nextButton.enabled = false
  result.closeButton = newSearchButton("×", symbol = true)
  result.errorLabel = newLabel("")
  result.errorLabel.hidden = true
  result.previousButton.accessibilityLabel =
    "Previous " & accessibilitySubject & " match"
  result.previousButton.toolTip = "Previous match"
  result.nextButton.accessibilityLabel = "Next " & accessibilitySubject & " match"
  result.nextButton.toolTip = "Next match"
  result.closeButton.accessibilityLabel = "Close " & accessibilitySubject & " search"
  result.closeButton.toolTip = "Close search"
  result.contentView().addSubview(result.xQueryField)
  result.contentView().addSubview(result.previousButton)
  result.contentView().addSubview(result.nextButton)
  result.contentView().addSubview(result.closeButton)
  result.contentView().addSubview(result.errorLabel)
  discard result.withProtocol(SearchBarLayout)
  result.hidden = true

  result.xQueryField.connect(textDidChange, result, searchQueryDidChange)
  result.previousButton.target = newActionTarget(
    actionSelector("nimkit.searchPrevious")
  ) do(sender: DynamicAgent):
    discard sender
    if not searchBar.isNil:
      searchBar[].activatePrevious()
  result.previousButton.action = actionSelector("nimkit.searchPrevious")
  result.nextButton.target = newActionTarget(actionSelector("nimkit.searchNext")) do(
    sender: DynamicAgent
  ):
    discard sender
    if not searchBar.isNil:
      searchBar[].activateNext()
  result.nextButton.action = actionSelector("nimkit.searchNext")
  result.closeButton.target = newActionTarget(actionSelector("nimkit.searchClose")) do(
    sender: DynamicAgent
  ):
    discard sender
    if not searchBar.isNil:
      searchBar[].activateClose()
  result.closeButton.action = actionSelector("nimkit.searchClose")

func queryField*(bar: SearchBar): TextField =
  if not bar.isNil:
    result = bar.xQueryField

proc query*(bar: SearchBar): string =
  if not bar.isNil:
    result = bar.xQueryField.text()

proc `query=`*(bar: SearchBar, query: string) =
  if not bar.isNil:
    bar.xQueryField.text = query

proc `hasMatches=`*(bar: SearchBar, hasMatches: bool) =
  if not bar.isNil:
    bar.xHasMatches = hasMatches
    bar.previousButton.enabled = hasMatches
    bar.nextButton.enabled = hasMatches
    if not bar.replaceButton.isNil:
      bar.replaceButton.enabled = hasMatches and bar.xErrorMessage.len == 0
      bar.replaceAllButton.enabled = bar.replaceButton.enabled

proc layoutInBounds*(bar: SearchBar, bounds: Rect) =
  let
    availableWidth = max(bounds.size.width - SearchBarInset * 2.0'f32, 1.0'f32)
    width = min(SearchBarWidth, availableWidth)
    height = min(
      SearchBarHeight + (if bar.xReplacementVisible: 40.0'f32 else: 0.0'f32) +
        (if bar.xErrorMessage.len > 0: 22.0'f32 else: 0.0'f32),
      bounds.size.height,
    )
  bar.setFrameFromLayout(
    rect(
      max(bounds.size.width - width - SearchBarInset, 0.0'f32),
      min(SearchBarInset, max(bounds.size.height - height, 0.0'f32)),
      width,
      height,
    )
  )

proc `errorMessage=`*(bar: SearchBar, message: string) =
  bar.xErrorMessage = message
  bar.errorLabel.text = message
  bar.errorLabel.toolTip = message
  bar.errorLabel.hidden = message.len == 0
  bar.hasMatches = bar.xHasMatches
  let parent = bar.superview()
  if not parent.isNil:
    bar.layoutInBounds(parent.bounds())
  bar.setNeedsLayout()

func errorMessage*(bar: SearchBar): string =
  bar.xErrorMessage

func regularExpression*(bar: SearchBar): bool =
  bar.xRegularExpression

proc `regularExpression=`*(bar: SearchBar, enabled: bool) =
  bar.xRegularExpression = enabled
  if not bar.expressionButton.isNil:
    bar.expressionButton.state = if enabled: bsOn else: bsOff
  if not bar.xReplacementField.isNil:
    bar.xReplacementField.accessibilityLabel =
      if enabled: "Replace with (capture template)" else: "Replace with (literal text)"
    bar.xReplacementField.toolTip =
      if enabled:
        "Reni replacement: $0, $1, ${name}, $$"
      else:
        "Literal replacement text"
  if not bar.onQueryChanged.isNil:
    bar.onQueryChanged(bar.query())

proc enableExpressions*(bar: SearchBar) =
  ## Offer opt-in Reni matching for a content search target.
  if not bar.expressionButton.isNil:
    return
  bar.expressionButton = newExpressionButton()
  bar.contentView().addSubview(bar.expressionButton, svpAbove, bar.xQueryField)
  let weakBar = bar.unsafeWeakRef()
  bar.expressionButton.action = actionSelector("nimkit.searchExpressions")
  bar.expressionButton.target = newActionTarget(bar.expressionButton.action) do(
    sender: DynamicAgent
  ):
    if not weakBar.isNil:
      weakBar[].regularExpression = weakBar[].expressionButton.state == bsOn
      let owner = weakBar[].window()
      if owner of Window:
        discard Window(owner).makeFirstResponder(weakBar[].xQueryField)

func replacementVisible*(bar: SearchBar): bool =
  bar.xReplacementVisible

proc `replacementVisible=`*(bar: SearchBar, visible: bool) =
  ## Reveal replacement controls without changing the query or replacement text.
  if bar.xReplacementField.isNil:
    return
  let owner = bar.window()
  if not visible and owner of Window:
    let window = Window(owner)
    if window.fieldEditorClient() == bar.xReplacementField or
        window.firstResponder() == bar.replaceButton or
        window.firstResponder() == bar.replaceAllButton:
      discard window.makeFirstResponder(bar.xQueryField)
  bar.xReplacementVisible = visible
  bar.xReplacementField.hidden = not visible
  bar.replaceButton.hidden = not visible
  bar.replaceAllButton.hidden = not visible
  bar.disclosureButton.showSearchDisclosure(visible)
  bar.disclosureButton.accessibilityLabel =
    if visible: "Hide replacement controls" else: "Show replacement controls"
  bar.disclosureButton.toolTip = bar.disclosureButton.accessibilityLabel()
  let parent = bar.superview()
  if not parent.isNil:
    bar.layoutInBounds(parent.bounds())
  bar.setNeedsLayout()
  bar.layoutSubtreeIfNeeded()

proc focusSearch(bar: SearchBar, replacing: bool): bool =
  if replacing and bar.xReplacementField.isNil:
    return
  let owner = bar.window()
  if owner of Window:
    bar.replacementVisible = replacing
    result = Window(owner).makeFirstResponder(bar.xQueryField)
    bar.xQueryField.selectedRange = initTextRange(0, bar.query().runeLen)

proc replacementDidChange(bar: SearchBar, sender: DynamicAgent) {.slot.} =
  discard sender
  if bar.xErrorMessage.startsWith("Replacement error:"):
    bar.errorMessage = ""

proc enableReplacement*(bar: SearchBar, onReplace, onReplaceAll: SearchAction) =
  ## Add initially collapsed replacement controls to an editable search target.
  bar.onReplace = onReplace
  bar.onReplaceAll = onReplaceAll
  if not bar.xReplacementField.isNil:
    return
  let weakBar = bar.unsafeWeakRef()
  bar.xReplacementField = newTextField()
  bar.xReplacementField.accessibilityLabel = "Replace with (literal text)"
  bar.xReplacementField.placeholder = "Replace with"
  bar.replaceButton = newSearchButton("Replace")
  bar.replaceAllButton = newSearchButton("Replace All")
  bar.disclosureButton = newSearchButton("›", symbol = true)
  bar.replaceButton.accessibilityLabel = "Replace match"
  bar.replaceAllButton.accessibilityLabel = "Replace all matches"
  let previousField =
    if bar.expressionButton.isNil:
      View(bar.xQueryField)
    else:
      View(bar.expressionButton)
  bar.contentView().addSubview(bar.xReplacementField, svpAbove, previousField)
  bar.contentView().addSubview(bar.replaceButton, svpAbove, bar.xReplacementField)
  bar.contentView().addSubview(bar.replaceAllButton, svpAbove, bar.replaceButton)
  bar.contentView().addSubview(bar.disclosureButton)
  bar.disclosureButton.action = actionSelector("nimkit.toggleReplacement")
  bar.disclosureButton.target = newActionTarget(bar.disclosureButton.action) do(
    sender: DynamicAgent
  ):
    if not weakBar.isNil:
      let bar = weakBar[]
      bar.replacementVisible = not bar.replacementVisible
      let owner = bar.window()
      if owner of Window:
        discard Window(owner).makeFirstResponder(bar.xQueryField)
  bar.xReplacementField.connect(textDidChange, bar, replacementDidChange)
  bar.replaceButton.action = actionSelector("nimkit.replaceMatch")
  bar.replaceButton.target = newActionTarget(bar.replaceButton.action) do(
    sender: DynamicAgent
  ):
    if not weakBar.isNil and not weakBar[].onReplace.isNil:
      weakBar[].onReplace()
  bar.replaceAllButton.action = actionSelector("nimkit.replaceAllMatches")
  bar.replaceAllButton.target = newActionTarget(bar.replaceAllButton.action) do(
    sender: DynamicAgent
  ):
    if not weakBar.isNil and not weakBar[].onReplaceAll.isNil:
      weakBar[].onReplaceAll()
  bar.replacementVisible = false
  bar.hasMatches = bar.xHasMatches

func replacementField*(bar: SearchBar): TextField =
  bar.xReplacementField

proc close*(bar: SearchBar) =
  ## Detach the controls and release action callbacks owned by the search host.
  bar.onQueryChanged = nil
  bar.onPrevious = nil
  bar.onNext = nil
  bar.onClose = nil
  bar.onReplace = nil
  bar.onReplaceAll = nil
  bar.hidden = true
  bar.removeFromSuperview()
