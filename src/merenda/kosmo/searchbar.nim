## Shared floating search controls for Kosmo content views.

import sigils/core

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout

const
  KosmoSearchBarWidth* = 520.0'f32
  KosmoSearchBarHeight* = 56.0'f32
  KosmoSearchBarInset* = 16.0'f32
  SearchControlInset = 10.0'f32
  SearchControlSpacing = 6.0'f32
  SearchButtonWidth = 30.0'f32
  SearchBarStyleId = "kosmo.search.bar"
  SearchFieldStyleId = "kosmo.search.field"
  SearchButtonStyleId = "kosmo.search.button"

type
  KosmoSearchQueryAction* = proc(query: string) {.closure.}
  KosmoSearchAction* = proc() {.closure.}

  KosmoSearchBar* = ref object of nimkit.Box
    xQueryField: nimkit.TextField
    promptLabel: nimkit.Label
    previousButton, nextButton, closeButton: nimkit.Button
    onQueryChanged: KosmoSearchQueryAction
    onPrevious, onNext, onClose: KosmoSearchAction

  KosmoSearchFieldEditor = ref object of nimkit.FieldEditor
    searchBar: WeakRef[KosmoSearchBar]

  KosmoSearchFieldCell = ref object of nimkit.TextFieldCell
    editor: KosmoSearchFieldEditor

proc activatePrevious(bar: KosmoSearchBar) =
  if not bar.isNil and not bar.onPrevious.isNil:
    bar.onPrevious()

proc activateNext(bar: KosmoSearchBar) =
  if not bar.isNil and not bar.onNext.isNil:
    bar.onNext()

proc activateClose(bar: KosmoSearchBar) =
  if not bar.isNil and not bar.onClose.isNil:
    bar.onClose()

protocol KosmoSearchFieldCellEditing of nimkit.CellEditingProtocol:
  method fieldEditorForView(
      cell: KosmoSearchFieldCell, controlView: nimkit.View
  ): nimkit.FieldEditor =
    discard controlView
    cell.editor

protocol KosmoSearchEditorMovement of nimkit.TextEditingCommandProtocol:
  method moveUp(editor: KosmoSearchFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.searchBar.isNil:
      editor.searchBar[].activatePrevious()

  method moveDown(editor: KosmoSearchFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.searchBar.isNil:
      editor.searchBar[].activateNext()

protocol KosmoSearchEditorActivation of nimkit.KeyViewCommandProtocol:
  method insertNewline(editor: KosmoSearchFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.searchBar.isNil:
      editor.searchBar[].activateNext()

protocol KosmoSearchEditorCancellation of nimkit.MenuCommandProtocol:
  method cancelOperation(editor: KosmoSearchFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.searchBar.isNil:
      editor.searchBar[].activateClose()

proc searchQueryDidChange(bar: KosmoSearchBar, sender: nimkit.DynamicAgent) {.slot.} =
  discard sender
  bar.promptLabel.hidden = bar.xQueryField.text().len > 0
  if not bar.onQueryChanged.isNil:
    bar.onQueryChanged(bar.xQueryField.text())

protocol KosmoSearchBarLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(bar: KosmoSearchBar) =
    let
      contentFrame = bar.contentRect()
      availableWidth = contentFrame.size.width
      availableHeight = contentFrame.size.height
      controlHeight =
        min(max(availableHeight - SearchControlInset * 2.0'f32, 1.0'f32), 34.0'f32)
      buttonWidth = min(SearchButtonWidth, availableWidth / 4.0'f32)
      buttonsWidth = buttonWidth * 3.0'f32 + SearchControlSpacing * 3.0'f32
      fieldWidth = max(availableWidth - buttonsWidth, 1.0'f32)
      controlY = max((availableHeight - controlHeight) * 0.5'f32, 0.0'f32)
      firstButtonX = fieldWidth + SearchControlSpacing
    bar.contentView().setFrameFromLayout(contentFrame)
    bar.xQueryField.setFrameFromLayout(
      nimkit.rect(0, controlY, fieldWidth, controlHeight)
    )
    bar.promptLabel.setFrameFromLayout(
      nimkit.rect(10, controlY, max(fieldWidth - 20.0'f32, 1.0'f32), controlHeight)
    )
    bar.previousButton.setFrameFromLayout(
      nimkit.rect(firstButtonX, controlY, buttonWidth, controlHeight)
    )
    bar.nextButton.setFrameFromLayout(
      nimkit.rect(
        firstButtonX + buttonWidth + SearchControlSpacing,
        controlY,
        buttonWidth,
        controlHeight,
      )
    )
    bar.closeButton.setFrameFromLayout(
      nimkit.rect(
        firstButtonX + (buttonWidth + SearchControlSpacing) * 2.0'f32,
        controlY,
        buttonWidth,
        controlHeight,
      )
    )

proc applyKosmoSearchAppearance*(bar: KosmoSearchBar, base: nimkit.Appearance) =
  var appearance = base
  let
    barSelector = nimkit.initStyleSelector(nimkit.srBox, id = SearchBarStyleId)
    fieldSelector =
      nimkit.initStyleSelector(nimkit.srTextField, id = SearchFieldStyleId)
    buttonSelector = nimkit.initStyleSelector(nimkit.srButton, id = SearchButtonStyleId)
    highlightedButtonSelector = nimkit.initStyleSelector(
      nimkit.srButton, {nimkit.ssHighlighted}, id = SearchButtonStyleId
    )
  appearance.setStyle(
    barSelector, nimkit.StyleFill, nimkit.fill(nimkit.color(0.08, 0.08, 0.075, 0.96))
  )
  appearance.setStyle(barSelector, nimkit.StyleBorderWidth, 0.0'f32)
  appearance.setStyle(barSelector, nimkit.StyleCornerRadius, 12.0'f32)
  appearance.setStyle(
    fieldSelector, nimkit.StyleFill, nimkit.fill(nimkit.color(0.18, 0.18, 0.17, 1.0))
  )
  appearance.setStyle(fieldSelector, nimkit.StyleBorderWidth, 0.0'f32)
  appearance.setStyle(fieldSelector, nimkit.StyleCornerRadius, 8.0'f32)
  appearance.setStyle(
    fieldSelector, nimkit.StyleChrome, nimkit.styleKeyword(nimkit.DefaultChromeName)
  )
  appearance.setStyle(
    fieldSelector, nimkit.StyleTextColor, nimkit.color(0.85, 0.85, 0.84)
  )
  appearance.setStyle(
    buttonSelector, nimkit.StyleFill, nimkit.fill(nimkit.color(0.0, 0.0, 0.0, 0.0))
  )
  appearance.setStyle(buttonSelector, nimkit.StyleBorderWidth, 0.0'f32)
  appearance.setStyle(buttonSelector, nimkit.StyleCornerRadius, 6.0'f32)
  appearance.setStyle(buttonSelector, nimkit.StyleTextInsets, nimkit.insets(0.0, 2.0))
  appearance.setStyle(
    buttonSelector, nimkit.StyleTextColor, nimkit.color(0.68, 0.68, 0.67)
  )
  appearance.setStyle(
    buttonSelector,
    nimkit.StyleChrome,
    nimkit.styleKeyword(nimkit.FlatTransparentChromeName),
  )
  appearance.setStyle(
    highlightedButtonSelector,
    nimkit.StyleFill,
    nimkit.fill(nimkit.color(1.0, 1.0, 1.0, 0.10)),
  )
  bar.appearance = appearance

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
  result.styleId = SearchBarStyleId

  let
    searchBar = result.unsafeWeakRef()
    editor = KosmoSearchFieldEditor(searchBar: searchBar)
  editor.initFieldEditorFields()
  discard editor.withProtocol(KosmoSearchEditorMovement)
  discard editor.withProtocol(KosmoSearchEditorActivation)
  discard editor.withProtocol(KosmoSearchEditorCancellation)
  let cell = KosmoSearchFieldCell(editor: editor)
  cell.initTextFieldCellFields()
  discard cell.withProtocol(KosmoSearchFieldCellEditing)

  result.xQueryField = nimkit.newTextField()
  result.xQueryField.setCell(cell)
  result.xQueryField.styleId = SearchFieldStyleId
  result.xQueryField.accessibilityLabel = "Search " & accessibilitySubject
  result.promptLabel = nimkit.newLabel("Search")
  result.promptLabel.textColor = nimkit.color(0.42, 0.42, 0.41)
  result.previousButton = nimkit.newButton("⌃")
  result.nextButton = nimkit.newButton("⌄")
  result.closeButton = nimkit.newButton("×")
  for button in [result.previousButton, result.nextButton, result.closeButton]:
    button.styleId = SearchButtonStyleId
  result.previousButton.accessibilityLabel =
    "Previous " & accessibilitySubject & " match"
  result.previousButton.toolTip = "Previous match"
  result.nextButton.accessibilityLabel = "Next " & accessibilitySubject & " match"
  result.nextButton.toolTip = "Next match"
  result.closeButton.accessibilityLabel = "Close " & accessibilitySubject & " search"
  result.closeButton.toolTip = "Close search"
  result.contentView().addSubview(result.xQueryField)
  result.contentView().addSubview(result.promptLabel)
  result.contentView().addSubview(result.previousButton)
  result.contentView().addSubview(result.nextButton)
  result.contentView().addSubview(result.closeButton)
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
    bar.promptLabel.hidden = query.len > 0

proc `hasMatches=`*(bar: KosmoSearchBar, hasMatches: bool) =
  if not bar.isNil:
    bar.previousButton.enabled = hasMatches
    bar.nextButton.enabled = hasMatches

proc layoutInBounds*(bar: KosmoSearchBar, bounds: nimkit.Rect) =
  let
    availableWidth = max(bounds.size.width - KosmoSearchBarInset * 2.0'f32, 1.0'f32)
    width = min(KosmoSearchBarWidth, availableWidth)
    height = min(KosmoSearchBarHeight, bounds.size.height)
  bar.setFrameFromLayout(
    nimkit.rect(
      max(bounds.size.width - width - KosmoSearchBarInset, 0.0'f32),
      min(KosmoSearchBarInset, max(bounds.size.height - height, 0.0'f32)),
      width,
      height,
    )
  )
