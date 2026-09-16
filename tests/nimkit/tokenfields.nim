import std/unittest

import figdraw

import merenda/nimkit

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
    var
      selected: seq[string]
      removed: seq[string]
      changes = 0
    field.onSelect = proc(option: ComboBoxOption) =
      selected.add option.identifier
    field.onRemove = proc(option: ComboBoxOption) =
      removed.add option.identifier
    field.onChange = proc(sender: TokenField) =
      check sender == field
      inc changes

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
    check selected == @["backend", "security"]
    check removed == @["backend"]
    check changes == 3
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

    root.addSubview(field)
    window.setContentView(root)
    check window.makeFirstResponder(field.input())
    check window.dispatchKeyDown(KeyEvent(text: "sec", key: keyS, keyCode: keyS.ord))
    check field.query == "sec"
    check field.popupOpen
    check field.filteredOptionCount == 1
    check field.optionAtIndex(0).identifier == "security"
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check field.input().highlightedIndex == 0
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check field.selectedOptionIdentifiers == @["security"]
    check field.query.len == 0
    check not field.popupOpen

    check window.dispatchKeyDown(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    check field.selectedCount == 0

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
