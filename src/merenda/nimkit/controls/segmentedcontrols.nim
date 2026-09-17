import ../foundation/types
import ./matrices

export matrices

type
  ## A single-row, mutually-exclusive Matrix convenience control.
  SegmentedControl* = Matrix

proc selectSegmentAtIndex*(control: SegmentedControl, index: int, notify = false): bool

proc newSegmentedControl*(
    titles: openArray[string], frame: Rect = AutoRect
): SegmentedControl =
  let prototype = newButtonCell()
  prototype.buttonType = btToggle
  result =
    newMatrix(if titles.len == 0: 0 else: 1, max(titles.len, 1), prototype, frame)
  result.selectionMode = msmRadio
  result.intercellSpacing = initSize(2.0, 0.0)
  for index, title in titles:
    result.cellAtIndex(index).title = title
  if titles.len > 0:
    discard result.selectSegmentAtIndex(0)
  result.applyInitialFrame(frame)

proc segmentCount*(control: SegmentedControl): int =
  control.len

proc selectedSegmentIndex*(control: SegmentedControl): int =
  control.selectedIndex()

proc `selectedSegmentIndex=`*(control: SegmentedControl, index: int) =
  if index < 0:
    control.deselectAll()
  else:
    discard control.selectSegmentAtIndex(index)

proc selectSegmentAtIndex*(
    control: SegmentedControl, index: int, notify = false
): bool =
  control.selectCellAtIndex(index, notify)

proc selectSegmentWithIdentifier*(
    control: SegmentedControl, identifier: string, notify = false
): bool {.discardable.} =
  control.selectMatrixItemWithIdentifier(identifier, notify)
