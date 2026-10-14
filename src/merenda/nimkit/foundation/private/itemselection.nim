## Selection algorithms shared by index-backed rows and identity-backed items.
## Contexts and transaction callbacks are used synchronously, never retained.

import std/[algorithm, sets]

import ../events

type
  ItemSelectionMode* = enum
    ismNone
    ismSingle
    ismMultiple
    ismExtended

  ItemSelectionGesture* = enum
    isgReplace
    isgExtend
    isgToggle

  ItemSelectionState*[K] = object
    selected*: seq[K]
    anchor*, lead*: K

  ItemSelectionContext*[K] = object
    count*: int
    mode*: ItemSelectionMode
    empty*: K
    keyAt*: proc(index: int): K {.closure.}
    indexOf*: proc(key: K): int {.closure.}
    selectable*: proc(index: int): bool {.closure.}
    retainInvalidCursor*: bool

proc firstSelected*[K](state: ItemSelectionState[K], empty: K): K =
  if state.selected.len > 0:
    state.selected[0]
  else:
    empty

proc normalized*[K](context: ItemSelectionContext[K], keys: openArray[K]): seq[K] =
  if context.mode == ismNone or (not context.indexOf.isNil and context.count == 0):
    return
  var seen: HashSet[K]
  var indexed: seq[tuple[index: int, key: K]]
  for key in keys:
    if key == context.empty or key in seen:
      continue
    seen.incl key
    if context.indexOf.isNil:
      result.add key
    else:
      let index = context.indexOf(key)
      if index in 0 ..< context.count and context.selectable(index):
        indexed.add (index, key)
  if not context.indexOf.isNil:
    indexed.sort(
      proc(left, right: tuple[index: int, key: K]): int =
        cmp(left.index, right.index)
    )
    for entry in indexed:
      result.add entry.key
  if context.mode == ismSingle and result.len > 1:
    result.setLen(1)

proc cursorKey[K](context: ItemSelectionContext[K], key, previous, first: K): K =
  let index = context.indexOf(key)
  if context.retainInvalidCursor:
    if index >= 0: key else: previous
  elif index in 0 ..< context.count and context.selectable(index):
    key
  else:
    first

proc changeSelection*[K](
    state: var ItemSelectionState[K],
    context: ItemSelectionContext[K],
    keys: openArray[K],
    anchor, lead: K,
    beforeChange: proc(previous: seq[K]) {.closure.},
    cursorChanged: proc(lead: K) {.closure.},
    afterChange: proc(first: K) {.closure.},
) =
  let
    next = context.normalized(keys)
    first =
      if next.len > 0:
        next[0]
      else:
        context.empty
    nextAnchor =
      if next.len == 0:
        first
      else:
        context.cursorKey(anchor, state.anchor, first)
    nextLead =
      if next.len == 0:
        first
      else:
        context.cursorKey(lead, state.anchor, first)
    changed = state.selected != next
  if changed:
    beforeChange(state.selected)
    state.selected = next
  state.anchor = nextAnchor
  state.lead = nextLead
  cursorChanged(nextLead)
  if changed:
    afterChange(first)

proc keysInRange*[K](context: ItemSelectionContext[K], anchor, lead: K): seq[K] =
  let
    first = context.indexOf(anchor)
    last = context.indexOf(lead)
  if first < 0 or last < 0:
    return
  for index in min(first, last) .. max(first, last):
    let key = context.keyAt(index)
    if key != context.empty:
      result.add key

proc toggled*[K](state: ItemSelectionState[K], key, empty: K): seq[K] =
  if key in state.selected:
    for selected in state.selected:
      if selected != key:
        result.add selected
  else:
    result = state.selected
    if key != empty:
      result.add key

proc nextSelectable*[K](context: ItemSelectionContext[K], index, delta: int): int =
  if delta == 0:
    return -1
  let step = if delta < 0: -1 else: 1
  var current = index
  while current in 0 ..< context.count:
    if context.selectable(current):
      return current
    current += step
  -1

proc nearestSelectable*[K](context: ItemSelectionContext[K], index, delta: int): int =
  if context.count == 0 or context.mode == ismNone:
    return -1
  let target = max(0, min(index, context.count - 1))
  result = context.nextSelectable(target, delta)
  if result < 0 and delta != 0:
    result = context.nextSelectable(target, -delta)

proc selectionGesture*(
    mode: ItemSelectionMode, modifiers: set[KeyModifier]
): ItemSelectionGesture =
  if mode == ismExtended and kmShift in modifiers:
    isgExtend
  elif mode in {ismMultiple, ismExtended} and
      (kmCommand in modifiers or kmControl in modifiers):
    isgToggle
  else:
    isgReplace

proc selectedRanges*(indexes: openArray[int]): seq[Slice[int]] =
  if indexes.len == 0:
    return
  var first = indexes[0]
  var previous = first
  for offset in 1 ..< indexes.len:
    let index = indexes[offset]
    if index != previous + 1:
      result.add first .. previous
      first = index
    previous = index
  result.add first .. previous

proc indexesInRange*(selection: Slice[int]): seq[int] =
  for index in selection.a .. selection.b:
    result.add index
