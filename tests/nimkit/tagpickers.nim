import std/[strutils, unittest]

import sigils/core

import merenda/nimkit

type
  TagRecorder = ref object of Agent
    queries: seq[string]
    edits: int

  TagPolicy = ref object of Responder
    attempted: seq[string]

proc queryChanged(recorder: TagRecorder, sender: DynamicAgent) {.slot.} =
  recorder.queries.add TagController(sender).query

proc selectionEdited(recorder: TagRecorder, sender: DynamicAgent) {.slot.} =
  inc recorder.edits

protocol LowercaseTags of TagControllerDelegate:
  method shouldAddTag(
      policy: TagPolicy, controller: TagController, item: ModelItem
  ): bool =
    policy.attempted.add item.identifier
    item.identifier != "blocked"

  method tagForText(
      policy: TagPolicy, controller: TagController, text: string
  ): ModelItem =
    tagItem(text.toLowerAscii, text)

proc record(controller: TagController): TagRecorder =
  result = TagRecorder()
  controller.connect(tagQueryDidChange, result, queryChanged)
  controller.connect(tagSelectionDidChange, result, selectionEdited)

proc identifiers(items: seq[ModelItem]): seq[string] =
  for item in items:
    result.add item.identifier

proc newTags(allowsNewTags = false): TagController =
  newTagController(
    available = [tagItem("nature"), tagItem("night"), tagItem("nim"), tagItem("sunset")],
    allowsNewTags = allowsNewTags,
  )

proc showInWindow(view: View, width = 320.0'f32): Window =
  result = newWindow("Tags", frame = rect(0, 0, width + 40, 240))
  let root = newView(frame = rect(0, 0, width + 40, 240))
  view.frame = rect(10, 10, width, 40)
  root.addSubview(view)
  result.setContentView(root)
  view.layoutSubtreeIfNeeded()

proc key(window: Window, key: Key): bool =
  window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord))

proc popupIn(window: Window): PopupListView =
  for view in window.contentView.subviews:
    if view of PopupListView:
      return PopupListView(view)

proc firstRowPoint(popup: PopupListView): Point =
  let row = popup.popupListItemRect(popup.bounds, popup.firstIndex())
  popup.pointToWindow(initPoint(row.minX + 5, row.minY + row.size.height / 2))

proc recordInputLifetime(fieldRef: var BackRef[Responder]): Chip =
  let input =
    newTagInput(newTagController(selected = [tagItem("selected")]), inlineTags = true)
  fieldRef.target = input.field
  input.tagList.chips[0]

suite "tag picker controller":
  test "matches exclude selected tags and follow the match mode":
    let tags = newTags()
    tags.setSelectedTags([tagItem("night")])
    tags.query = "N"
    check tags.matches.identifiers == @["nature", "nim"]
    tags.query = "set"
    check tags.matches.len == 0
    tags.matchMode = tmmContains
    check tags.matches.identifiers == @["sunset"]

  test "only user edits send the selection signal":
    let tags = newTags()
    let recorder = tags.record()
    tags.setSelectedTags([tagItem("nim")])
    check recorder.edits == 0
    check tags.addTag(tagItem("nature"))
    check not tags.addTag(tagItem("nature"))
    check tags.removeTag("nim")
    check tags.selectedIdentifiers == @["nature"]
    check recorder.edits == 2

  test "committing text adds a matching or new tag through the delegate":
    let tags = newTags()
    tags.query = "Nim"
    check tags.commitQuery()
    check tags.selectedIdentifiers == @["nim"]
    check tags.query == ""
    tags.query = "Fresh"
    check not tags.commitQuery()

    tags.allowsNewTags = true
    let policy = TagPolicy()
    initResponder(policy)
    discard policy.withProtocol(LowercaseTags)
    tags.delegate = policy
    check tags.commitQuery()
    check tags.selectedTags[^1].identifier == "fresh"
    check tags.selectedTags[^1].title == "Fresh"
    check not tags.addTag(tagItem("blocked"))

  test "an exact title cannot bypass selection identity or a catalog veto":
    let
      tags = newTagController(
        [tagItem("sea-ice", "Sea Ice"), tagItem("blocked", "Reserved")],
        [tagItem("sea-ice", "Sea Ice")],
        allowsNewTags = true,
      )
      policy = TagPolicy()
    initResponder(policy)
    discard policy.withProtocol(LowercaseTags)
    tags.delegate = policy
    tags.selected.filter = proc(item: ModelItem): bool =
      false

    check tags.isSelected("sea-ice")
    check not tags.addTag(tagItem("sea-ice", "Sea Ice"))
    for query in ["SEA ICE", "Reserved"]:
      tags.query = query
      check not tags.commitQuery()
      check tags.query == query
    check tags.selectedIdentifiers == @["sea-ice"]
    tags.setAvailableTags([])
    tags.query = "Sea Ice"
    check not tags.commitQuery()

  test "replacing items keeps surviving selections and rejects duplicates":
    let controller = newArrayController([tagItem("a"), tagItem("b")])
    controller.selectionController.setSelectedIdentifiers(["b"])
    controller.setItems([tagItem("b"), tagItem("c")])
    check controller.len == 2
    check controller.selectionController.selectedIdentifiers == @["b"]
    expect ModelControllerError:
      controller.setItems([tagItem("x"), tagItem("x")])
    check controller.itemAt(0).identifier == "b"

suite "tag picker views":
  test "the dropdown lists every match, filters while typing and adds tags":
    let tags = newTags()
    let recorder = tags.record()
    let input = newTagInput(tags)
    let window = input.showInWindow()
    defer:
      input.closeList()
      window.close()
    let field = input.field
    check field.showsDropdownIndicator
    check field.mouseDown(MouseEvent(location: initPoint(20, 10), button: mbPrimary))
    check input.isListOpen
    check input.matches.identifiers == @["nature", "night", "nim", "sunset"]
    check input.highlightedIndex == -1

    check window.dispatchTextInput("ni")
    check tags.query == "ni"
    check recorder.queries == @["ni"]
    check input.matches.identifiers == @["night", "nim"]
    check input.highlightedIndex == 0
    check window.key(keyArrowDown)
    check input.highlightedIndex == 1
    check window.key(keyEnter)
    check tags.selectedIdentifiers == @["nim"]
    check field.stringValue == ""
    check not input.isListOpen

    check window.key(keyArrowDown)
    check input.isListOpen
    check input.matches.identifiers == @["nature", "night", "sunset"]
    check window.key(keyEscape)
    check not input.isListOpen

  test "typing keeps editing while the list resizes, closes and reopens":
    let input = newTagInput(newTags())
    let window = input.showInWindow()
    defer:
      input.closeList()
      window.close()
    check window.makeFirstResponder(input.field)
    let editor = input.field.currentEditor
    require not editor.isNil
    check window.dispatchTextInput("n")
    check input.isListOpen
    check input.matches.len == 3
    check window.dispatchTextInput("i")
    check input.isListOpen
    check input.matches.len == 2
    check window.dispatchTextInput("xy")
    check not input.isListOpen
    check window.key(keyBackspace)
    check window.key(keyBackspace)
    check input.field.stringValue == "ni"
    check input.isListOpen
    check input.field.currentEditor == editor

  test "keyboard and mouse vetoes keep the query and suggestions open":
    let
      tags = newTagController([tagItem("blocked", "Reserved")], allowsNewTags = true)
      policy = TagPolicy()
      input = newTagInput(tags)
      window = input.showInWindow()
    defer:
      window.close()
    initResponder(policy)
    discard policy.withProtocol(LowercaseTags)
    tags.delegate = policy
    require window.makeFirstResponder(input.field)
    require window.dispatchTextInput("res")
    require input.isListOpen
    check window.key(keyEnter)
    check tags.query == "res"
    check input.isListOpen
    check window.clickAt(window.popupIn().firstRowPoint())
    check tags.selectedIdentifiers.len == 0
    check input.field.stringValue == "res"
    check input.isListOpen
    check policy.attempted == @["blocked", "blocked"]

    tags.query = ""
    require window.dispatchTextInput("Reserved,fresh,")
    check tags.query == "Reserved,fresh,"
    check tags.selectedIdentifiers.len == 0
    check policy.attempted == @["blocked", "blocked", "blocked"]

  test "detaching the anchor dismisses the popup and discards stale row actions":
    let
      tags = newTags()
      input = newTagInput(tags)
      window = input.showInWindow()
    defer:
      window.close()
    require window.makeFirstResponder(input.field)
    input.openList()
    let popup = window.popupIn()
    require not popup.isNil
    let point = popup.firstRowPoint()
    let row = popup.accessibilityChildren()[0]
    input.removeFromSuperview()
    check not input.isListOpen
    check not window.hasActiveTransientSession()
    check popup.superview().isNil
    discard window.clickAt(point)
    check not row.accessibilityPerformAction(AccessibilityActionPress)
    check tags.selectedIdentifiers.len == 0

  test "a discarded input releases its field and retained chips can outlive it":
    var fieldRef: BackRef[Responder]
    let chip = recordInputLifetime(fieldRef)
    check fieldRef.isNil
    discard chip.remove()

  test "an open popup follows match mode, row count, and ancestor movement":
    let tags = newTags()
    tags.query = "set"
    let input = newTagInput(tags)
    check input.field.stringValue == "set"
    let
      group = newView()
      window = group.showInWindow()
    defer:
      window.close()
    input.frame = rect(0, 0, 260, 32)
    group.addSubview(input)
    input.openList()
    check not input.isListOpen
    tags.matchMode = tmmContains
    require input.isListOpen
    check input.matches.identifiers == @["sunset"]
    tags.query = ""
    let popup = window.popupIn()
    require not popup.isNil
    let before = popup.frame
    input.maxVisibleRows = 1
    check popup.frame.size.height < before.size.height
    check popup.accessibilityChildren().len == 1
    group.frame = rect(20, 30, group.frame.size.width, group.frame.size.height)
    check popup.frame.minX == before.minX + 10
    check popup.frame.minY == before.minY + 20

  test "the picker disables input and chips, and separate chips support keyboard removal":
    let
      tags = newTags()
      picker = newTagPicker(tags, tlpBelow)
      window = picker.showInWindow()
      input = picker.input
    defer:
      window.close()
    tags.setSelectedTags([tagItem("night")])
    require window.makeFirstResponder(input.field)
    input.openList()
    require input.isListOpen
    picker.enabled = false
    let chip = picker.tagList.chips[0]
    check not picker.enabled
    check input.field.currentEditor.isNil
    check not window.dispatchTextInput("ignored")
    check tags.query == ""
    check not input.isListOpen
    discard window.clickAt(input.field.pointToWindow(initPoint(10, 10)))
    check not input.isListOpen
    check not chip.remove()
    check not window.makeFirstResponder(chip)
    picker.enabled = true
    require window.makeFirstResponder(input.field)
    check window.key(keyTab)
    require window.firstResponder() == chip
    check window.key(keyBackspace)
    check tags.selectedIdentifiers.len == 0

  test "accessibility can open suggestions, inspect labels, and add a tag":
    let
      tags = newTags()
      input = newTagInput(tags)
      window = input.showInWindow()
    defer:
      window.close()
    check input.field.accessibilityRole() == arComboBox
    check input.field.accessibilityLabel() == input.field.placeholder
    check input.field.accessibilitySupportsAction(AccessibilityActionShowMenu)
    check input.field.accessibilityPerformAction(AccessibilityActionShowMenu)
    let popup = window.popupIn()
    require not popup.isNil
    let rows = popup.accessibilityChildren()
    require rows.len == 4
    check rows[1].accessibilityRole() == arListItem
    check rows[1].accessibilityLabel() == "night"
    check rows[1].accessibilityPerformAction(AccessibilityActionPress)
    check tags.selectedIdentifiers == @["night"]
    check not input.isListOpen

  test "the indicator toggles the list without editing text":
    let input = newTagInput(newTags())
    let window = input.showInWindow()
    defer:
      input.closeList()
      window.close()
    let indicator = input.field.dropdownIndicatorRect
    check indicator.size.width == DropdownIndicatorWidth
    let click = MouseEvent(
      location: initPoint(indicator.origin.x + 4, indicator.origin.y + 4),
      button: mbPrimary,
    )
    check input.field.mouseDown(click)
    check input.isListOpen
    check input.field.mouseDown(click)
    check not input.isListOpen

  test "inline tags share the field and Delete removes the last one":
    let tags = newTags(allowsNewTags = true)
    tags.setSelectedTags([tagItem("nature"), tagItem("night")])
    let picker = newTagPicker(tags, tlpInline)
    let window = picker.showInWindow()
    defer:
      picker.input.closeList()
      window.close()
    let list = picker.tagList
    check picker.input.tagList == list
    check not picker.input.field.bezeled
    check list.chips.len == 2
    check list.trailingView == picker.input.field

    check window.makeFirstResponder(picker.input.field)
    check window.dispatchTextInput("alpha,beta,")
    check tags.selectedIdentifiers == @["nature", "night", "alpha", "beta"]
    check picker.input.field.stringValue == ""
    check window.key(keyBackspace)
    check tags.selectedIdentifiers == @["nature", "night", "alpha"]
    check list.chips.len == 3

  test "a separate list wraps chips and removes tags from chips":
    let tags = newTags()
    tags.setSelectedTags(
      [tagItem("nature"), tagItem("night"), tagItem("nim"), tagItem("sunset")]
    )
    let picker = newTagPicker(tags, tlpBelow)
    check picker.arrangedSubviews == @[View(picker.input), View(picker.tagList)]
    check picker.input.tagList.isNil
    check picker.input.field.bezeled
    let list = picker.tagList
    list.frame = rect(0, 0, 120, 200)
    list.layoutSubtreeIfNeeded()
    check list.chips.len == 4
    check list.chips[^1].frame.origin.y > list.chips[0].frame.origin.y
    check list.chips[1].remove()
    check tags.selectedIdentifiers == @["nature", "nim", "sunset"]
    check list.chips.len == 3

    let above = newTagPicker(tags, tlpAbove)
    check above.arrangedSubviews == @[View(above.tagList), View(above.input)]

  test "an open dropdown in a filling stack settles and matches the input":
    let picker = newTagPicker(newTags(), tlpInline)
    let stack = newStackView(laVertical)
    stack.alignment = svaFill
    stack.addArrangedSubview(picker)
    let window = newWindow("Tags", frame = rect(0, 0, 600, 300))
    window.setContentView(stack)
    defer:
      picker.input.closeList()
      window.close()
    stack.layoutSubtreeIfNeeded()
    picker.input.openList()
    require picker.input.isListOpen
    for pass in 0 ..< 4:
      stack.setNeedsLayout()
      stack.layoutSubtreeIfNeeded()
    check stack.layoutFeedbackCycles() == 0
    check picker.input.frame.size.width == 600
    let popup = stack.subviews()[^1]
    check popup.frame.size.width == picker.input.frame.size.width

  test "an open dropdown tracks the position and width set by constraints":
    let
      window = newWindow("Tags", frame = rect(0, 0, 400, 220))
      root = newView(frame = rect(0, 0, 400, 220))
      input = newTagInput(newTags())
      width = input[atWidth].equalTo(120)
      left = input[atLeft].equalTo(root[atLeft] + 10)
    defer:
      window.close()
    root.addSubview(input)
    window.setContentView(root)
    activate(width, left)
    root.layoutSubtreeIfNeeded()
    input.openList()
    let popup = window.popupIn()
    require not popup.isNil
    check popup.frame.size.width == 120
    check popup.frame.minX == 10

    width.constant = 200
    left.constant = 35
    root.layoutSubtreeIfNeeded()
    check popup.frame.size.width == 200
    check popup.frame.minX == 35
    check root.layoutFeedbackCycles() == 0

  test "an inline picker grows only when its tags wrap":
    let tags = newTags()
    tags.setSelectedTags(
      [tagItem("nature"), tagItem("night"), tagItem("nim"), tagItem("sunset")]
    )
    let picker = newTagPicker(tags, tlpInline)
    let stack = newStackView(laVertical)
    stack.alignment = svaFill
    stack.distribution = svdNatural
    stack.addArrangedSubview(picker)
    let window = newWindow("Tags", frame = rect(0, 0, 760, 300))
    window.setContentView(stack)
    defer:
      window.close()
    # The height depends on the width, so the second pass applies the
    # measurement taken at the width the first pass assigned.
    stack.layoutSubtreeIfNeeded()
    stack.layoutSubtreeIfNeeded()
    let chip = picker.tagList.chips[0].frame
    let oneLine = picker.input.frame.size.height
    check picker.input.field.frame.origin.y < chip.maxY
    check oneLine <= chip.size.height + 8

    stack.frame = rect(0, 0, 240, 300)
    stack.layoutSubtreeIfNeeded()
    stack.layoutSubtreeIfNeeded()
    check picker.input.frame.size.height > oneLine
    check picker.input.field.frame.origin.y > chip.maxY
