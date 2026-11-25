import std/unittest

import sigils/core

import merenda/nimkit

type UndoStateSpy = ref object of Agent
  changeCount: int
  cleanStates: seq[bool]

proc rememberUndoState(spy: UndoStateSpy, manager: UndoManager) {.slot.} =
  inc spy.changeCount
  spy.cleanStates.add manager.isAtCleanState()

suite "nimkit undo managers":
  test "typed changes coalesce only across continuous matching gestures":
    let manager = newUndoManager()
    var value = ""
    proc apply(next: string) =
      value = next

    proc change(next: string, key = "title") =
      let before = value
      value = next
      manager.registerMergeableValueChange(apply, before, next, key, "Edit")

    change("a")
    change("ab")
    check manager.undoCount == 1
    check manager.performUndo()
    check value == ""
    check manager.performRedo()
    check value == "ab"
    change("abc") # redo ends the gesture
    manager.breakUndoCoalescing()
    change("abcd")
    change("abcde", "other")
    check manager.undoCount == 4
    value = "x"
    manager.registerMergeableValueChange(apply, "different", "x", "other")
    check manager.undoCount == 5
    check manager.performUndo()
    check value == "different"

  test "checkpoints and unrelated commands separate typed changes":
    let manager = newUndoManager()
    var value = 0
    proc apply(next: int) =
      value = next

    value = 1
    manager.registerMergeableValueChange(apply, 0, 1, "number")
    manager.markCleanState()
    value = 2
    manager.registerMergeableValueChange(apply, 1, 2, "number")
    check manager.undoCount == 2
    check manager.performUndo()
    check value == 1
    check manager.isAtCleanState()
    check manager.performRedo()
    manager.registerUndo(
      proc() =
        discard
    )
    value = 3
    manager.registerMergeableValueChange(apply, 2, 3, "number")
    check manager.undoCount == 4

  test "history limits retain clean state identity through pruning and branching":
    let manager = newUndoManager()
    var value = 0
    proc apply(next: int) =
      value = next

    proc change(next: int) =
      let before = value
      value = next
      manager.registerMergeableValueChange(apply, before, next, "", "Edit")

    manager.historyLimit = 2
    change(1)
    manager.markCleanState()
    change(2)
    change(3)
    check manager.undoCount == 2
    check manager.performUndo()
    check manager.performUndo()
    check manager.isAtCleanState()
    check value == 1
    manager.historyLimit = 1
    check manager.redoCount == 1
    change(4)
    check not manager.isAtCleanState()
    check manager.performUndo()
    check manager.isAtCleanState()
    check value == 1

    check manager.performRedo()
    manager.markCleanState()
    check manager.performUndo()
    manager.historyLimit = 0
    manager.clearRedo()
    change(5)
    check not manager.isAtCleanState()

  test "action names separate coalesced gestures":
    let manager = newUndoManager()
    var value = 0
    proc apply(next: int) =
      value = next

    value = 1
    manager.registerMergeableValueChange(apply, 0, 1, "number", "First")
    manager.setActionName("Second")
    value = 2
    manager.registerMergeableValueChange(apply, 1, 2, "number")
    check manager.undoCount == 2
    check manager.undoActionName == "Second"

  test "replay observers can reduce the limit and mark the resulting state clean":
    let manager = newUndoManager()
    manager.registerUndo(
      proc() =
        discard,
      "Earlier",
    )
    manager.registerUndo(
      proc() =
        manager.registerUndo(
          proc() =
            discard,
          "Redo",
        )
        manager.historyLimit = 1
        manager.markCleanState()
    )
    check manager.performUndo()
    check manager.undoCount == 0
    check manager.redoCount == 1
    check manager.isAtCleanState()
    check manager.performRedo()
    check not manager.isAtCleanState()

  test "redo applies a new history limit and deferred checkpoint":
    let manager = newUndoManager()
    manager.registerUndo(
      proc() =
        discard,
      "Earlier",
    )
    manager.registerUndo(
      proc() =
        manager.registerUndo(
          proc() =
            manager.registerUndo(
              proc() =
                discard
            )
            manager.historyLimit = 1
            manager.markCleanState()
        )
    )
    check manager.performUndo()
    check manager.performRedo()
    check manager.undoCount == 1
    check manager.redoCount == 0
    check manager.isAtCleanState()

  test "groups nested commands, names actions, and invalidates redo branches":
    let manager = newUndoManager()
    var value = ""

    proc assignValue(next: string) =
      let before = value
      if before == next:
        return
      manager.registerValueChange(
        proc(value: string) =
          assignValue(value),
        before,
        "Set Value",
      )
      value = next

    manager.beginUndoGrouping()
    manager.setActionName("Compose Value")
    assignValue("a")
    manager.beginUndoGrouping()
    assignValue("ab")
    check manager.groupingDepth == 2
    check manager.endUndoGrouping()
    check manager.endUndoGrouping()

    check value == "ab"
    check manager.undoCount == 1
    check manager.undoActionName == "Compose Value"
    check manager.debugSummary().undoGroups[0].commandCount == 2

    check manager.performUndo()
    check value == ""
    check manager.redoCount == 1
    check manager.redoActionName == "Compose Value"

    check manager.performRedo()
    check value == "ab"

    check manager.performUndo()
    assignValue("branch")
    check value == "branch"
    check manager.redoCount == 0

  test "nested undo registration forms redo groups":
    let manager = newUndoManager()
    var events: seq[string]

    proc redoA() =
      events.add "redo-a"

    proc redoB() =
      events.add "redo-b"

    proc undoNested() =
      manager.beginUndoGrouping()
      manager.registerUndo(redoA, "Redo Nested")
      manager.registerUndo(redoB, "Redo Nested")
      check manager.endUndoGrouping()
      events.add "undo"

    manager.registerUndo(undoNested, "Undo Nested")

    check manager.performUndo()
    check events == @["undo"]
    check manager.redoCount == 1
    check manager.debugSummary().redoGroups[0].commandCount == 2

    check manager.performRedo()
    check events == @["undo", "redo-b", "redo-a"]

  test "disabled undo scopes mutate without registration":
    let manager = newUndoManager()
    var value = 0

    proc assignValue(next: int) =
      let before = value
      manager.registerValueChange(
        proc(value: int) =
          assignValue(value),
        before,
        "Set Number",
      )
      value = next

    withUndoRegistrationDisabled(manager):
      assignValue(10)

    check value == 10
    check manager.undoCount == 0
    check manager.debugSummary().disabledDepth == 0

  test "documents track edited state against undo clean positions":
    let document = newDocument()
    let manager = document.undoManagerFor()
    var number = 0

    proc assignNumber(next: int) =
      let before = number
      if before == next:
        return
      manager.registerValueChange(
        proc(value: int) =
          assignNumber(value),
        before,
        "Set Number",
      )
      number = next

    check not document.isDocumentEdited
    assignNumber(1)
    check document.isDocumentEdited

    document.documentEdited = false
    check manager.isAtCleanState()
    assignNumber(2)
    check document.isDocumentEdited

    check manager.performUndo()
    check number == 1
    check not document.isDocumentEdited

    check manager.performRedo()
    check number == 2
    check document.isDocumentEdited

  test "text storage registers snapshot inverses":
    let
      manager = newUndoManager()
      storage = newTextStorage("hello")

    storage.undoManager = manager
    storage.replace(initTextRange(5, 0), " world")

    check storage.stringValue == "hello world"
    check manager.undoCount == 1

    check manager.performUndo()
    check storage.stringValue == "hello"
    check manager.performRedo()
    check storage.stringValue == "hello world"

  test "choice controls and document tabs register through responder lookup":
    let
      document = newDocument()
      manager = document.undoManagerFor()
      combo = newComboBox(["Small", "Large"])
      tabs = newDocumentTabs()
      first = newDocumentTabItem("First", "first")
      second = newDocumentTabItem("Second", "second")

    combo.setNextResponder(document)
    tabs.setNextResponder(document)

    withUndoRegistrationDisabled(manager):
      discard tabs.add(first)
      discard tabs.add(second)

    document.documentEdited = false

    combo.selectedIndex = 1
    check combo.stringValue == "Large"
    check document.isDocumentEdited
    check manager.performUndo()
    check combo.stringValue == ""

    document.documentEdited = false
    check tabs.move(1, 0)
    check tabs[0] == second
    check document.isDocumentEdited
    check manager.performUndo()
    check tabs[0] == first

  test "state change signal fans out to observers":
    let
      manager = newUndoManager()
      firstSpy = UndoStateSpy()
      secondSpy = UndoStateSpy()

    manager.connect(stateDidChange, firstSpy, rememberUndoState)
    manager.connect(stateDidChange, secondSpy, rememberUndoState)

    manager.registerUndo(
      proc() =
        discard,
      "No Op",
    )
    check firstSpy.changeCount == 1
    check secondSpy.changeCount == 1

    manager.disconnect(stateDidChange, firstSpy, rememberUndoState)
    manager.markCleanState()
    check firstSpy.changeCount == 1
    check secondSpy.changeCount == 2
    check secondSpy.cleanStates[^1]
