import sigils/core

import ../foundation/selectors
import ../drawing/theme
import ../foundation/types
import ../view/viewgeometry
import ../view/views

export views

type
  FormLabelAlignment* = enum
    flaLeading
    flaTrailing

  FormRowAlignment* = enum
    fraFill
    fraTop
    fraCenter
    fraBottom

  FormRow* = object
    label*: View
    field*: View

  FormSpacing* = object
    xFormView: FormView

  FormView* = ref object of View
    xRows: seq[FormRow]
    xSpacing: array[Direction, float32]
    xEdgeInsets: EdgeInsets
    xLabelAlignment: FormLabelAlignment
    xRowAlignment: FormRowAlignment
    xMinimumFieldWidth: float32

  FormMetrics = object
    labelWidth: float32
    fieldWidth: float32
    rowHeights: seq[float32]

func normalizedSpacing(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedInsets(insets: EdgeInsets): EdgeInsets =
  initEdgeInsets(
    max(insets.top, 0.0'f32),
    max(insets.left, 0.0'f32),
    max(insets.bottom, 0.0'f32),
    max(insets.right, 0.0'f32),
  )

func totalSpacing(spacing: float32, count: int): float32 =
  if count <= 1:
    0.0'f32
  else:
    spacing * float32(count - 1)

proc fittingSize(view: View): Size =
  if view.isNil:
    initSize(0.0, 0.0)
  else:
    view.sizeThatFits(UnconstrainedFittingSize)

proc visibleFormView(formView: FormView, view: View): View =
  if view.isNil or view.superview != formView or view.isHidden: nil else: view

proc visibleRows(formView: FormView): seq[FormRow] =
  for row in formView.xRows:
    let
      label = formView.visibleFormView(row.label)
      field = formView.visibleFormView(row.field)
    if not label.isNil or not field.isNil:
      result.add FormRow(label: label, field: field)

proc formMetrics(formView: FormView): FormMetrics =
  result.fieldWidth = formView.xMinimumFieldWidth
  for row in formView.visibleRows():
    let
      labelSize = row.label.fittingSize()
      fieldSize = row.field.fittingSize()
    result.labelWidth = max(result.labelWidth, labelSize.width)
    result.fieldWidth = max(result.fieldWidth, fieldSize.width)
    result.rowHeights.add max(labelSize.height, fieldSize.height)

func hasColumns(metrics: FormMetrics): bool =
  metrics.labelWidth > 0.0'f32 and metrics.fieldWidth > 0.0'f32

proc naturalSize(formView: FormView): Size =
  let
    metrics = formView.formMetrics()
    rowCount = metrics.rowHeights.len
    colSpacing =
      if metrics.hasColumns:
        formView.xSpacing[dcol]
      else:
        0.0'f32

  var height =
    formView.xEdgeInsets.vertical + formView.xSpacing[drow].totalSpacing(rowCount)
  for rowHeight in metrics.rowHeights:
    height += rowHeight

  initSize(
    formView.xEdgeInsets.horizontal + metrics.labelWidth + colSpacing +
      metrics.fieldWidth,
    height,
  )

proc contentRect(formView: FormView): Rect =
  let
    bounds = formView.bounds()
    insets = formView.xEdgeInsets
  initRect(
    insets.left,
    insets.top,
    bounds.size.width - insets.horizontal,
    bounds.size.height - insets.vertical,
  )

proc setFrameFromFormLayout(view: View, frame: Rect) =
  view.applyLayoutFrame(frame, lfoContainer)

proc invalidateFormLayout(formView: FormView) =
  formView.invalidateContainerMetrics()
  formView.setNeedsDisplay(true)

proc boundedRowFrame(
    formView: FormView, rowY, rowHeight: float32, naturalSize: Size
): tuple[y, height: float32] =
  case formView.xRowAlignment
  of fraFill:
    (rowY, rowHeight)
  of fraTop:
    (rowY, min(naturalSize.height, rowHeight))
  of fraCenter:
    let height = min(naturalSize.height, rowHeight)
    (rowY + (rowHeight - height) / 2.0'f32, height)
  of fraBottom:
    let height = min(naturalSize.height, rowHeight)
    (rowY + rowHeight - height, height)

proc layoutFormRows(formView: FormView) =
  let
    rows = formView.visibleRows()
    metrics = formView.formMetrics()
    content = formView.contentRect()
    colSpacing =
      if metrics.hasColumns:
        formView.xSpacing[dcol]
      else:
        0.0'f32
    fieldX = content.origin.x + metrics.labelWidth + colSpacing
    fieldWidth = max(
      content.size.width - metrics.labelWidth - colSpacing, formView.xMinimumFieldWidth
    )

  var rowY = content.origin.y
  for index, row in rows:
    let
      rowHeight = metrics.rowHeights[index]
      labelSize = row.label.fittingSize()
      fieldSize = row.field.fittingSize()

    if not row.label.isNil:
      let
        frame = formView.boundedRowFrame(rowY, rowHeight, labelSize)
        labelX =
          case formView.xLabelAlignment
          of flaLeading:
            content.origin.x
          of flaTrailing:
            content.origin.x + metrics.labelWidth - labelSize.width
      row.label.setFrameFromFormLayout(
        initRect(labelX, frame.y, labelSize.width, frame.height)
      )

    if not row.field.isNil:
      let frame = formView.boundedRowFrame(rowY, rowHeight, fieldSize)
      row.field.setFrameFromFormLayout(
        initRect(fieldX, frame.y, fieldWidth, frame.height)
      )

    rowY += rowHeight + formView.xSpacing[drow]

proc rowIndex(formView: FormView, label, field: View): int =
  for index, row in formView.xRows:
    if row.label == label and row.field == field:
      return index
  -1

proc rowIndexContaining(formView: FormView, view: View): int =
  if formView.isNil or view.isNil:
    return -1
  for index, row in formView.xRows:
    if row.label == view or row.field == view:
      return index
  -1

proc rows*(formView: FormView): seq[FormRow] =
  if formView.isNil:
    @[]
  else:
    formView.xRows

proc spacing*(formView: FormView): FormSpacing =
  FormSpacing(xFormView: formView)

proc setSpacing*(formView: FormView, direction: Direction, spacing: float32) =
  let normalized = spacing.normalizedSpacing()
  if formView.isNil or formView.xSpacing[direction] == normalized:
    return
  formView.xSpacing[direction] = normalized
  formView.invalidateFormLayout()

proc `[]`*(spacing: FormSpacing, direction: Direction): float32 =
  let formView = spacing.xFormView
  if formView.isNil:
    return 0.0'f32
  formView.xSpacing[direction]

proc `[]=`*(spacing: FormSpacing, direction: Direction, value: float32) =
  spacing.xFormView.setSpacing(direction, value)

proc edgeInsets*(formView: FormView): EdgeInsets =
  if formView.isNil:
    initEdgeInsets(0.0)
  else:
    formView.xEdgeInsets

proc `edgeInsets=`*(formView: FormView, insets: EdgeInsets) =
  let normalized = insets.normalizedInsets()
  if formView.isNil or formView.xEdgeInsets == normalized:
    return
  formView.xEdgeInsets = normalized
  formView.invalidateFormLayout()

proc labelAlignment*(formView: FormView): FormLabelAlignment =
  if formView.isNil: flaTrailing else: formView.xLabelAlignment

proc `labelAlignment=`*(formView: FormView, alignment: FormLabelAlignment) =
  if formView.isNil or formView.xLabelAlignment == alignment:
    return
  formView.xLabelAlignment = alignment
  formView.invalidateFormLayout()

proc rowAlignment*(formView: FormView): FormRowAlignment =
  if formView.isNil: fraCenter else: formView.xRowAlignment

proc `rowAlignment=`*(formView: FormView, alignment: FormRowAlignment) =
  if formView.isNil or formView.xRowAlignment == alignment:
    return
  formView.xRowAlignment = alignment
  formView.invalidateFormLayout()

proc minFieldWidth*(formView: FormView): float32 =
  if formView.isNil: 0.0'f32 else: formView.xMinimumFieldWidth

proc `minFieldWidth=`*(formView: FormView, width: float32) =
  let normalized = max(width, 0.0'f32)
  if formView.isNil or formView.xMinimumFieldWidth == normalized:
    return
  formView.xMinimumFieldWidth = normalized
  formView.invalidateFormLayout()

proc intrinsicContentSize*(formView: FormView): IntrinsicSize =
  if formView.isNil:
    NoIntrinsicContentSize
  else:
    initIntrinsicSize(formView.naturalSize())

proc insertRow*(formView: FormView, label, field: View, index: int) =
  if formView.isNil or (label.isNil and field.isNil):
    return

  if not label.isNil and label.superview != formView:
    formView.addSubview(label)
  if not field.isNil and field.superview != formView:
    formView.addSubview(field)

  let oldIndex = formView.rowIndex(label, field)
  if oldIndex >= 0:
    formView.xRows.delete(oldIndex)

  let boundedIndex = max(0, min(index, formView.xRows.len))
  formView.xRows.insert(FormRow(label: label, field: field), boundedIndex)
  formView.invalidateFormLayout()

proc addRow*(formView: FormView, label, field: View) =
  formView.insertRow(label, field, formView.xRows.len)

proc removeRow*(formView: FormView, index: int) =
  if formView.isNil or index < 0 or index >= formView.xRows.len:
    return
  formView.xRows.delete(index)
  formView.invalidateFormLayout()

proc removeRowContaining(formView: FormView, view: View) =
  let index = formView.rowIndexContaining(view)
  if index >= 0:
    formView.removeRow(index)

protocol FormViewLifecycleSlots of ViewLifecycleProtocol:
  proc willRemoveSubview(formView: FormView, child: View) {.slot.} =
    formView.removeRowContaining(child)

protocol DefaultFormViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(formView: FormView): IntrinsicSize =
    initIntrinsicSize(formView.naturalSize())

  method layoutSubviews(formView: FormView) =
    formView.layoutFormRows()

proc initFormViewFields*(formView: FormView, frame: Rect = AutoRect) =
  initViewFields(formView, frame)
  formView.xSpacing[drow] = 8.0'f32
  formView.xSpacing[dcol] = 8.0'f32
  formView.xLabelAlignment = flaTrailing
  formView.xRowAlignment = fraCenter
  discard formView.withProtocol(DefaultFormViewLayout)
  discard formView.withProtocol(FormViewLifecycleSlots)
  formView.observeProtocol(formView, FormViewLifecycleSlots)
  formView.applyInitialFrame(frame)

proc newFormView*(frame: Rect = AutoRect): FormView =
  result = FormView()
  initFormViewFields(result, frame)
