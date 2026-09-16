import std/unittest

import merenda/nimkit

suite "NimKit date range pickers":
  test "date ranges validate optional ordered endpoints":
    let
      start = initCalendarDate(2025, 6, 10)
      endDate = initCalendarDate(2025, 7, 24)
      valid = initDateRange(
        startDate = start, hasStartDate = true, endDate = endDate, hasEndDate = true
      )
      startOnly = initDateRange(startDate = start, hasStartDate = true)
      endOnly = initDateRange(endDate = endDate, hasEndDate = true)
      reversed = initDateRange(
        startDate = endDate, hasStartDate = true, endDate = start, hasEndDate = true
      )

    check valid.isValidDateRange()
    check startOnly.isValidDateRange()
    check endOnly.isValidDateRange()
    check valid == initDateRange(start, true, endDate, true)
    check not valid.isEmpty()
    check startOnly.startDate == start
    check not startOnly.hasEndDate
    check endOnly.endDate == endDate
    check not endOnly.hasStartDate
    check not reversed.isValidDateRange()
    check initDateRange().isEmpty()

  test "date range picker normalizes endpoints and emits one change callback":
    let
      start = initCalendarDate(2025, 6, 10)
      endDate = initCalendarDate(2025, 7, 24)
      initial = initDateRange(
        startDate = start, hasStartDate = true, endDate = endDate, hasEndDate = true
      )
      picker = newDateRangePicker(initial, startTitle = "From", endTitle = "Until")
    var
      callbackCount = 0
      callbackValues: seq[DateRange]
    picker.onChange = proc(sender: DateRangePicker, value: DateRange) =
      check sender == picker
      inc callbackCount
      callbackValues.add(value)

    check picker.selectedRange == initial
    check picker.dateRange == initial
    check picker.startButton.title == "From · Jun 10, 2025"
    check picker.endButton.title == "Until · Jul 24, 2025"
    check picker.accessibilityLabel() == "Date range picker"
    check picker.accessibilityValue() == "Jun 10, 2025 – Jul 24, 2025"

    check picker.setStartDate(initCalendarDate(2025, 8, 3))
    check picker.selectedRange ==
      initDateRange(
        startDate = initCalendarDate(2025, 8, 3),
        hasStartDate = true,
        endDate = initCalendarDate(2025, 8, 3),
        hasEndDate = true,
      )
    check callbackCount == 1
    check callbackValues[^1] == picker.selectedRange

    check picker.setEndDate(initCalendarDate(2025, 7, 1))
    check picker.startDate == initCalendarDate(2025, 7, 1)
    check picker.endDate == initCalendarDate(2025, 7, 1)
    check callbackCount == 2

    check picker.setEndDate(initCalendarDate(2025, 6, 30), notify = false)
    check picker.startDate == initCalendarDate(2025, 6, 30)
    check picker.endDate == initCalendarDate(2025, 6, 30)
    check callbackCount == 2

    picker.clearStartDate()
    check not picker.hasStartDate
    check picker.hasEndDate
    check picker.accessibilityValue() == "Until Jun 30, 2025"
    check callbackCount == 3

    picker.clearEndDate(notify = false)
    check picker.selectedRange.isEmpty()
    check callbackCount == 3
    check picker.accessibilityValue() == "No dates selected"

    let invalid = initDateRange(
      startDate = endDate, hasStartDate = true, endDate = start, hasEndDate = true
    )
    check not picker.setSelectedRange(invalid)
    check picker.selectedRange.isEmpty()
    check callbackCount == 3

  test "date range picker propagates popup presentation to both buttons":
    let picker = newDateRangePicker(frame = rect(0, 0, 280, 34))

    picker.popupPresentation = ppInline

    check picker.startButton.popupPresentation == ppInline
    check picker.endButton.popupPresentation == ppInline
