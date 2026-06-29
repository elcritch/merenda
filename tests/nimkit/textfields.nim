import std/[unicode, unittest]

import figdraw/fignodes

import sigils/core

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

const TextFieldGeometryEpsilon = 0.5'f32

type CustomEditorTextFieldCell = ref object of TextFieldCell
  editor: FieldEditor

type TextFieldChangeSpy = ref object of Agent
  changeCount: int

type TextFieldPasteboardProvider = ref object of DynamicAgent
  text: string

protocol TextFieldPasteboardProviderProtocol of PasteboardProviderProtocol:
  method pasteboardTypes(
      provider: TextFieldPasteboardProvider, pasteboard: Pasteboard
  ): seq[string] =
    if provider.text.len > 0:
      result.add PasteboardTypeString

  method stringForPasteboardType(
      provider: TextFieldPasteboardProvider, request: PasteboardTypeRequest
  ): string =
    if request.kind == PasteboardTypeString: provider.text else: ""

  method setStringForPasteboardType(
      provider: TextFieldPasteboardProvider, request: PasteboardStringRequest
  ): bool =
    if request.kind != PasteboardTypeString:
      return false
    provider.text = request.value
    true

  method clearPasteboardContents(
      provider: TextFieldPasteboardProvider, pasteboard: Pasteboard
  ): bool =
    provider.text = ""
    true

proc newTextFieldPasteboardProvider(text: string): TextFieldPasteboardProvider =
  result = TextFieldPasteboardProvider(text: text)
  discard result.withProtocol(TextFieldPasteboardProviderProtocol)

proc rememberTextFieldChange(spy: TextFieldChangeSpy, sender: DynamicAgent) {.slot.} =
  inc spy.changeCount

protocol CustomEditorTextFieldCellProtocol of CellEditingProtocol:
  method fieldEditorForView(
      cell: CustomEditorTextFieldCell, controlView: View
  ): FieldEditor =
    cell.editor

proc newCustomEditorTextFieldCell(editor: FieldEditor): CustomEditorTextFieldCell =
  result = CustomEditorTextFieldCell(editor: editor)
  initTextFieldCellFields(result)
  discard result.withProtocol(CustomEditorTextFieldCellProtocol)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

proc renderedRect(node: Fig): nimkitTypes.Rect =
  nimkitTypes.initRect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

proc containsRect(outer, inner: nimkitTypes.Rect): bool =
  inner.minX >= outer.minX - 0.01'f32 and inner.minY >= outer.minY - 0.01'f32 and
    inner.maxX <= outer.maxX + 0.01'f32 and inner.maxY <= outer.maxY + 0.01'f32

proc checkClose(actual, expected: float32) =
  check abs(actual - expected) <= TextFieldGeometryEpsilon

proc checkRectClose(actual, expected: nimkitTypes.Rect) =
  checkClose(actual.origin.x, expected.origin.x)
  checkClose(actual.origin.y, expected.origin.y)
  checkClose(actual.size.width, expected.size.width)
  checkClose(actual.size.height, expected.size.height)

proc nodeRenderedInView(node: Fig, view: View): bool =
  view.rectToWindow(view.bounds).containsRect(node.renderedRect())

proc renderedTextInView(nodes: openArray[Fig], view: View, text: string): bool =
  for node in nodes:
    if node.kind == nkText and node.renderedText() == text and
        node.nodeRenderedInView(view):
      return true

proc renderedSelectionInView(nodes: openArray[Fig], view: View): bool =
  for node in nodes:
    if node.kind == nkRectangle and node.fill.kind == flColor and
        node.fill.color == initColor(0.24, 0.56, 1.0, 0.34).rgba and
        node.screenBox.w > 1.0 and node.screenBox.h > 0.0 and
        node.nodeRenderedInView(view):
      return true

proc renderedCaretInView(
    nodes: openArray[Fig], view: View, color: nimkitTypes.Color
): bool =
  for node in nodes:
    if node.kind == nkRectangle and node.fill.kind == flColor and
        node.fill.color == color.rgba and abs(node.screenBox.w - 1.0) <= 0.01 and
        node.nodeRenderedInView(view):
      return true

proc renderedFocusRingInView(nodes: openArray[Fig], view: View): bool =
  let viewRect = view.rectToWindow(view.bounds)
  for node in nodes:
    if node.kind == nkRectangle and node.stroke.weight > 1.0 and
        not viewRect.intersection(node.renderedRect()).isEmpty:
      return true

proc renderedFocusRingOutsetsView(nodes: openArray[Fig], view: View): bool =
  let viewRect = view.rectToWindow(view.bounds)
  for node in nodes:
    if node.kind != nkRectangle or node.stroke.weight <= 1.0:
      continue
    let ringRect = node.renderedRect()
    if ringRect.minX < viewRect.minX and ringRect.minY < viewRect.minY and
        ringRect.maxX > viewRect.maxX and ringRect.maxY > viewRect.maxY:
      return true

proc renderedOpaqueBackgroundForView(nodes: openArray[Fig], view: View): bool =
  let viewRect = view.rectToWindow(view.bounds)
  for node in nodes:
    if node.kind == nkRectangle and node.fill.kind == flColor and
        node.fill.color != initColor(0.0, 0.0, 0.0, 0.0).rgba and
        node.renderedRect() == viewRect:
      return true

suite "nimkit text fields":
  test "text fields default to editable selectable first-responder controls":
    let field = newTextField("abc", frame = initRect(0, 0, 120, 24))

    check field.isEditable
    check field.isSelectable
    check field.acceptsFirstResponder
    check field.clipsToBounds
    check field.selectedRange == initTextRange(3, 0)
    check field.insertionPoint == 3

    field.text = "abcd"
    field.alignment = taCenter
    field.editable = false
    field.selectable = false

    check field.text == "abcd"
    check field.stringValue == "abcd"
    check field.alignment == taCenter
    check not field.editable
    check not field.selectable

  test "labels are styled non-editable text fields":
    let
      body = newLabel("Body")
      title = newTitleLabel("Title")
      heading = newHeadingLabel("Heading")
      status = newStatusLabel("Status")
      form = newFormLabel("Name")

    for label in [body, title, heading, status, form]:
      check not label.editable
      check not label.selectable
      check not label.acceptsFirstResponder
      check label.clipsToBounds

    check body.labelStyle == lsBody
    check body.styleClasses == @[LabelStyleClass]
    check body.alignment == taLeft
    check title.labelStyle == lsTitle
    check title.styleClasses == @[LabelStyleClass, LabelTitleStyleClass]
    check title.alignment == taCenter
    check heading.labelStyle == lsHeading
    check heading.styleClasses == @[LabelStyleClass, LabelHeadingStyleClass]
    check status.labelStyle == lsStatus
    check status.styleClasses == @[LabelStyleClass, LabelStatusStyleClass]
    check form.labelStyle == lsForm
    check form.styleClasses == @[LabelStyleClass, LabelFormStyleClass]
    check form.alignment == taRight

    title.labelStyle = lsForm
    check title.labelStyle == lsForm
    check title.styleClasses == @[LabelStyleClass, LabelFormStyleClass]
    check title.alignment == taRight

  test "multiline labels measure and stack to multiple lines":
    let
      root = newView(frame = initRect(0, 0, 240, 120))
      stack = newStackView(laVertical, frame = initRect(0, 0, 220, 120))
      single = newStatusLabel("Kind / Owner / Status")
      multi = newStatusLabel("Kind / Owner / Status\nSelected / Trail")
      singleHeight = single.intrinsicContentSize().height

    stack.spacing = 0.0
    stack.addArrangedSubview(single, multi)
    root.addSubview(stack)
    root.layoutSubtreeIfNeeded()

    check multi.intrinsicContentSize().height > singleHeight
    check singleHeight < 40.0'f32
    check multi.intrinsicContentSize().height < 70.0'f32
    check multi.frame().size.height > single.frame().size.height

  test "first responder text input replaces the current selection":
    let
      window = newWindow("Text input", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abc", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    check window.firstResponder == window.fieldEditor()
    check window.fieldEditorClient() == field
    check field.currentEditor == window.fieldEditor()
    check window.fieldEditor().superview == field
    check field.isEditing
    check field.selectedRange == initTextRange(0, 3)

    check window.dispatchKeyDown(KeyEvent(text: "X", key: keyX, keyCode: keyX.ord))
    check field.stringValue == "X"
    check field.selectedRange == initTextRange(1, 0)

    check window.dispatchKeyDown(KeyEvent(text: "y", key: keyY, keyCode: keyY.ord))
    check field.stringValue == "Xy"
    check field.selectedRange == initTextRange(2, 0)

  test "field editor keeps caret aligned with passive text field text":
    let
      window = newWindow("Text alignment", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("Edit me", frame = initRect(10, 10, 140, 30))

    root.addSubview(field)
    window.setContentView(root)

    let
      style = field.effectiveAppearance().resolveTextFieldStyle(
          controlStyle(srTextField), field.textColor()
        )
      passiveTextRect = style.textFieldTextRect(field.bounds)
      passiveLayout =
        textLayout(passiveTextRect, field.stringValue(), style.text, field.alignment())
      passiveCaret = caretRect(passiveTextRect, passiveLayout, 0)

    check window.makeFirstResponder(field)
    discard window.buildRenders()

    let
      editor = window.fieldEditor()
      activeCaret = editor.layoutManager().caretRect(0)
      activeCaretX = editor.frame().origin.x + activeCaret.origin.x
      activeCaretY = editor.frame().origin.y + activeCaret.origin.y

    check editor.textContainer().insets.top > 0.0'f32
    checkClose(activeCaretX, passiveCaret.origin.x)
    checkClose(activeCaretY, passiveCaret.origin.y)

  test "field editor text rect and accessibility geometry do not shift on focus":
    let
      window = newWindow("Text geometry", frame = initRect(0, 0, 260, 140))
      root = newView(frame = initRect(0, 0, 260, 140))
      field = newTextField("Offset text", frame = initRect(14, 18, 168, 34))

    root.addSubview(field)
    window.setContentView(root)

    let
      passiveTextRect = field.layoutManager().layoutBounds()
      passiveTextRectInWindow = field.rectToWindow(passiveTextRect)
      passiveChar = field.accessibilityBoundsForCharacter(0)
      passiveLine = field.accessibilityBoundsForLine(0)

    check passiveTextRect.origin.x > 0.0'f32
    check passiveTextRectInWindow.containsRect(passiveChar)
    check passiveTextRectInWindow.containsRect(passiveLine)
    check passiveLine.containsRect(passiveChar)

    check window.makeFirstResponder(field)
    discard window.buildRenders()

    let
      editor = window.fieldEditor()
      activeChar = field.accessibilityBoundsForCharacter(0)
      activeLine = field.accessibilityBoundsForLine(0)

    checkRectClose(editor.frame(), passiveTextRect)
    check editor.textContainer().insets.top > 0.0'f32
    check passiveTextRectInWindow.containsRect(activeChar)
    check passiveTextRectInWindow.containsRect(activeLine)
    check not activeChar.isEmpty
    check not activeLine.isEmpty
    check field.accessibilityCharacterIndexAtPoint(
      initPoint(
        passiveChar.origin.x + passiveChar.size.width * 0.5'f32,
        passiveChar.origin.y + passiveChar.size.height * 0.5'f32,
      )
    ) == 0
    check field.accessibilityCharacterIndexAtPoint(
      initPoint(
        activeChar.origin.x + activeChar.size.width * 0.5'f32,
        activeChar.origin.y + activeChar.size.height * 0.5'f32,
      )
    ) == 0

  test "field editor exposes text input client geometry and command dispatch":
    let
      window = newWindow("Field editor input client", frame = initRect(0, 0, 260, 140))
      root = newView(frame = initRect(0, 0, 260, 140))
      field = newTextField("abcdef", frame = initRect(14, 18, 168, 34))
      spy = TextFieldChangeSpy()

    field.connect(textDidChange, spy, rememberTextFieldChange)
    root.addSubview(field)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    let
      editor = window.fieldEditor()
      textView = TextView(editor)
      textRectInWindow = field.rectToWindow(field.layoutManager().layoutBounds())

    textView.selectedRange = initTextRange(3, 0)
    let
      substring = textView.attributedSubstringForRange(initTextRange(1, 2))
      firstRect = textView.firstRectForCharacterRange(initTextRange(3, 1))
      hitIndex = textView.characterIndexForPoint(
        initPoint(
          firstRect.origin.x + firstRect.size.width * 0.5'f32,
          firstRect.origin.y + firstRect.size.height * 0.5'f32,
        )
      )

    check editor.superview == field
    check textRectInWindow.containsRect(firstRect)
    check substring.stringValue() == "bc"
    check hitIndex == 3
    check not textView.hasMarkedText
    check textView.markedRange == initTextRange(0, 0)
    check "fontSize" in textView.validAttributesForMarkedText()

    doCommandBySelector(
      Responder(editor), deleteToBeginningOfLine(), DynamicAgent(editor)
    )

    check field.stringValue == "def"
    check field.selectedRange == initTextRange(0, 0)
    check field.currentEditor == editor
    check window.firstResponder == editor
    check spy.changeCount == 1

  test "window-backed field editor renders live text before blur":
    let
      window = newWindow("Text field render", frame = initRect(0, 0, 420, 220))
      root = newView(frame = initRect(0, 0, 420, 220))
      title = newTitleLabel("Text Field", frame = initRect(28, 24, 240, 28))
      field = newTextField("Edit me", frame = initRect(28, 70, 240, 30))
      secondField = newTextField("Tab here", frame = initRect(28, 112, 240, 30))
      status =
        newStatusLabel("Values: Edit me / Tab here", frame = initRect(28, 154, 320, 24))

    root.addSubviews(autoNames(title, field, secondField, status))
    window.setContentView(root)

    check window.makeFirstResponder(field)
    let focusedNodes = window.buildRenders()[DefaultDrawLevel].nodes
    check focusedNodes.renderedSelectionInView(field)
    check focusedNodes.renderedFocusRingInView(field)
    check focusedNodes.renderedFocusRingOutsetsView(field)

    check window.dispatchKeyDown(KeyEvent(text: "X", key: keyX, keyCode: keyX.ord))
    let editedNodes = window.buildRenders()[DefaultDrawLevel].nodes
    check editedNodes.renderedTextInView(field, "X")
    check editedNodes.renderedCaretInView(field, field.textColor())
    check editedNodes.renderedFocusRingInView(field)
    check editedNodes.renderedFocusRingOutsetsView(field)

  test "field editor does not paint an opaque background over text field chrome":
    let
      window = newWindow("Field editor chrome", frame = initRect(0, 0, 420, 180))
      root = newView(frame = initRect(0, 0, 420, 180))
      field = newTextField("Edit me", frame = initRect(28, 44, 240, 30))

    root.addSubview(field)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(40, 58))
    check field.isFocused
    check not field.isFocusVisible
    let editor = window.fieldEditor()
    check editor.superview == field

    let nodes = window.buildRenders()[DefaultDrawLevel].nodes
    check not nodes.renderedOpaqueBackgroundForView(editor)

  test "tabbing through field editor keeps constrained showcase layout stretched":
    let
      window = newWindow("Controls Showcase", frame = initRect(0, 0, 760, 500))
      root = newView()
      layout = newStackView(laVertical)
      bodyRow = newStackView(laHorizontal)
      inputColumn = newStackView(laVertical)
      buttonRow = newStackView(laHorizontal)
      choiceColumn = newStackView(laVertical)
      popupColumn = newStackView(laVertical)
      title = newTitleLabel("Nimkit Controls")
      summary = newStatusLabel("/ Building UI / Toggle: Off")
      inputTitle = newHeadingLabel("Text Fields")
      nameField = newTextField("")
      noteField = newTextField("Building UI")
      actionTitle = newHeadingLabel("Buttons")
      pushButton = newButton("Push")
      toggleButton = newButton("Toggle Off")
      actionCountLabel = newStatusLabel("Push count: 0")
      choiceTitle = newHeadingLabel("Choices")
      downloads = newCheckBox("Enable downloads")
      notifications = newCheckBox("Show notifications")
      sync = newCheckBox("Sync over cellular")
      sizeTitle = newHeadingLabel("Radio Buttons")
      small = newRadioButton("Small")
      medium = newRadioButton("Medium")
      large = newRadioButton("Large")
      popupTitle = newHeadingLabel("Combo Boxes")
      priority = newComboBox(["Low", "Medium", "High"])
      color = newComboBox(["Red", "Green", "Blue"])

    root.background = initColor(0.95, 0.96, 0.98)
    layout.spacing = 16.0
    layout.alignment = svaFill
    bodyRow.spacing = 28.0
    bodyRow.alignment = svaFill
    bodyRow.distribution = svdFill
    for column in [inputColumn, choiceColumn, popupColumn]:
      column.spacing = 10.0
      column.alignment = svaFill
    popupColumn.distribution = svdNatural
    buttonRow.spacing = 8.0
    buttonRow.alignment = svaFill
    buttonRow.distribution = svdFillEqually

    buttonRow.addArrangedSubview(pushButton, toggleButton)
    inputColumn.addArrangedSubview(
      inputTitle, nameField, noteField, actionTitle, buttonRow, actionCountLabel
    )
    inputColumn.addFlexibleSpacer()
    choiceColumn.addArrangedSubview(
      choiceTitle, downloads, notifications, sync, sizeTitle, small, medium, large
    )
    choiceColumn.addFlexibleSpacer()
    popupColumn.addArrangedSubview(popupTitle, priority, color)
    bodyRow.addArrangedSubview(inputColumn, choiceColumn, popupColumn)
    layout.addArrangedSubview(title, bodyRow, summary)

    root.addSubview(layout)
    layout.pinEdges(
      toGuide = root.contentLayoutGuide(insets(22.0, 24.0, 0.0, 24.0)),
      edges = {leLeft, leTop, leRight},
    )
    window.setContentView(root)
    check window.makeFirstResponder(nameField)
    root.frame = initRect(0, 0, 760, 500)

    discard window.buildRenders()
    let stretchedWidth = layout.frame.size.width
    check stretchedWidth > 700.0'f32
    check title.frame.size.width == stretchedWidth
    check summary.frame.size.width == stretchedWidth

    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    discard window.buildRenders()

    check layout.frame.size.width == stretchedWidth
    check title.frame.size.width == stretchedWidth
    check summary.frame.size.width == stretchedWidth

    check not root.needsUpdateConstraints
    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponder == toggleButton
    check not root.needsUpdateConstraints
    discard window.buildRenders()
    check layout.frame.size.width == stretchedWidth
    check title.frame.size.width == stretchedWidth
    check summary.frame.size.width == stretchedWidth

  test "insertText respects text field editability":
    let field = newTextField("abc", frame = initRect(0, 0, 120, 24))

    field.editable = false
    discard field.send(insertText(), "x")
    check field.stringValue == "abc"
    check field.selectedRange == initTextRange(3, 0)

    field.editable = true
    discard field.send(insertText(), "x")
    check field.stringValue == "abcx"
    check field.selectedRange == initTextRange(4, 0)

  test "default edit commands move and delete text":
    let
      window = newWindow("Text commands", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.selectedRange = initTextRange(3, 0)
    check window.dispatchKeyDown(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    check field.stringValue == "abdef"
    check field.selectedRange == initTextRange(2, 0)

    check window.dispatchKeyDown(KeyEvent(key: keyDelete, keyCode: keyDelete.ord))
    check field.stringValue == "abef"
    check field.selectedRange == initTextRange(2, 0)

    check window.dispatchKeyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check field.selectedRange == initTextRange(1, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift})
    )
    check field.selectedRange == initTextRange(1, 1)

    check window.dispatchKeyDown(KeyEvent(text: "Z", key: keyZ, keyCode: keyZ.ord))
    check field.stringValue == "aZef"
    check field.selectedRange == initTextRange(2, 0)

  test "macOS profile moves and deletes by word":
    let
      window = newWindow("Text word commands", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("one two three", frame = initRect(10, 10, 180, 24))

    window.setKeyBindingProfile(kbpMacOS)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.selectedRange = initTextRange(0, 0)
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmOption})
    )
    check field.selectedRange == initTextRange(3, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmOption})
    )
    check field.selectedRange == initTextRange(7, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord, modifiers: {kmOption})
    )
    check field.selectedRange == initTextRange(4, 0)

    check window.dispatchKeyDown(
      KeyEvent(
        key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift, kmOption}
      )
    )
    check field.selectedRange == initTextRange(4, 3)

    field.selectedRange = initTextRange(field.stringValue.len, 0)
    check window.dispatchKeyDown(
      KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord, modifiers: {kmOption})
    )
    check field.stringValue == "one two "
    check field.selectedRange == initTextRange(8, 0)

  test "windows profile uses control arrows for word movement":
    let
      window = newWindow("Text windows word commands", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("one two", frame = initRect(10, 10, 180, 24))

    window.setKeyBindingProfile(kbpWindows)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)

    field.selectedRange = initTextRange(0, 0)
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmControl})
    )
    check field.selectedRange == initTextRange(3, 0)

    check window.dispatchKeyDown(
      KeyEvent(
        key: keyArrowRight, keyCode: keyArrowRight.ord, modifiers: {kmShift, kmControl}
      )
    )
    check field.selectedRange == initTextRange(3, 4)

  test "control character text input after command shortcuts is ignored":
    let
      window = newWindow("Text control input", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 180, 24))

    window.setKeyBindingProfile(kbpMacOS)
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)
    field.selectedRange = initTextRange(6, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: {kmControl})
    )
    check field.selectedRange == initTextRange(0, 0)

    discard window.dispatchKeyDown(KeyEvent(text: "\x01", keyCode: 0))
    check field.stringValue == "abcdef"
    check field.selectedRange == initTextRange(0, 0)

  test "select all shortcut selects and replaces the full value":
    let
      window = newWindow("Text select all", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)
    field.selectedRange = initTextRange(2, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: shortcutModifiers())
    )
    check field.selectedRange == initTextRange(0, 6)

    check window.dispatchKeyDown(KeyEvent(text: "q", key: keyQ, keyCode: keyQ.ord))
    check field.stringValue == "q"
    check field.selectedRange == initTextRange(1, 0)

  test "paste shortcut inserts provider-backed general pasteboard text":
    let
      pasteboard = generalPasteboard()
      previousProvider = pasteboard.provider
      provider = newTextFieldPasteboardProvider("clip")
      window = newWindow("Text paste", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("az", frame = initRect(10, 10, 140, 24))

    pasteboard.provider = nil
    pasteboard.clearContents()
    pasteboard.provider = provider
    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field)
    field.selectedRange = initTextRange(1, 0)

    check window.dispatchKeyDown(
      KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: shortcutModifiers())
    )
    check field.stringValue == "aclipz"
    check field.selectedRange == initTextRange(5, 0)

    pasteboard.provider = nil
    pasteboard.clearContents()
    pasteboard.provider = previousProvider

  test "mouse down focuses text field and places caret at clicked position":
    let
      window = newWindow("Text mouse", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abcdef", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check window.firstResponder == window.fieldEditor()
    check window.fieldEditorClient() == field
    check field.currentEditor == window.fieldEditor()
    check window.fieldEditor().superview == field
    check field.isFocused
    check not field.isFocusVisible
    check field.isEditing
    check field.selectedRange == initTextRange(1, 0)

    check window.makeFirstResponder(field)
    check window.firstResponder == window.fieldEditor()
    check field.isFocused
    check field.isFocusVisible
    check window.fieldEditor().isFocusVisible

    check window.mouseDownAt(initPoint(30, 20))
    check window.firstResponder == window.fieldEditor()
    check window.fieldEditorClient() == field
    check field.currentEditor == window.fieldEditor()
    check window.fieldEditor().superview == field
    check field.isFocused
    check not field.isFocusVisible
    check not window.fieldEditor().isFocusVisible
    check field.isEditing

  test "return ends field editor editing and sends text field action":
    let
      window = newWindow("Text return", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abc", frame = initRect(10, 10, 140, 24))
      action = actionSelector("textFieldReturnAction")

    var actionCount = 0

    proc onReturn(sender: DynamicAgent) =
      check sender == DynamicAgent(field)
      inc actionCount

    field.target = newActionTarget(action, onReturn)
    field.action = action
    root.addSubview(field)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    check window.firstResponder == window.fieldEditor()
    check window.fieldEditor().superview == field
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check actionCount == 1
    check not field.isEditing
    check field.currentEditor.isNil
    check window.fieldEditor().superview.isNil
    check not field.isFocused
    check window.firstResponder != window.fieldEditor()

  test "validateEditing syncs field editor text without ending editing":
    let
      window = newWindow("Validate editing", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abc", frame = initRect(10, 10, 140, 24))
      spy = TextFieldChangeSpy()

    field.connect(textDidChange, spy, rememberTextFieldChange)
    root.addSubview(field)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    let editor = field.currentEditor
    check editor == window.fieldEditor()

    TextView(editor).insertTextValue("draft")
    check spy.changeCount == 0
    check field.validateEditing()
    check spy.changeCount == 1
    check field.currentEditor == editor
    check window.firstResponder == editor
    check field.stringValue == "draft"

  test "abortEditing cancels field editor text and clears first responder":
    let
      window = newWindow("Abort editing", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abc", frame = initRect(10, 10, 140, 24))

    root.addSubview(field)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    let editor = field.currentEditor
    TextView(editor).insertTextValue("draft")

    check field.abortEditing()
    check field.stringValue == "abc"
    check field.currentEditor.isNil
    check editor.superview.isNil
    check window.firstResponder.isNil

  test "sendsActionOnEndEditing sends action before tab key-view movement":
    let
      window = newWindow("End editing action", frame = initRect(0, 0, 260, 120))
      root = newView(frame = initRect(0, 0, 260, 120))
      first = newTextField("one", frame = initRect(10, 10, 100, 24))
      second = newTextField("two", frame = initRect(10, 44, 100, 24))
      action = actionSelector("textFieldEndEditingAction")

    var actionCount = 0

    proc onEndEditing(sender: DynamicAgent) =
      check sender == DynamicAgent(first)
      inc actionCount

    first.textFieldCell().setSendsActionOnEndEditing(true)
    first.target = newActionTarget(action, onEndEditing)
    first.action = action
    root.addSubview(first)
    root.addSubview(second)
    window.setContentView(root)

    check window.makeFirstResponder(first)
    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check actionCount == 1
    check window.fieldEditorClient() == second

  test "text field cells can provide a custom field editor":
    let
      window = newWindow("Custom editor", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      field = newTextField("abc", frame = initRect(10, 10, 140, 24))
      customEditor = newFieldEditor()
      customCell = newCustomEditorTextFieldCell(customEditor)

    field.setCell(customCell)
    root.addSubview(field)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    check window.firstResponder == customEditor
    check window.fieldEditorClient() == field
    check field.currentEditor == customEditor
    check customEditor.superview == field
    check customEditor.selectedRange == initTextRange(0, 3)
