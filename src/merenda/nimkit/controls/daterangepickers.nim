## Optional calendar date ranges and a paired date-picker control.

import ../accessibility/accessibility
import ../containers/stackviews
import ../foundation/types
import ./datepickers

import sigils/core
import sigils/selectors

export datepickers
export stackviews

type
  DateRange* = object
    startDate*: CalendarDate
    hasStartDate*: bool
    endDate*: CalendarDate
    hasEndDate*: bool

  DateRangePicker* = ref object of StackView
    xStartButton: DatePickerButton
    xEndButton: DatePickerButton
    xLastRange: DateRange
    xOnChange: DateRangeChangeHandler

  DateRangeChangeHandler* = proc(picker: DateRangePicker, value: DateRange) {.closure.}

proc selectedRange*(picker: DateRangePicker): DateRange
proc setSelectedRange*(picker: DateRangePicker, value: DateRange): bool {.discardable.}
proc setStartDate*(picker: DateRangePicker, date: CalendarDate, notify = true): bool
proc setEndDate*(picker: DateRangePicker, date: CalendarDate, notify = true): bool

func initDateRange*(
    startDate: CalendarDate = CalendarDate(),
    hasStartDate = false,
    endDate: CalendarDate = CalendarDate(),
    hasEndDate = false,
): DateRange =
  result.startDate =
    if hasStartDate:
      startDate
    else:
      CalendarDate()
  result.hasStartDate = hasStartDate
  result.endDate =
    if hasEndDate:
      endDate
    else:
      CalendarDate()
  result.hasEndDate = hasEndDate

func `==`*(left, right: DateRange): bool =
  left.startDate == right.startDate and left.hasStartDate == right.hasStartDate and
    left.endDate == right.endDate and left.hasEndDate == right.hasEndDate

func isValidDateRange*(value: DateRange): bool =
  (not value.hasStartDate or value.startDate.isValidCalendarDate()) and
    (not value.hasEndDate or value.endDate.isValidCalendarDate()) and
    (not value.hasStartDate or not value.hasEndDate or value.startDate <= value.endDate)

func isEmpty*(value: DateRange): bool =
  not value.hasStartDate and not value.hasEndDate

proc startButton*(picker: DateRangePicker): DatePickerButton =
  picker.xStartButton

proc endButton*(picker: DateRangePicker): DatePickerButton =
  picker.xEndButton

proc selectedRange*(picker: DateRangePicker): DateRange =
  if picker.isNil:
    return
  if not picker.xStartButton.isNil and picker.xStartButton.hasSelectedDate():
    result.startDate = picker.xStartButton.selectedDate()
    result.hasStartDate = true
  if not picker.xEndButton.isNil and picker.xEndButton.hasSelectedDate():
    result.endDate = picker.xEndButton.selectedDate()
    result.hasEndDate = true

proc dateRange*(picker: DateRangePicker): DateRange =
  picker.selectedRange()

proc `dateRange=`*(picker: DateRangePicker, value: DateRange) =
  discard picker.setSelectedRange(value)

proc `selectedRange=`*(picker: DateRangePicker, value: DateRange) =
  discard picker.setSelectedRange(value)

proc applySelectedRange(picker: DateRangePicker, value: DateRange, notify: bool): bool =
  if picker.isNil or not value.isValidDateRange():
    return false
  let before = picker.xLastRange
  if value.hasStartDate:
    picker.xStartButton.selectedDate = value.startDate
  picker.xStartButton.hasSelectedDate = value.hasStartDate
  if value.hasEndDate:
    picker.xEndButton.selectedDate = value.endDate
  picker.xEndButton.hasSelectedDate = value.hasEndDate
  let after = picker.selectedRange()
  picker.xLastRange = after
  if notify and before != after:
    picker.postAccessibilityNotification(anValueChanged)
    if not picker.xOnChange.isNil:
      picker.xOnChange(picker, after)
  true

proc setSelectedRange*(
    picker: DateRangePicker, value: DateRange
): bool {.discardable.} =
  picker.applySelectedRange(value, notify = true)

proc setStartDate*(picker: DateRangePicker, date: CalendarDate, notify = true): bool =
  if picker.isNil or not date.isValidCalendarDate():
    return false
  let before = picker.xLastRange
  var next = before
  next.startDate = date
  next.hasStartDate = true
  if next.hasEndDate and next.endDate < date:
    next.endDate = date
  if not picker.applySelectedRange(next, notify):
    return false
  true

proc setEndDate*(picker: DateRangePicker, date: CalendarDate, notify = true): bool =
  if picker.isNil or not date.isValidCalendarDate():
    return false
  let before = picker.xLastRange
  var next = before
  next.endDate = date
  next.hasEndDate = true
  if next.hasStartDate and date < next.startDate:
    next.startDate = date
  if not picker.applySelectedRange(next, notify):
    return false
  true

proc clearStartDate*(picker: DateRangePicker, notify = true) =
  if picker.isNil:
    return
  var next = picker.selectedRange()
  next.hasStartDate = false
  discard picker.applySelectedRange(next, notify)

proc clearEndDate*(picker: DateRangePicker, notify = true) =
  if picker.isNil:
    return
  var next = picker.selectedRange()
  next.hasEndDate = false
  discard picker.applySelectedRange(next, notify)

proc clearDates*(picker: DateRangePicker, notify = true) =
  if picker.isNil:
    return
  discard picker.applySelectedRange(DateRange(), notify)

proc startDate*(picker: DateRangePicker): CalendarDate =
  picker.selectedRange().startDate

proc `startDate=`*(picker: DateRangePicker, date: CalendarDate) =
  discard picker.setStartDate(date)

proc hasStartDate*(picker: DateRangePicker): bool =
  picker.selectedRange().hasStartDate

proc `hasStartDate=`*(picker: DateRangePicker, value: bool) =
  if value:
    if not picker.hasStartDate():
      discard picker.setStartDate(todayCalendarDate())
  else:
    picker.clearStartDate()

proc endDate*(picker: DateRangePicker): CalendarDate =
  picker.selectedRange().endDate

proc `endDate=`*(picker: DateRangePicker, date: CalendarDate) =
  discard picker.setEndDate(date)

proc hasEndDate*(picker: DateRangePicker): bool =
  picker.selectedRange().hasEndDate

proc `hasEndDate=`*(picker: DateRangePicker, value: bool) =
  if value:
    if not picker.hasEndDate():
      discard picker.setEndDate(todayCalendarDate())
  else:
    picker.clearEndDate()

proc onChange*(picker: DateRangePicker): DateRangeChangeHandler =
  picker.xOnChange

proc `onChange=`*(picker: DateRangePicker, handler: DateRangeChangeHandler) =
  picker.xOnChange = handler

proc popupPresentation*(picker: DateRangePicker): PopupPresentation =
  picker.xStartButton.popupPresentation()

proc `popupPresentation=`*(picker: DateRangePicker, value: PopupPresentation) =
  picker.xStartButton.popupPresentation = value
  picker.xEndButton.popupPresentation = value

proc startDidSelect(picker: DateRangePicker, date: CalendarDate) =
  var next = picker.xLastRange
  next.startDate = date
  next.hasStartDate = true
  if next.hasEndDate and next.endDate < date:
    next.endDate = date
  discard picker.applySelectedRange(next, notify = true)

proc endDidSelect(picker: DateRangePicker, date: CalendarDate) =
  var next = picker.xLastRange
  next.endDate = date
  next.hasEndDate = true
  if next.hasStartDate and date < next.startDate:
    next.startDate = date
  discard picker.applySelectedRange(next, notify = true)

protocol DateRangePickerAccessibility of AccessibilityProtocol:
  method accessibilityRole(picker: DateRangePicker): AccessibilityRole =
    arGroup

  method accessibilityLabel(picker: DateRangePicker): string =
    if picker.xAccessibilityLabel.len > 0:
      picker.xAccessibilityLabel
    else:
      "Date range picker"

  method accessibilityValue(picker: DateRangePicker): string =
    let value = picker.selectedRange()
    if value.hasStartDate and value.hasEndDate:
      value.startDate.formatCalendarDate() & " – " & value.endDate.formatCalendarDate()
    elif value.hasStartDate:
      "From " & value.startDate.formatCalendarDate()
    elif value.hasEndDate:
      "Until " & value.endDate.formatCalendarDate()
    else:
      "No dates selected"

  method accessibilityTraits(picker: DateRangePicker): AccessibilityTraits =
    result = picker.xAccessibilityTraits
    if picker.focused():
      result.incl atFocused

  method isAccessibilityElement(picker: DateRangePicker): bool =
    true

proc initDateRangePickerFields*(
    picker: DateRangePicker,
    value: DateRange = DateRange(),
    startTitle = "From",
    endTitle = "Until",
    frame: Rect = AutoRect,
) =
  initStackViewFields(picker, laHorizontal, frame)
  picker.spacing = 8.0
  picker.alignment = svaCenter
  picker.distribution = svdNatural
  picker.xStartButton = newDatePickerButton(startTitle)
  picker.xEndButton = newDatePickerButton(endTitle)
  picker.addArrangedSubview(picker.xStartButton, picker.xEndButton)
  let pickerRef = picker.unsafeWeakRef()
  picker.xStartButton.onSelect = proc(date: CalendarDate) =
    if not pickerRef.isNil:
      pickerRef[].startDidSelect(date)
  picker.xEndButton.onSelect = proc(date: CalendarDate) =
    if not pickerRef.isNil:
      pickerRef[].endDidSelect(date)
  discard picker.withProtocol(DateRangePickerAccessibility)
  if value.isValidDateRange():
    discard picker.setSelectedRange(value)

proc newDateRangePicker*(
    startTitle = "From", endTitle = "Until", frame: Rect = AutoRect
): DateRangePicker =
  result = DateRangePicker()
  result.initDateRangePickerFields(
    DateRange(), startTitle = startTitle, endTitle = endTitle, frame = frame
  )

proc newDateRangePicker*(
    value: DateRange, startTitle = "From", endTitle = "Until", frame: Rect = AutoRect
): DateRangePicker =
  result = DateRangePicker()
  result.initDateRangePickerFields(value, startTitle, endTitle, frame)

proc newDateRangePicker*(
    startDate, endDate: CalendarDate,
    hasStartDate = true,
    hasEndDate = true,
    startTitle = "From",
    endTitle = "Until",
    frame: Rect = AutoRect,
): DateRangePicker =
  result = newDateRangePicker(
    initDateRange(startDate, hasStartDate, endDate, hasEndDate),
    startTitle,
    endTitle,
    frame,
  )
