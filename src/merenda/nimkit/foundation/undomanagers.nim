import sigils/core
import sigils/selectors

import ./notifications

type
  UndoOperation* = proc() {.closure.}

  UndoValueApplyProc*[T] = proc(value: T) {.closure.}
  UndoCollectionIndexProc* = proc(index: int) {.closure.}
  UndoCollectionInsertProc*[T] = proc(index: int, value: T) {.closure.}
  UndoCollectionMoveProc* = proc(fromIndex, toIndex: int) {.closure.}

  UndoCommand = object
    actionName: string
    operation: UndoOperation

  UndoGroup = object
    actionName: string
    commands: seq[UndoCommand]

  UndoStackEntry* = object
    actionName*: string
    commandCount*: Natural

  UndoDebugSummary* = object
    undoGroupCount*: Natural
    redoGroupCount*: Natural
    groupingDepth*: Natural
    disabledDepth*: Natural
    undoing*: bool
    redoing*: bool
    nextUndoActionName*: string
    nextRedoActionName*: string
    undoGroups*: seq[UndoStackEntry]
    redoGroups*: seq[UndoStackEntry]

  UndoManager* = ref object of DynamicAgent
    xUndoStack: seq[UndoGroup]
    xRedoStack: seq[UndoGroup]
    xGroupStack: seq[UndoGroup]
    xRedoReplayGroup: UndoGroup
    xUndoReplayGroup: UndoGroup
    xIsUndoing: bool
    xIsRedoing: bool
    xDisabledDepth: Natural
    xNextActionName: string
    xChangeIndex: int
    xCleanIndex: int
    xBranchSerial: int
    xCleanBranchSerial: int
    xHasCleanState: bool

protocol UndoManagerEvents:
  proc stateDidChange*(manager: UndoManager, sender: UndoManager) {.signal.}

func undoStackEntry(group: UndoGroup): UndoStackEntry =
  UndoStackEntry(actionName: group.actionName, commandCount: group.commands.len.Natural)

proc notifyStateChanged(manager: UndoManager) =
  if not manager.isNil:
    emit manager.stateDidChange(manager)
    postNotification(
      nkUndoStateDidChange,
      sender = DynamicAgent(manager),
      payload = initUndoNotificationPayload(
        undoCount = manager.xUndoStack.len.Natural,
        redoCount = manager.xRedoStack.len.Natural,
        groupingDepth = manager.xGroupStack.len.Natural,
        disabledDepth = manager.xDisabledDepth,
        undoing = manager.xIsUndoing,
        redoing = manager.xIsRedoing,
        clean =
          manager.xHasCleanState and manager.xChangeIndex == manager.xCleanIndex and
          manager.xBranchSerial == manager.xCleanBranchSerial,
        nextUndoActionName =
          if manager.xUndoStack.len > 0:
            manager.xUndoStack[^1].actionName
          else:
            "",
        nextRedoActionName =
          if manager.xRedoStack.len > 0:
            manager.xRedoStack[^1].actionName
          else:
            "",
      ),
    )

proc addCommand(group: var UndoGroup, command: sink UndoCommand) =
  if command.actionName.len > 0 and group.actionName.len == 0:
    group.actionName = command.actionName
  group.commands.add command

proc mergeGroup(target: var UndoGroup, source: sink UndoGroup) =
  if source.commands.len == 0:
    return
  if target.actionName.len == 0:
    target.actionName = source.actionName
  for command in source.commands:
    target.commands.add command

proc commitNormalGroup(manager: UndoManager, group: sink UndoGroup) =
  if manager.isNil or group.commands.len == 0:
    return
  if group.actionName.len == 0 and manager.xNextActionName.len > 0:
    group.actionName = manager.xNextActionName
  if manager.xRedoStack.len > 0:
    inc manager.xBranchSerial
    manager.xRedoStack.setLen(0)
  manager.xNextActionName = ""
  manager.xUndoStack.add group
  inc manager.xChangeIndex
  manager.notifyStateChanged()

proc commitEndedGroup(manager: UndoManager, group: sink UndoGroup) =
  if manager.isNil or group.commands.len == 0:
    return
  if manager.xGroupStack.len > 0:
    manager.xGroupStack[^1].mergeGroup(group)
  elif manager.xIsUndoing:
    manager.xRedoReplayGroup.mergeGroup(group)
  elif manager.xIsRedoing:
    manager.xUndoReplayGroup.mergeGroup(group)
  else:
    manager.commitNormalGroup(group)

proc newUndoManager*(): UndoManager =
  result = UndoManager(xHasCleanState: true)

proc isUndoing*(manager: UndoManager): bool =
  not manager.isNil and manager.xIsUndoing

proc isRedoing*(manager: UndoManager): bool =
  not manager.isNil and manager.xIsRedoing

proc isUndoRegistrationEnabled*(manager: UndoManager): bool =
  not manager.isNil and manager.xDisabledDepth == 0

proc groupingDepth*(manager: UndoManager): Natural =
  if manager.isNil:
    return 0
  manager.xGroupStack.len.Natural

proc undoCount*(manager: UndoManager): Natural =
  if manager.isNil:
    return 0
  manager.xUndoStack.len.Natural

proc redoCount*(manager: UndoManager): Natural =
  if manager.isNil:
    return 0
  manager.xRedoStack.len.Natural

proc canUndo*(manager: UndoManager): bool =
  not manager.isNil and manager.xUndoStack.len > 0

proc canRedo*(manager: UndoManager): bool =
  not manager.isNil and manager.xRedoStack.len > 0

proc undoActionName*(manager: UndoManager): string =
  if manager.isNil or manager.xUndoStack.len == 0:
    ""
  else:
    manager.xUndoStack[^1].actionName

proc redoActionName*(manager: UndoManager): string =
  if manager.isNil or manager.xRedoStack.len == 0:
    ""
  else:
    manager.xRedoStack[^1].actionName

proc beginUndoGrouping*(manager: UndoManager) =
  if not manager.isNil:
    manager.xGroupStack.add UndoGroup()

proc endUndoGrouping*(manager: UndoManager): bool {.discardable.} =
  if manager.isNil or manager.xGroupStack.len == 0:
    return false
  let group = manager.xGroupStack.pop()
  manager.commitEndedGroup(group)
  true

proc discardUndoGrouping*(manager: UndoManager): bool {.discardable.} =
  if manager.isNil or manager.xGroupStack.len == 0:
    return false
  discard manager.xGroupStack.pop()
  true

proc setActionName*(manager: UndoManager, actionName: string) =
  if manager.isNil:
    return
  if manager.xGroupStack.len > 0:
    manager.xGroupStack[^1].actionName = actionName
  elif manager.xIsUndoing:
    manager.xRedoReplayGroup.actionName = actionName
  elif manager.xIsRedoing:
    manager.xUndoReplayGroup.actionName = actionName
  else:
    manager.xNextActionName = actionName

proc disableUndoRegistration*(manager: UndoManager) =
  if not manager.isNil:
    inc manager.xDisabledDepth

proc enableUndoRegistration*(manager: UndoManager) =
  if manager.isNil or manager.xDisabledDepth == 0:
    return
  dec manager.xDisabledDepth

template withUndoRegistrationDisabled*(manager: UndoManager, body: untyped): untyped =
  let undoManagerForScope = manager
  undoManagerForScope.disableUndoRegistration()
  try:
    body
  finally:
    undoManagerForScope.enableUndoRegistration()

proc registerUndo*(manager: UndoManager, operation: UndoOperation, actionName = "") =
  if manager.isNil or operation.isNil or manager.xDisabledDepth > 0:
    return
  let command = UndoCommand(actionName: actionName, operation: operation)
  if manager.xGroupStack.len > 0:
    manager.xGroupStack[^1].addCommand(command)
  elif manager.xIsUndoing:
    manager.xRedoReplayGroup.addCommand(command)
  elif manager.xIsRedoing:
    manager.xUndoReplayGroup.addCommand(command)
  else:
    var group = UndoGroup(actionName: actionName)
    group.addCommand(command)
    manager.commitNormalGroup(group)

proc registerValueChange*[T](
    manager: UndoManager, apply: UndoValueApplyProc[T], oldValue: T, actionName = ""
) =
  manager.registerUndo(
    proc() =
      apply(oldValue),
    actionName,
  )

proc setUndoableValue*[T](
    manager: UndoManager,
    currentValue, newValue: T,
    apply: UndoValueApplyProc[T],
    actionName = "",
): bool {.discardable.} =
  if currentValue == newValue:
    return false
  manager.registerValueChange(apply, currentValue, actionName)
  apply(newValue)
  true

proc registerSelectionChange*[T](
    manager: UndoManager, apply: UndoValueApplyProc[T], oldSelection: T, actionName = ""
) =
  manager.registerValueChange(apply, oldSelection, actionName)

proc registerCollectionInsert*(
    manager: UndoManager, removeAt: UndoCollectionIndexProc, index: int, actionName = ""
) =
  manager.registerUndo(
    proc() =
      removeAt(index),
    actionName,
  )

proc registerCollectionRemove*[T](
    manager: UndoManager,
    insertAt: UndoCollectionInsertProc[T],
    index: int,
    value: T,
    actionName = "",
) =
  manager.registerUndo(
    proc() =
      insertAt(index, value),
    actionName,
  )

proc registerCollectionMove*(
    manager: UndoManager,
    move: UndoCollectionMoveProc,
    fromIndex, toIndex: int,
    actionName = "",
) =
  manager.registerUndo(
    proc() =
      move(toIndex, fromIndex),
    actionName,
  )

proc performUndo*(manager: UndoManager): bool {.discardable.} =
  if manager.isNil or manager.xUndoStack.len == 0 or manager.xIsUndoing or
      manager.xIsRedoing:
    return false
  let group = manager.xUndoStack.pop()
  manager.xRedoReplayGroup = UndoGroup(actionName: group.actionName)
  manager.xIsUndoing = true
  try:
    var index = group.commands.len - 1
    while index >= 0:
      let command = group.commands[index]
      command.operation()
      dec index
  finally:
    manager.xIsUndoing = false
  if manager.xRedoReplayGroup.commands.len > 0:
    manager.xRedoStack.add manager.xRedoReplayGroup
  manager.xRedoReplayGroup = UndoGroup()
  dec manager.xChangeIndex
  manager.notifyStateChanged()
  true

proc performRedo*(manager: UndoManager): bool {.discardable.} =
  if manager.isNil or manager.xRedoStack.len == 0 or manager.xIsUndoing or
      manager.xIsRedoing:
    return false
  let group = manager.xRedoStack.pop()
  manager.xUndoReplayGroup = UndoGroup(actionName: group.actionName)
  manager.xIsRedoing = true
  try:
    var index = group.commands.len - 1
    while index >= 0:
      let command = group.commands[index]
      command.operation()
      dec index
  finally:
    manager.xIsRedoing = false
  if manager.xUndoReplayGroup.commands.len > 0:
    manager.xUndoStack.add manager.xUndoReplayGroup
  manager.xUndoReplayGroup = UndoGroup()
  inc manager.xChangeIndex
  manager.notifyStateChanged()
  true

proc clearUndo*(manager: UndoManager) =
  if manager.isNil:
    return
  if manager.xUndoStack.len > 0:
    manager.xUndoStack.setLen(0)
    manager.notifyStateChanged()

proc clearRedo*(manager: UndoManager) =
  if manager.isNil:
    return
  if manager.xRedoStack.len > 0:
    manager.xRedoStack.setLen(0)
    manager.notifyStateChanged()

proc clearAll*(manager: UndoManager) =
  if manager.isNil:
    return
  if manager.xUndoStack.len > 0 or manager.xRedoStack.len > 0 or
      manager.xGroupStack.len > 0:
    manager.xUndoStack.setLen(0)
    manager.xRedoStack.setLen(0)
    manager.xGroupStack.setLen(0)
    manager.notifyStateChanged()

proc markCleanState*(manager: UndoManager) =
  if manager.isNil:
    return
  manager.xCleanIndex = manager.xChangeIndex
  manager.xCleanBranchSerial = manager.xBranchSerial
  manager.xHasCleanState = true
  manager.notifyStateChanged()

proc clearCleanState*(manager: UndoManager) =
  if manager.isNil:
    return
  manager.xHasCleanState = false
  manager.notifyStateChanged()

proc isAtCleanState*(manager: UndoManager): bool =
  not manager.isNil and manager.xHasCleanState and
    manager.xChangeIndex == manager.xCleanIndex and
    manager.xBranchSerial == manager.xCleanBranchSerial

proc debugSummary*(manager: UndoManager): UndoDebugSummary =
  if manager.isNil:
    return
  result.undoGroupCount = manager.xUndoStack.len.Natural
  result.redoGroupCount = manager.xRedoStack.len.Natural
  result.groupingDepth = manager.xGroupStack.len.Natural
  result.disabledDepth = manager.xDisabledDepth
  result.undoing = manager.xIsUndoing
  result.redoing = manager.xIsRedoing
  result.nextUndoActionName = manager.undoActionName()
  result.nextRedoActionName = manager.redoActionName()
  for group in manager.xUndoStack:
    result.undoGroups.add group.undoStackEntry()
  for group in manager.xRedoStack:
    result.redoGroups.add group.undoStackEntry()
