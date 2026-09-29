## Shared floating search controls for Kosmo content views.

import std/options

import sigils/core

import ../nimkit as nimkit except performKeyEquivalent
from ../nimkit/foundation/selectors import performKeyEquivalent
from ../nimkit/view/viewgeometry import setFrameFromLayout

const
  KosmoSearchBarWidth* = 520.0'f32
  KosmoSearchBarHeight* = 48.0'f32
  KosmoSearchBarInset* = 16.0'f32
  SearchBarContentInset = 6.0'f32
  SearchBarBlurRadius = 20.0'f32
  SearchBarTintOpacity = 0.18'f32
  SearchControlSpacing = 6.0'f32
  SearchButtonWidth = 40.0'f32

type
  KosmoSearchQueryAction* = proc(query: string) {.closure.}
  KosmoSearchAction* = proc() {.closure.}

  KosmoSearchBar* = ref object of nimkit.Box
    backwardsSearch*: bool ## Find-next follows older output; arrows remain spatial.
    xQueryField: nimkit.TextField
    xReplacementField: nimkit.TextField
    replacementPrompt: nimkit.Label
    replaceButton, replaceAllButton: nimkit.Button
    onReplace, onReplaceAll: KosmoSearchAction
    promptLabel: nimkit.Label
    previousButton, nextButton, closeButton: nimkit.Button
    onQueryChanged: KosmoSearchQueryAction
    onPrevious, onNext, onClose: KosmoSearchAction

  KosmoSearchFieldEditor = ref object of nimkit.FieldEditor
    searchBar: WeakRef[KosmoSearchBar]
    replacement: bool

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
      if editor.replacement:
        if not editor.searchBar[].onReplace.isNil:
          editor.searchBar[].onReplace()
      elif editor.searchBar[].backwardsSearch:
        editor.searchBar[].activatePrevious()
      else:
        editor.searchBar[].activateNext()

protocol KosmoSearchEditorCancellation of nimkit.MenuCommandProtocol:
  method cancelOperation(editor: KosmoSearchFieldEditor, args: nimkit.ActionArgs) =
    discard args
    if not editor.searchBar.isNil:
      editor.searchBar[].activateClose()

protocol KosmoSearchEditorKeyEquivalents of nimkit.ResponderCommandDispatchProtocol:
  method performKeyEquivalent(
      editor: KosmoSearchFieldEditor, event: nimkit.KeyEvent
  ): bool =
    if not editor.searchBar.isNil and event.key == nimkit.keyG:
      if event.modifiers == nimkit.shortcutModifiers():
        if editor.searchBar[].backwardsSearch:
          editor.searchBar[].activatePrevious()
        else:
          editor.searchBar[].activateNext()
        return true
      if event.modifiers == nimkit.shortcutModifiers() + {nimkit.kmShift}:
        if editor.searchBar[].backwardsSearch:
          editor.searchBar[].activateNext()
        else:
          editor.searchBar[].activatePrevious()
        return true
    let owner = editor.window()
    if not (owner of nimkit.Window):
      return
    let command = nimkit.Window(owner).keyBindings().commandFor(event)
    if command.isNone:
      return
    editor.tryToPerform(command.get(), nimkit.DynamicAgent(editor))

proc searchQueryDidChange(bar: KosmoSearchBar, sender: nimkit.DynamicAgent) {.slot.} =
  discard sender
  bar.promptLabel.hidden = bar.xQueryField.text().len > 0
  if not bar.onQueryChanged.isNil:
    bar.onQueryChanged(bar.xQueryField.text())

func tint(fill: nimkit.Fill, opacity: float32): nimkit.Fill =
  let base = fill.centerColor()
  nimkit.fill(nimkit.color(base.r, base.g, base.b, opacity))

protocol KosmoSearchBarDrawing of nimkit.ViewDrawingProtocol:
  method draw(bar: KosmoSearchBar, context: nimkit.DrawContext) =
    let bounds = bar.bounds()
    if context.isNil or bounds.isEmpty:
      return
    let
      style = context.appearance.resolveBoxStyle(nimkit.controlStyle(nimkit.srBox))
      frame = context.renderRectFor(bounds)
    discard context.addRenderBackdropBlur(
      context.renderLayer(),
      context.renderParent(),
      frame,
      style.box.fill.tint(SearchBarTintOpacity),
      SearchBarBlurRadius,
      style.box.cornerRadius,
      style.box.cornerRadii,
    )
    discard context.addRenderRectangle(
      frame,
      nimkit.fill(nimkit.color(0.0, 0.0, 0.0, 0.0)),
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      cornerRadii = style.box.cornerRadii,
    )

protocol KosmoSearchBarLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(bar: KosmoSearchBar) =
    let
      contentFrame = bar.bounds().inset(nimkit.insets(SearchBarContentInset))
      availableWidth = contentFrame.size.width
      availableHeight = min(contentFrame.size.height, KosmoSearchBarHeight - 12)
      controlHeight = min(max(availableHeight, 1.0'f32), 34.0'f32)
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

    if not bar.xReplacementField.isNil:
      let y = controlY + 40.0'f32
      let actionWidth = min(90.0'f32, availableWidth / 3)
      let replacementWidth =
        max(availableWidth - 2 * (actionWidth + SearchControlSpacing), 1)
      bar.xReplacementField.setFrameFromLayout(
        nimkit.rect(0, y, replacementWidth, controlHeight)
      )
      bar.replacementPrompt.setFrameFromLayout(
        nimkit.rect(10, y, max(replacementWidth - 20, 1), controlHeight)
      )
      bar.replaceButton.setFrameFromLayout(
        nimkit.rect(
          replacementWidth + SearchControlSpacing, y, actionWidth, controlHeight
        )
      )
      bar.replaceAllButton.setFrameFromLayout(
        nimkit.rect(
          replacementWidth + actionWidth + 2 * SearchControlSpacing,
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
  discard result.withProtocol(KosmoSearchBarDrawing)

  let
    searchBar = result.unsafeWeakRef()
    editor = KosmoSearchFieldEditor(searchBar: searchBar)
  editor.initFieldEditorFields()
  discard editor.withProtocol(KosmoSearchEditorMovement)
  discard editor.withProtocol(KosmoSearchEditorActivation)
  discard editor.withProtocol(KosmoSearchEditorCancellation)
  discard editor.withProtocol(KosmoSearchEditorKeyEquivalents)
  let cell = KosmoSearchFieldCell(editor: editor)
  cell.initTextFieldCellFields()
  discard cell.withProtocol(KosmoSearchFieldCellEditing)

  result.xQueryField = nimkit.newTextField()
  result.xQueryField.setCell(cell)
  result.xQueryField.accessibilityLabel = "Search " & accessibilitySubject
  result.promptLabel = nimkit.newLabel("Search")
  result.previousButton = nimkit.newButton("^")
  result.nextButton = nimkit.newButton("v")
  result.closeButton = nimkit.newButton("×")
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
    if not bar.replaceButton.isNil:
      bar.replaceButton.enabled = hasMatches
      bar.replaceAllButton.enabled = hasMatches

proc layoutInBounds*(bar: KosmoSearchBar, bounds: nimkit.Rect) =
  let
    availableWidth = max(bounds.size.width - KosmoSearchBarInset * 2.0'f32, 1.0'f32)
    width = min(KosmoSearchBarWidth, availableWidth)
    height = min(
      KosmoSearchBarHeight + (if bar.xReplacementField.isNil: 0.0'f32 else: 40.0'f32),
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

proc replacementDidChange(bar: KosmoSearchBar, sender: nimkit.DynamicAgent) {.slot.} =
  discard sender
  bar.replacementPrompt.hidden = bar.xReplacementField.text().len > 0

proc enableReplacement*(
    bar: KosmoSearchBar, onReplace, onReplaceAll: KosmoSearchAction
) =
  ## Add literal replacement controls to an editable search target.
  bar.onReplace = onReplace
  bar.onReplaceAll = onReplaceAll
  let weakBar = bar.unsafeWeakRef()
  let editor = KosmoSearchFieldEditor(searchBar: weakBar, replacement: true)
  editor.initFieldEditorFields()
  discard editor.withProtocol(KosmoSearchEditorMovement)
  discard editor.withProtocol(KosmoSearchEditorActivation)
  discard editor.withProtocol(KosmoSearchEditorCancellation)
  discard editor.withProtocol(KosmoSearchEditorKeyEquivalents)
  let cell = KosmoSearchFieldCell(editor: editor)
  cell.initTextFieldCellFields()
  discard cell.withProtocol(KosmoSearchFieldCellEditing)
  bar.xReplacementField = nimkit.newTextField()
  bar.xReplacementField.setCell(cell)
  bar.xReplacementField.accessibilityLabel = "Replace with (literal text)"
  bar.replacementPrompt = nimkit.newLabel("Replace with")
  bar.replaceButton = nimkit.newButton("Replace")
  bar.replaceAllButton = nimkit.newButton("Replace All")
  bar.replaceButton.accessibilityLabel = "Replace match"
  bar.replaceAllButton.accessibilityLabel = "Replace all matches"
  bar.contentView().addSubview(bar.xReplacementField)
  bar.contentView().addSubview(bar.replacementPrompt)
  bar.contentView().addSubview(bar.replaceButton)
  bar.contentView().addSubview(bar.replaceAllButton)
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

func replacementField*(bar: KosmoSearchBar): nimkit.TextField =
  bar.xReplacementField
