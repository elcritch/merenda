## Shared floating search controls for Kosmo content views.

import std/[options, strutils, unicode]

import sigils/core

import ../nimkit as nimkit except performKeyEquivalent
from ../nimkit/foundation/selectors import performKeyEquivalent
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./searchbuttons

const
  KosmoSearchBarWidth* = 520.0'f32
  KosmoSearchBarHeight* = 48.0'f32
  KosmoSearchBarInset* = 16.0'f32
  SearchBarContentInset = 6.0'f32
  SearchControlSpacing = 6.0'f32
  SearchButtonWidth = 28.0'f32

type
  KosmoSearchQueryAction* = proc(query: string) {.closure.}
  KosmoSearchAction* = proc() {.closure.}

  KosmoSearchBar* = ref object of nimkit.Box
    backwardsSearch*: bool ## Find-next follows older output; arrows remain spatial.
    xQueryField: nimkit.TextField
    xReplacementField: nimkit.TextField
    xReplacementVisible: bool
    disclosureButton: nimkit.Button
    expressionButton: nimkit.Button
    xRegularExpression, xHasMatches: bool
    errorLabel: nimkit.Label
    xErrorMessage: string
    replaceButton, replaceAllButton: nimkit.Button
    onReplace, onReplaceAll: KosmoSearchAction
    previousButton, nextButton, closeButton: nimkit.Button
    onQueryChanged: KosmoSearchQueryAction
    onPrevious, onNext, onClose: KosmoSearchAction

proc focusSearch(bar: KosmoSearchBar, replacing: bool): bool

proc activatePrevious(bar: KosmoSearchBar) =
  if not bar.isNil and not bar.onPrevious.isNil:
    bar.onPrevious()

proc activateNext(bar: KosmoSearchBar) =
  if not bar.isNil and not bar.onNext.isNil:
    bar.onNext()

proc activateClose(bar: KosmoSearchBar) =
  if not bar.isNil and not bar.onClose.isNil:
    bar.onClose()

protocol KosmoSearchBarKeyEquivalents of nimkit.ResponderCommandDispatchProtocol:
  method performKeyEquivalent(bar: KosmoSearchBar, event: nimkit.KeyEvent): bool =
    if event.key == nimkit.keyF:
      if event.modifiers == nimkit.shortcutModifiers():
        return bar.focusSearch(replacing = false)
      if event.modifiers == nimkit.shortcutModifiers() + {nimkit.kmOption}:
        return bar.focusSearch(replacing = true)
    if event.key == nimkit.keyG:
      if event.modifiers == nimkit.shortcutModifiers():
        if bar.backwardsSearch:
          bar.activatePrevious()
        else:
          bar.activateNext()
        return true
      if event.modifiers == nimkit.shortcutModifiers() + {nimkit.kmShift}:
        if bar.backwardsSearch:
          bar.activateNext()
        else:
          bar.activatePrevious()
        return true
    let owner = bar.window()
    if not (owner of nimkit.Window):
      return
    let window = nimkit.Window(owner)
    let command = window.keyBindings().commandFor(event)
    if command.isNone:
      return
    if command.get().name == nimkit.cancelOperation().name:
      bar.activateClose()
      return true
    let field = window.fieldEditorClient()
    if field.isNil or (field != bar.xQueryField and field != bar.xReplacementField):
      return
    if command.get().name == nimkit.moveUp().name:
      bar.activatePrevious()
    elif command.get().name == nimkit.moveDown().name:
      bar.activateNext()
    elif command.get().name == nimkit.insertNewline().name:
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

protocol KosmoSearchBarMouseEvents of nimkit.ResponderEventProtocol:
  # Children handle their own events. Consume unhandled panel clicks here so
  # padding and disabled controls cannot move the underlying editor's cursor.
  method mouseDown(bar: KosmoSearchBar, event: nimkit.MouseEvent): bool =
    true

  method mouseUp(bar: KosmoSearchBar, event: nimkit.MouseEvent): bool =
    true

  method mouseDragged(bar: KosmoSearchBar, event: nimkit.MouseEvent): bool =
    true

  method rightMouseDown(bar: KosmoSearchBar, event: nimkit.MouseEvent): bool =
    true

  method rightMouseUp(bar: KosmoSearchBar, event: nimkit.MouseEvent): bool =
    true

proc searchQueryDidChange(bar: KosmoSearchBar, sender: nimkit.DynamicAgent) {.slot.} =
  discard sender
  if not bar.onQueryChanged.isNil:
    bar.onQueryChanged(bar.xQueryField.text())

protocol KosmoSearchBarLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(bar: KosmoSearchBar) =
    let
      contentFrame = bar.bounds().inset(nimkit.insets(SearchBarContentInset))
      availableWidth = contentFrame.size.width
      availableHeight = min(contentFrame.size.height, KosmoSearchBarHeight - 12)
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
        nimkit.rect(0, buttonY, disclosureWidth, buttonHeight)
      )
    bar.xQueryField.setFrameFromLayout(
      nimkit.rect(fieldX, controlY, fieldWidth, controlHeight)
    )
    if not bar.expressionButton.isNil:
      bar.expressionButton.setFrameFromLayout(
        nimkit.rect(
          fieldX + fieldWidth + SearchControlSpacing, buttonY, 28, buttonHeight
        )
      )
    if bar.xErrorMessage.len > 0:
      bar.errorLabel.setFrameFromLayout(
        nimkit.rect(0, (if bar.xReplacementVisible: 80 else: 40), availableWidth, 18)
      )
    bar.previousButton.setFrameFromLayout(
      nimkit.rect(firstButtonX, buttonY, buttonWidth, buttonHeight)
    )
    bar.nextButton.setFrameFromLayout(
      nimkit.rect(
        firstButtonX + buttonWidth + SearchControlSpacing,
        buttonY,
        buttonWidth,
        buttonHeight,
      )
    )
    bar.closeButton.setFrameFromLayout(
      nimkit.rect(
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
        nimkit.rect(fieldX, y, replacementWidth, controlHeight)
      )
      bar.replaceButton.setFrameFromLayout(
        nimkit.rect(
          fieldX + replacementWidth + SearchControlSpacing,
          y,
          actionWidth,
          controlHeight,
        )
      )
      bar.replaceAllButton.setFrameFromLayout(
        nimkit.rect(
          fieldX + replacementWidth + actionWidth + 2 * SearchControlSpacing,
          y,
          actionWidth,
          controlHeight,
        )
      )

proc newKosmoSearchBar*(
    accessibilitySubject: string,
    onQueryChanged: KosmoSearchQueryAction,
    onPrevious, onNext, onClose: KosmoSearchAction,
): KosmoSearchBar =
  result = KosmoSearchBar(
    onQueryChanged: onQueryChanged,
    onPrevious: onPrevious,
    onNext: onNext,
    onClose: onClose,
  )
  result.initBoxFields()
  result.addStyleClass(nimkit.PopoverBoxStyleClass)
  result.backdropBlurRadius = 20
  result.backdropTintOpacity = 0.78
  discard result.withProtocol(KosmoSearchBarKeyEquivalents)
  discard result.withProtocol(KosmoSearchBarMouseEvents)
  let searchBar = result.unsafeWeakRef()

  result.xQueryField = nimkit.newTextField()
  result.xQueryField.accessibilityLabel = "Search " & accessibilitySubject
  result.xQueryField.placeholder = "Search"
  result.previousButton = newSearchButton("↑", symbol = true)
  result.nextButton = newSearchButton("↓", symbol = true)
  result.closeButton = newSearchButton("×", symbol = true)
  result.errorLabel = nimkit.newLabel("")
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
  discard result.withProtocol(KosmoSearchBarLayout)
  result.hidden = true

  result.xQueryField.connect(nimkit.textDidChange, result, searchQueryDidChange)
  result.previousButton.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.searchPrevious")
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    if not searchBar.isNil:
      searchBar[].activatePrevious()
  result.previousButton.action = nimkit.actionSelector("kosmo.searchPrevious")
  result.nextButton.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.searchNext")
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    if not searchBar.isNil:
      searchBar[].activateNext()
  result.nextButton.action = nimkit.actionSelector("kosmo.searchNext")
  result.closeButton.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.searchClose")
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    if not searchBar.isNil:
      searchBar[].activateClose()
  result.closeButton.action = nimkit.actionSelector("kosmo.searchClose")

func queryField*(bar: KosmoSearchBar): nimkit.TextField =
  if not bar.isNil:
    result = bar.xQueryField

proc query*(bar: KosmoSearchBar): string =
  if not bar.isNil:
    result = bar.xQueryField.text()

proc `query=`*(bar: KosmoSearchBar, query: string) =
  if not bar.isNil:
    bar.xQueryField.text = query

proc `hasMatches=`*(bar: KosmoSearchBar, hasMatches: bool) =
  if not bar.isNil:
    bar.xHasMatches = hasMatches
    bar.previousButton.enabled = hasMatches
    bar.nextButton.enabled = hasMatches
    if not bar.replaceButton.isNil:
      bar.replaceButton.enabled = hasMatches and bar.xErrorMessage.len == 0
      bar.replaceAllButton.enabled = bar.replaceButton.enabled

proc layoutInBounds*(bar: KosmoSearchBar, bounds: nimkit.Rect) =
  let
    availableWidth = max(bounds.size.width - KosmoSearchBarInset * 2.0'f32, 1.0'f32)
    width = min(KosmoSearchBarWidth, availableWidth)
    height = min(
      KosmoSearchBarHeight + (if bar.xReplacementVisible: 40.0'f32 else: 0.0'f32) +
        (if bar.xErrorMessage.len > 0: 22.0'f32 else: 0.0'f32),
      bounds.size.height,
    )
  bar.setFrameFromLayout(
    nimkit.rect(
      max(bounds.size.width - width - KosmoSearchBarInset, 0.0'f32),
      min(KosmoSearchBarInset, max(bounds.size.height - height, 0.0'f32)),
      width,
      height,
    )
  )

proc `errorMessage=`*(bar: KosmoSearchBar, message: string) =
  bar.xErrorMessage = message
  bar.errorLabel.text = message
  bar.errorLabel.toolTip = message
  bar.errorLabel.hidden = message.len == 0
  bar.hasMatches = bar.xHasMatches
  let parent = bar.superview()
  if not parent.isNil:
    bar.layoutInBounds(parent.bounds())
  bar.setNeedsLayout()

func regularExpression*(bar: KosmoSearchBar): bool =
  bar.xRegularExpression

proc `regularExpression=`*(bar: KosmoSearchBar, enabled: bool) =
  bar.xRegularExpression = enabled
  if not bar.expressionButton.isNil:
    bar.expressionButton.state = if enabled: nimkit.bsOn else: nimkit.bsOff
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

proc enableExpressions*(bar: KosmoSearchBar) =
  ## Offer opt-in Reni matching only for search targets that support it.
  if not bar.expressionButton.isNil:
    return
  bar.expressionButton = newSearchButton(".*", symbol = true)
  bar.expressionButton.buttonType = nimkit.btToggle
  bar.expressionButton.accessibilityLabel = "Use Reni regular expressions"
  bar.expressionButton.toolTip = "Use Reni expressions and replacement captures"
  bar.contentView().addSubview(bar.expressionButton, nimkit.svpAbove, bar.xQueryField)
  let weakBar = bar.unsafeWeakRef()
  bar.expressionButton.action = nimkit.actionSelector("kosmo.searchExpressions")
  bar.expressionButton.target = nimkit.newActionTarget(bar.expressionButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not weakBar.isNil:
      weakBar[].regularExpression = weakBar[].expressionButton.state == nimkit.bsOn
      let owner = weakBar[].window()
      if owner of nimkit.Window:
        discard nimkit.Window(owner).makeFirstResponder(weakBar[].xQueryField)

func replacementVisible*(bar: KosmoSearchBar): bool =
  bar.xReplacementVisible

proc `replacementVisible=`*(bar: KosmoSearchBar, visible: bool) =
  ## Reveal replacement controls without changing the query or replacement text.
  if bar.xReplacementField.isNil:
    return
  let owner = bar.window()
  if not visible and owner of nimkit.Window:
    let window = nimkit.Window(owner)
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

proc focusSearch(bar: KosmoSearchBar, replacing: bool): bool =
  if replacing and bar.xReplacementField.isNil:
    return
  let owner = bar.window()
  if owner of nimkit.Window:
    bar.replacementVisible = replacing
    result = nimkit.Window(owner).makeFirstResponder(bar.xQueryField)
    bar.xQueryField.selectedRange = nimkit.initTextRange(0, bar.query().runeLen)

proc replacementDidChange(bar: KosmoSearchBar, sender: nimkit.DynamicAgent) {.slot.} =
  discard sender
  if bar.xErrorMessage.startsWith("Replacement error:"):
    bar.errorMessage = ""

proc enableReplacement*(
    bar: KosmoSearchBar, onReplace, onReplaceAll: KosmoSearchAction
) =
  ## Add initially collapsed replacement controls to an editable search target.
  bar.onReplace = onReplace
  bar.onReplaceAll = onReplaceAll
  if not bar.xReplacementField.isNil:
    return
  let weakBar = bar.unsafeWeakRef()
  bar.xReplacementField = nimkit.newTextField()
  bar.xReplacementField.accessibilityLabel = "Replace with (literal text)"
  bar.xReplacementField.placeholder = "Replace with"
  bar.replaceButton = newSearchButton("Replace")
  bar.replaceAllButton = newSearchButton("Replace All")
  bar.disclosureButton = newSearchButton("›", symbol = true)
  bar.replaceButton.accessibilityLabel = "Replace match"
  bar.replaceAllButton.accessibilityLabel = "Replace all matches"
  let previousField =
    if bar.expressionButton.isNil:
      nimkit.View(bar.xQueryField)
    else:
      nimkit.View(bar.expressionButton)
  bar.contentView().addSubview(bar.xReplacementField, nimkit.svpAbove, previousField)
  bar.contentView().addSubview(
    bar.replaceButton, nimkit.svpAbove, bar.xReplacementField
  )
  bar.contentView().addSubview(bar.replaceAllButton, nimkit.svpAbove, bar.replaceButton)
  bar.contentView().addSubview(bar.disclosureButton)
  bar.disclosureButton.action = nimkit.actionSelector("kosmo.toggleReplacement")
  bar.disclosureButton.target = nimkit.newActionTarget(bar.disclosureButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not weakBar.isNil:
      let bar = weakBar[]
      bar.replacementVisible = not bar.replacementVisible
      let owner = bar.window()
      if owner of nimkit.Window:
        discard nimkit.Window(owner).makeFirstResponder(bar.xQueryField)
  bar.xReplacementField.connect(nimkit.textDidChange, bar, replacementDidChange)
  bar.replaceButton.action = nimkit.actionSelector("kosmo.replaceMatch")
  bar.replaceButton.target = nimkit.newActionTarget(bar.replaceButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not weakBar.isNil and not weakBar[].onReplace.isNil:
      weakBar[].onReplace()
  bar.replaceAllButton.action = nimkit.actionSelector("kosmo.replaceAllMatches")
  bar.replaceAllButton.target = nimkit.newActionTarget(bar.replaceAllButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not weakBar.isNil and not weakBar[].onReplaceAll.isNil:
      weakBar[].onReplaceAll()
  bar.replacementVisible = false

func replacementField*(bar: KosmoSearchBar): nimkit.TextField =
  bar.xReplacementField
