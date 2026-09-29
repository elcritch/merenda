## Shared floating search controls for Kosmo content views.

import std/[options, strutils, unicode]

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
    xReplacementVisible: bool
    disclosureButton: nimkit.Button
    expressionButton: nimkit.Button
    xRegularExpression, xHasMatches: bool
    errorLabel: nimkit.Label
    xErrorMessage: string
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
    if not editor.searchBar.isNil and event.key == nimkit.keyF:
      if event.modifiers == nimkit.shortcutModifiers():
        return editor.searchBar[].focusSearch(replacing = false)
      if event.modifiers == nimkit.shortcutModifiers() + {nimkit.kmOption}:
        return editor.searchBar[].focusSearch(replacing = true)
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
      expressionWidth = if bar.expressionButton.isNil: 0.0'f32 else: 40.0'f32
      buttonsWidth = buttonWidth * 3.0'f32 + SearchControlSpacing * 3.0'f32
      fieldWidth =
        max(availableWidth - buttonsWidth - fieldX - expressionWidth, 1.0'f32)
      controlY = max((availableHeight - controlHeight) * 0.5'f32, 0.0'f32)
      firstButtonX = fieldX + fieldWidth + expressionWidth + SearchControlSpacing
    bar.contentView().setFrameFromLayout(contentFrame)
    if not bar.disclosureButton.isNil:
      bar.disclosureButton.setFrameFromLayout(
        nimkit.rect(0, controlY, disclosureWidth, controlHeight)
      )
    bar.xQueryField.setFrameFromLayout(
      nimkit.rect(fieldX, controlY, fieldWidth, controlHeight)
    )
    if not bar.expressionButton.isNil:
      bar.expressionButton.setFrameFromLayout(
        nimkit.rect(
          fieldX + fieldWidth + SearchControlSpacing, controlY, 34, controlHeight
        )
      )
    if bar.xErrorMessage.len > 0:
      bar.errorLabel.setFrameFromLayout(
        nimkit.rect(0, (if bar.xReplacementVisible: 80 else: 40), availableWidth, 18)
      )
    bar.promptLabel.setFrameFromLayout(
      nimkit.rect(
        fieldX + 10, controlY, max(fieldWidth - 20.0'f32, 1.0'f32), controlHeight
      )
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

    if bar.xReplacementVisible:
      let y = controlY + 40.0'f32
      let actionWidth = min(90.0'f32, availableWidth / 3)
      let replacementWidth =
        max(availableWidth - fieldX - 2 * (actionWidth + SearchControlSpacing), 1)
      bar.xReplacementField.setFrameFromLayout(
        nimkit.rect(fieldX, y, replacementWidth, controlHeight)
      )
      bar.replacementPrompt.setFrameFromLayout(
        nimkit.rect(fieldX + 10, y, max(replacementWidth - 20, 1), controlHeight)
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
  result.contentView().addSubview(result.promptLabel)
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
    bar.promptLabel.hidden = query.len > 0

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
  bar.expressionButton = nimkit.newButton(".*")
  bar.expressionButton.buttonType = nimkit.btToggle
  bar.expressionButton.accessibilityLabel = "Use Reni regular expressions"
  bar.expressionButton.toolTip = "Use Reni expressions and replacement captures"
  bar.contentView().addSubview(bar.expressionButton)
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
  bar.replacementPrompt.hidden = not visible or bar.xReplacementField.text().len > 0
  bar.replaceButton.hidden = not visible
  bar.replaceAllButton.hidden = not visible
  bar.disclosureButton.title = if visible: "⌄" else: "›"
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
  bar.replacementPrompt.hidden =
    not bar.xReplacementVisible or bar.xReplacementField.text().len > 0
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
  bar.disclosureButton = nimkit.newButton("›")
  bar.replaceButton.accessibilityLabel = "Replace match"
  bar.replaceAllButton.accessibilityLabel = "Replace all matches"
  bar.contentView().addSubview(bar.xReplacementField)
  bar.contentView().addSubview(bar.replacementPrompt)
  bar.contentView().addSubview(bar.replaceButton)
  bar.contentView().addSubview(bar.replaceAllButton)
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
