import sigils/core

import ./cells
import ../accessibility/accessibility
import ../app/dragging
import ../app/pasteboards
import ../text/fieldeditors
import ../foundation/events
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types
import ../view/views
import ../app/windows

export cells, objectvalues, views

type
  Control* = ref object of View
    xCell: Cell
    xTarget: DynamicAgent
    xAction: ActionSelector
    xCurrentEditor: FieldEditor
    xDraggingSession: DraggingSession
    xObjectValue: ObjectValue
    xObjectValueFormatter: DynamicAgent
    xObjectFormatContext: ObjectFormatContext
    xObjectParseContext: ObjectParseContext
    xValidationError: ObjectValidationError

  ActionProc* = proc(sender: DynamicAgent) {.closure.}

  ClosureTarget* = ref object of Responder
    xCallback: ActionProc

protocol ControlEvents:
  proc actionDidSend*(control: Control, sender: DynamicAgent) {.signal.}
  proc objectValueDidChange*(
    control: Control, sender: DynamicAgent, value: ObjectValue
  ) {.signal.}

  proc validationDidChange*(
    control: Control, sender: DynamicAgent, error: ObjectValidationError
  ) {.signal.}

  proc invalidObjectValueEdit*(
    control: Control, sender: DynamicAgent, error: ObjectValidationError
  ) {.signal.}

protocol ControlValueHooks {.selectorScope: protocol.}:
  method validateValue*(
    control: Control, value: ObjectValue
  ): ObjectValidationError {.optional.}

  method shouldCommitValue*(control: Control, value: ObjectValue): bool {.optional.}

  method didFailValue*(control: Control, error: ObjectValidationError) {.optional.}

  method didCommitValue*(control: Control, value: ObjectValue) {.optional.}

proc cell*(control: Control): Cell
proc setCell*(control: Control, cell: Cell)
proc selectedCell*(control: Control): Cell
proc currentEditor*(control: Control): FieldEditor
proc setCurrentEditor*(control: Control, editor: FieldEditor)
proc target*(control: Control): DynamicAgent
proc action*(control: Control): ActionSelector
proc draggingSession*(control: Control): DraggingSession
proc clearValidationError*(control: Control)
proc setValidationError*(control: Control, error: ObjectValidationError)
proc hasValidationError*(control: Control): bool
proc validationError*(control: Control): ObjectValidationError
proc rejectObjectValueEdit*(control: Control, error: ObjectValidationError): bool
proc setObjectValue*(control: Control, value: ObjectValue, notify = false)
proc validateObjectValueForWriteback*(control: Control, value: ObjectValue): bool

proc controlIntrinsicContentSize(control: Control): IntrinsicSize =
  let controlCell = control.cell()
  if controlCell.isNil:
    NoIntrinsicContentSize
  else:
    controlCell.cellSize()

proc invalidateCellMetrics(control: Control) =
  control.invalidateIntrinsicContentSize()
  control.setNeedsDisplay(true)

proc syncActionCell(control: Control, cell: Cell) =
  if control.isNil or cell.isNil or not (cell of ActionCell):
    return
  let actionCell = ActionCell(cell)
  actionCell.setTarget(control.xTarget)
  actionCell.setAction(control.xAction)

proc defaultControlCell(): Cell =
  newActionCell()

protocol ControlProtocol from Control:
  method isEnabled*(self: Control): bool =
    self.cell().isEnabled()

  method setEnabled*(self: Control, enabled: bool) =
    if self.isNil:
      return
    self.cell().setEnabled(enabled)

  method canBecomeKeyView*(self: Control): bool =
    self.isEnabled() and View(self).viewCanBecomeKeyView()

  method shouldBecomeFirstResponder*(self: Control): bool =
    self.isEnabled() and self.acceptsFirstResponder()

  method layoutIntrinsicContentSize*(self: Control): IntrinsicSize =
    self.controlIntrinsicContentSize()

  method sendAction*(self: Control): bool =
    var handled = false
    let target = self.target()
    if not target.isNil:
      handled =
        target.sendLocalIfHandled(self.action(), ActionArgs(sender: DynamicAgent(self)))
    else:
      let owner = self.window()
      if owner of Window:
        handled = Window(owner).sendAction(self.action(), DynamicAgent(self))
    emit self.actionDidSend(DynamicAgent(self))
    handled

  method validateEditing*(self: Control): bool =
    let editor = self.currentEditor()
    editor.isNil or editor.validateEditing()

  method abortEditing*(self: Control): bool =
    let editor = self.currentEditor()
    if editor.isNil:
      return false
    result = editor.cancelEditing()
    if result:
      let owner = self.window()
      if owner of Window and Window(owner).firstResponder() == editor:
        discard Window(owner).makeFirstResponder(nil)

proc acceptsDraggingInfo(control: Control, info: DraggingInfo): bool =
  if control.isNil or info.pasteboard.isNil:
    return false
  let acceptedTypes = control.registeredDraggedTypes()
  acceptedTypes.len > 0 and info.pasteboard.availableTypeFromArray(acceptedTypes).len > 0

protocol DefaultControlDraggingSource of DraggingSourceProtocol:
  method draggingSourceOperationMask(
      control: Control, info: DraggingInfo
  ): DragOperations =
    if control.isNil: NoDragOperations else: info.allowedOperations

  method draggingSessionEnded(control: Control, info: DraggingInfo) =
    if not control.isNil and control.xDraggingSession == info.session:
      control.xDraggingSession = nil

protocol DefaultControlDraggingDestination of DraggingDestinationProtocol:
  method draggingEntered(control: Control, info: DraggingInfo): DragOperations =
    if control.acceptsDraggingInfo(info): info.allowedOperations else: NoDragOperations

  method draggingUpdated(control: Control, info: DraggingInfo): DragOperations =
    if control.acceptsDraggingInfo(info): info.allowedOperations else: NoDragOperations

  method prepareForDragOperation(control: Control, info: DraggingInfo): bool =
    control.acceptsDraggingInfo(info)

  method performDragOperation(control: Control, info: DraggingInfo): bool =
    control.acceptsDraggingInfo(info)

proc enabled*(control: Control): bool =
  (not control.isNil) and control.isEnabled()

proc `enabled=`*(control: Control, enabled: bool) =
  if not control.isNil:
    control.setEnabled(enabled)

proc cellForwardingTarget*(control: Control, selector: SigilName): DynamicAgent =
  let controlCell = control.xCell
  if not controlCell.isNil and controlCell.respondsTo(selector):
    return DynamicAgent(controlCell)

proc installCellForwarding(control: Control) =
  control.setForwardingTarget(
    proc(self: DynamicAgent, selector: SigilName): DynamicAgent =
      cellForwardingTarget(Control(self), selector)
  )

proc intrinsicContentSize*(control: Control): IntrinsicSize =
  control.controlIntrinsicContentSize()

proc sizeThatFits*(control: Control, proposedSize: FittingSize): Size =
  let controlCell = control.cell()
  if controlCell.isNil:
    return control.bounds().size.constrainSize(proposedSize)

  let naturalSize = controlCell.cellSize().resolveIntrinsicSize(control.bounds().size)
  if not proposedSize.hasWidth and not proposedSize.hasHeight:
    return naturalSize

  let fittingBounds = initRect(
    0.0,
    0.0,
    if proposedSize.hasWidth: proposedSize.width else: naturalSize.width,
    if proposedSize.hasHeight: proposedSize.height else: naturalSize.height,
  )
  controlCell.cellSizeForBounds(fittingBounds)

proc sizeThatFits*(control: Control): Size =
  control.sizeThatFits(UnconstrainedFittingSize)

proc sizeThatFits*(control: Control, proposedSize: Size): Size =
  control.sizeThatFits(initFittingSize(proposedSize))

proc sizeToFit*(control: Control) =
  let frame = control.frame()
  control.setFrame(
    initRect(frame.origin, control.sizeThatFits(UnconstrainedFittingSize))
  )

proc initControlFields*(control: Control, frame: Rect = AutoRect, cell: Cell = nil) =
  initViewFields(control, frame)
  control.background = initColor(0.0, 0.0, 0.0, 0.0)
  control.xObjectValue = emptyObjectValue()
  control.xObjectFormatContext = initObjectFormatContext()
  control.xObjectParseContext = initObjectParseContext()
  control.setHuggingPriority(LayoutPriorityRequired, laVertical)
  control.installCellForwarding()
  control.setCell(
    if cell.isNil:
      defaultControlCell()
    else:
      cell
  )
  discard control.withProto()
  discard control.withProtocol(DefaultControlDraggingSource)
  discard control.withProtocol(DefaultControlDraggingDestination)

proc cell*(control: Control): Cell =
  if control.xCell.isNil:
    control.setCell(newActionCell())
  control.xCell

proc setCell*(control: Control, cell: Cell) =
  if control.xCell == cell:
    control.syncActionCell(cell)
    return
  let oldCell = control.xCell
  if not oldCell.isNil and oldCell.controlView() == View(control):
    oldCell.setControlView(nil)
  control.xCell = cell
  control.syncActionCell(control.xCell)
  if not control.xCell.isNil:
    control.xCell.setControlView(control)
  control.invalidateCellMetrics()

proc selectedCell*(control: Control): Cell =
  control.cell()

proc currentEditor*(control: Control): FieldEditor =
  if control.isNil or control.xCurrentEditor.isNil:
    return nil
  let owner = control.window()
  if owner of Window and Window(owner).firstResponder() == control.xCurrentEditor:
    control.xCurrentEditor
  else:
    nil

proc activeEditor*(control: Control): FieldEditor =
  if control.isNil: nil else: control.xCurrentEditor

proc setCurrentEditor*(control: Control, editor: FieldEditor) =
  if not control.isNil:
    control.xCurrentEditor = editor

proc target*(control: Control): DynamicAgent =
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    return ActionCell(selected).target()
  control.xTarget

proc `target=`*(control: Control, target: DynamicAgent) =
  control.xTarget = target
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    ActionCell(selected).setTarget(target)

proc `target=`*(control: Control, target: Responder) =
  control.target = DynamicAgent(target)

proc action*(control: Control): ActionSelector =
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    return ActionCell(selected).action()
  control.xAction

proc `action=`*(control: Control, action: ActionSelector) =
  control.xAction = action
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    ActionCell(selected).setAction(action)

proc draggingSession*(control: Control): DraggingSession =
  if control.isNil: nil else: control.xDraggingSession

proc objectValue*(control: Control): ObjectValue =
  if control.isNil:
    nilObjectValue()
  else:
    control.xObjectValue

proc objectValueFormatter*(control: Control): DynamicAgent =
  if control.isNil: nil else: control.xObjectValueFormatter

proc `objectValueFormatter=`*(control: Control, formatter: DynamicAgent) =
  if not control.isNil:
    control.xObjectValueFormatter = formatter

proc `objectValueFormatter=`*(control: Control, formatter: Responder) =
  control.objectValueFormatter = DynamicAgent(formatter)

proc objectFormatContext*(control: Control): ObjectFormatContext =
  if control.isNil:
    initObjectFormatContext()
  else:
    control.xObjectFormatContext

proc `objectFormatContext=`*(control: Control, context: ObjectFormatContext) =
  if not control.isNil:
    control.xObjectFormatContext = context

proc objectParseContext*(control: Control): ObjectParseContext =
  if control.isNil:
    initObjectParseContext()
  else:
    control.xObjectParseContext

proc `objectParseContext=`*(control: Control, context: ObjectParseContext) =
  if not control.isNil:
    control.xObjectParseContext = context

proc formatObjectValue*(
    control: Control, value: ObjectValue, role = ovrDefault
): string =
  if control.isNil:
    return value.formatObjectValue(initObjectFormatContext(role = role))
  let context = control.xObjectFormatContext.withRole(role)
  control.xObjectValueFormatter.formatObjectValue(value, context)

proc formattedObjectValue*(control: Control, role = ovrDefault): string =
  if control.isNil:
    return ""
  control.formatObjectValue(control.xObjectValue, role)

proc parseEditedObjectValue*(
    control: Control, text: string, role = ovrTextField
): ObjectParseResult =
  if control.isNil:
    return parseObjectValue(text, initObjectParseContext(role = role))
  let context = control.xObjectParseContext.withRole(role)
  control.xObjectValueFormatter.parseObjectValue(text, context)

proc validationError*(control: Control): ObjectValidationError =
  if control.isNil:
    initObjectValidationError()
  else:
    control.xValidationError

proc hasValidationError*(control: Control): bool =
  not control.validationError().valid()

proc setValidationError*(control: Control, error: ObjectValidationError) =
  if control.isNil:
    return
  let wasInvalid = control.hasValidationError()
  control.xValidationError = error
  let message =
    if error.failed():
      error.displayMessage()
    else:
      ""
  View(control).validationMessage = message
  let isInvalid = control.hasValidationError()
  if wasInvalid != isInvalid or error.message.len > 0:
    control.postAccessibilityNotification(anValueChanged)
  emit control.validationDidChange(DynamicAgent(control), error)

proc clearValidationError*(control: Control) =
  control.setValidationError(initObjectValidationError())

proc sendValueFailure(control: Control, error: ObjectValidationError) =
  let target = control.target()
  if not target.isNil:
    discard target.sendLocalIfHandled(didFailValue(), (control: control, error: error))
  discard DynamicAgent(control).sendLocalIfHandled(
      didFailValue(), (control: control, error: error)
    )

proc sendValueCommit(control: Control, value: ObjectValue) =
  let target = control.target()
  if not target.isNil:
    discard
      target.sendLocalIfHandled(didCommitValue(), (control: control, value: value))
  discard DynamicAgent(control).sendLocalIfHandled(
      didCommitValue(), (control: control, value: value)
    )

proc rejectObjectValueEdit*(control: Control, error: ObjectValidationError): bool =
  if control.isNil:
    return false
  control.setValidationError(error)
  control.sendValueFailure(error)
  emit control.invalidObjectValueEdit(DynamicAgent(control), error)
  false

proc validateWithTarget(
    target: DynamicAgent, control: Control, value: ObjectValue
): ObjectValidationError =
  if target.isNil:
    return initObjectValidationError()
  let error = target.trySendLocal(validateValue(), (control: control, value: value))
  if error.isSome:
    return error.get()
  initObjectValidationError()

proc shouldCommitWithTarget(
    target: DynamicAgent, control: Control, value: ObjectValue
): Option[bool] =
  if target.isNil:
    return none(bool)
  target.trySendLocal(shouldCommitValue(), (control: control, value: value))

proc validateObjectValueForWriteback*(control: Control, value: ObjectValue): bool =
  if control.isNil:
    return false
  if value.kind == ovValidationFailure:
    return control.rejectObjectValueEdit(value.validationError)

  let target = control.target()
  let targetError = validateWithTarget(target, control, value)
  if targetError.failed():
    return control.rejectObjectValueEdit(targetError)

  let selfError = validateWithTarget(DynamicAgent(control), control, value)
  if selfError.failed():
    return control.rejectObjectValueEdit(selfError)

  let targetAllowed = shouldCommitWithTarget(target, control, value)
  if targetAllowed.isSome and not targetAllowed.get():
    return control.rejectObjectValueEdit(
      initObjectValidationError(
        oveRejected,
        message = "Value was rejected",
        expectedKind = value.kind,
        actualKind = value.kind,
      )
    )

  let selfAllowed = shouldCommitWithTarget(DynamicAgent(control), control, value)
  if selfAllowed.isSome and not selfAllowed.get():
    return control.rejectObjectValueEdit(
      initObjectValidationError(
        oveRejected,
        message = "Value was rejected",
        expectedKind = value.kind,
        actualKind = value.kind,
      )
    )

  control.clearValidationError()
  true

proc setObjectValue*(control: Control, value: ObjectValue, notify = false) =
  if control.isNil:
    return
  let changed = control.xObjectValue != value
  control.xObjectValue = value
  control.clearValidationError()
  if changed:
    emit control.objectValueDidChange(DynamicAgent(control), value)
    control.sendValueCommit(value)
    if notify:
      discard control.sendAction()

proc `objectValue=`*(control: Control, value: ObjectValue) =
  control.setObjectValue(value)

proc commitEditedObjectText*(
    control: Control, text: string, role = ovrTextField, notify = false
): bool =
  if control.isNil:
    return false
  let parsed = control.parseEditedObjectValue(text, role)
  if parsed.failed():
    return control.rejectObjectValueEdit(parsed.error)
  if not control.validateObjectValueForWriteback(parsed.value):
    return false
  control.setObjectValue(parsed.value, notify)
  true

proc beginDraggingItems*(
    control: Control,
    items: openArray[DraggingItem],
    allowedOperations = EveryDragOperation,
    pasteboardName = DragPasteboardName,
): DraggingSession =
  if control.isNil:
    return nil
  result = beginDraggingSession(
    DynamicAgent(control), items, allowedOperations, pasteboardName
  )
  control.xDraggingSession = result

proc updateDragging*(
    control: Control,
    event: MouseEvent,
    destination: DynamicAgent = nil,
    dropTarget = initDraggingDropTarget(),
): DragOperations =
  if control.isNil or control.xDraggingSession.isNil:
    return NoDragOperations
  updateDraggingSession(
    control.xDraggingSession,
    event.location,
    if destination.isNil:
      DynamicAgent(control)
    else:
      destination,
    dropTarget,
  )

proc autoscrollDragging*(
    control: Control,
    event: MouseEvent,
    destination: DynamicAgent = nil,
    dropTarget = initDraggingDropTarget(),
): bool =
  if control.isNil or control.xDraggingSession.isNil:
    return false
  autoscrollDraggingSession(
    control.xDraggingSession,
    event.location,
    if destination.isNil:
      DynamicAgent(control)
    else:
      destination,
    dropTarget,
  )

proc finishDragging*(control: Control, operations = NoDragOperations) =
  if not control.isNil and not control.xDraggingSession.isNil:
    control.xDraggingSession.endDraggingSession(operations)

proc cancelDragging*(control: Control) =
  if not control.isNil and not control.xDraggingSession.isNil:
    control.xDraggingSession.cancelDraggingSession()

proc newActionTarget*(action: ActionSelector, callback: ActionProc): ClosureTarget =
  result = ClosureTarget()
  initResponder(result)
  result.xCallback = callback
  let fn: DynamicMethod = proc(self: DynamicAgent, invocation: var Invocation) =
    let target = ClosureTarget(self)
    let args = invocation.argsAs(ActionArgs)
    if not target.xCallback.isNil:
      target.xCallback(args.sender)
    invocation.setResult(())
  discard result.replaceMethod(action, fn)
