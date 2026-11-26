import std/unittest

import figdraw
import sigils/core

import merenda/nimkit

type TokenRecorder = ref object of Agent
  selected, removed, queries: seq[string]
  changes: int
  chipCounts: seq[int]

proc tokenSelected(recorder: TokenRecorder, option: ComboBoxOption) {.slot.} =
  recorder.selected.add option.identifier

proc tokenRemoved(recorder: TokenRecorder, option: ComboBoxOption) {.slot.} =
  recorder.removed.add option.identifier

proc tokensChanged(recorder: TokenRecorder, sender: DynamicAgent) {.slot.} =
  inc recorder.changes

proc queryChanged(recorder: TokenRecorder, sender: DynamicAgent) {.slot.} =
  let field = TokenField(sender)
  recorder.queries.add field.query
  recorder.chipCounts.add field.chipCount

proc record(field: TokenField): TokenRecorder =
  result = TokenRecorder()
  field.connect(tokenFieldDidSelect, result, tokenSelected)
  field.connect(tokenFieldDidRemove, result, tokenRemoved)
  field.connect(tokenFieldDidChange, result, tokensChanged)
  field.connect(tokenQueryDidChange, result, queryChanged)

type RejectingDelegate = ref object of Responder

protocol RejectDocs of TokenFieldDelegate:
  method shouldSelectOption(
      owner: RejectingDelegate, field: TokenField, option: ComboBoxOption
  ): bool =
    option.identifier != "docs"

suite "nimkit token fields":
  test "chips expose removable selection state and accessibility actions":
    let chip = newChip("Backend")
    var removed = false
    chip.onRemove = proc(sender: Chip) =
      check sender == chip
      removed = true

    check chip.label == "Backend"
    check chip.text == "Backend"
    check chip.removable
    chip.selected = true
    check chip.selected
    check atSelected in chip.accessibilityTraits()
    check AccessibilityActionDelete in chip.accessibilityActionNames()
    check chip.remove()
    check removed

    chip.enabled = false
    check not chip.remove()

  test "token fields filter options, disable selected values, and remove chips":
    let field = newTokenField(
      [
        initComboBoxOption("backend", "Backend"),
        initComboBoxOption("security", "Security"),
        initComboBoxOption("docs", "Docs"),
      ],
      placeholder = "Add labels...",
      frame = rect(0, 0, 280, 30),
    )
    let recorder = field.record()

    check field.optionCount == 3
    check field.selectedCount == 0
    check field.selectOptionWithIdentifier("backend")
    check field.selectedCount == 1
    check field.selectedOptionIdentifiers == @["backend"]
    check field.chipCount == 1
    check field.chipAtIndex(0).label == "Backend"
    check not field.optionIsEnabledAtIndex(0)
    check not field.selectOptionWithIdentifier("backend")

    field.query = "sec"
    check field.query == "sec"
    check field.filteredOptionCount == 1
    check field.optionAtIndex(0).identifier == "security"
    check field.selectOptionAtIndex(0)
    check field.selectedOptionIdentifiers == @["backend", "security"]
    check field.chipCount == 2

    check field.chipAtIndex(0).remove()
    check field.selectedOptionIdentifiers == @["security"]
    check field.chipCount == 1
    check field.optionIsEnabledAtIndex(0)
    check recorder.selected == @["backend", "security"]
    check recorder.removed == @["backend"]
    check recorder.changes == 3

    let delegate = RejectingDelegate()
    initResponder(delegate)
    discard delegate.withProtocol(RejectDocs)
    field.delegate = delegate
    check not field.selectOptionWithIdentifier("docs")
    check field.selectedOptionIdentifiers == @["security"]
    check field.accessibilityValue() == "Security"

  test "token field input opens filtered popup and activates a highlighted option":
    let
      window = newWindow("Token field", frame = rect(0, 0, 320, 180))
      root = newView(frame = rect(0, 0, 320, 180))
      field = newTokenField(
        [
          initComboBoxOption("backend", "Backend"),
          initComboBoxOption("security", "Security"),
          initComboBoxOption("docs", "Docs"),
        ],
        frame = rect(10, 10, 280, 30),
      )

    let recorder = field.record()

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field.input())
    check window.dispatchTextInput("sec")
    check window.dispatchTextInput("urity")
    check field.query == "security"
    check recorder.queries == @["sec", "security"]
    check field.popupOpen
    check field.filteredOptionCount == 1
    check field.optionAtIndex(0).identifier == "security"
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check field.input().highlightedIndex == 0
    check window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )
    check field.selectedOptionIdentifiers == @["security"]
    check field.query.len == 0
    check recorder.queries == @["sec", "security", ""]
    check recorder.chipCounts == @[0, 0, 1]
    check not field.popupOpen

    check window.dispatchKeyDown(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    check field.selectedCount == 0

  test "disabling a token field handles chips rebuilt during an enabled setter":
    let field = newTokenField(
      [initComboBoxOption("one", "One"), initComboBoxOption("two", "Two")]
    )
    require field.selectOptionWithIdentifier("one")
    require field.selectOptionWithIdentifier("two")
    let
      first = field.chipAtIndex(0)
      detached = field.chipAtIndex(1)
      rebuild: AroundMethod = proc(
          self: DynamicAgent, invocation: var Invocation, next: DynamicMethod
      ) =
        check not field.enabled
        check not field.input().enabled
        next(self, invocation)
        check field.removeSelectedOptionWithIdentifier("one")
      swizzle = first.pushMethod(`enabled=`(), rebuild)
    defer:
      discard swizzle.popMethod()

    field.enabled = false
    check field.selectedOptionIdentifiers == @["two"]
    let remaining = field.chipAtIndex(0)
    require remaining != detached
    check detached.enabled
    check not remaining.enabled

    field.enabled = true
    check field.input().enabled
    check remaining.enabled

  test "clicking an inline popup row selects a token":
    let
      window = newWindow("Token field mouse", frame = rect(0, 0, 320, 180))
      root = newView(frame = rect(0, 0, 320, 180))
      field = newTokenField(
        [
          initComboBoxOption("backend", "Backend"),
          initComboBoxOption("security", "Security"),
        ],
        frame = rect(10, 10, 280, 30),
      )
    defer:
      window.close()
    root.addSubview(field)
    window.setContentView(root)
    field.layoutSubtreeIfNeeded()
    field.popupOpen = true
    let
      input = field.input()
      row = input.popupItemRect(input.bounds(), 1)
      point = initPoint(row.minX + row.size.width / 2, row.minY + row.size.height / 2)
    check window.clickAt(input.pointToWindow(point))
    check field.selectedOptionIdentifiers == @["security"]
    check not field.popupOpen
    check not window.hasActiveTransientSession()

  test "allowing duplicates restores selected option availability":
    let field = newMultiSelectComboBox(
      [initComboBoxOption("one", "One")], frame = rect(0, 0, 240, 30)
    )

    check field.selectOptionWithIdentifier("one")
    check not field.optionIsEnabledAtIndex(0)
    field.allowDuplicates = true
    check field.optionIsEnabledAtIndex(0)
    check field.selectOptionWithIdentifier("one")
    check field.selectedCount == 2

  test "replacing options refreshes original enabled states":
    let field = newTokenField([initComboBoxOption("one", "One")])

    check field.selectOptionWithIdentifier("one")
    check not field.optionIsEnabledAtIndex(0)
    field.options = [initComboBoxOption("one", "One", enabled = false)]
    check not field.optionIsEnabledAtIndex(0)
    check field.removeSelectedOptionWithIdentifier("one")
    check not field.optionIsEnabledAtIndex(0)
