import std/unittest

import figdraw

import merenda/nimkit

suite "NimKit date pickers":
  test "calendar dates provide validation, ordering, and formatting":
    let
      leapDay = initCalendarDate(2024, 2, 29)
      ordinaryFebruary = initCalendarDate(2025, 2, 28)
      invalid = initCalendarDate(2025, 2, 29)

    check leapDay.isValidCalendarDate()
    check leapDay.daysInMonth() == 29
    check ordinaryFebruary.isValidCalendarDate()
    check ordinaryFebruary.daysInMonth() == 28
    check not invalid.isValidCalendarDate()
    check initCalendarDate(2025, 7, 1).weekday() == 2
    check initCalendarDate(2025, 7, 1).formatCalendarDate() == "Jul 01, 2025"
    check initCalendarDate(2025, 7, 1).formatCalendarMonth() == "July 2025"
    check initCalendarDate(2025, 6, 30) < initCalendarDate(2025, 7, 1)
    check initCalendarDate(2025, 7, 1) <= initCalendarDate(2025, 7, 1)
    check initCalendarDate(2025, 13, 1).daysInMonth() == 0

  test "date picker selection updates state and invokes its callback":
    let
      initial = initCalendarDate(2025, 7, 24)
      next = initCalendarDate(2025, 8, 3)
      picker = newDatePicker(initial)
    var
      selectedCount = 0
      callbackDate: CalendarDate
    picker.onSelect = proc(date: CalendarDate) =
      inc selectedCount
      callbackDate = date

    check picker.selectedDate == initial
    check picker.displayedMonth == initCalendarDate(2025, 7, 1)
    check picker.hasSelectedDate
    check picker.sizeThatFits() == datePickerDefaultSize()
    picker.selectDate(next)
    check selectedCount == 1
    check callbackDate == next
    check picker.selectedDate == next
    check picker.displayedMonth == initCalendarDate(2025, 8, 1)
    check picker.accessibilityValue() == "Aug 03, 2025"

    picker.hasSelectedDate = false
    check not picker.hasSelectedDate
    check picker.accessibilityValue() == "No date selected"

  test "date picker uses themed light and dark calendar colors":
    let
      picker =
        newDatePicker(initCalendarDate(2025, 7, 24), frame = rect(0, 0, 252, 244))
      darkAppearance = initAppearance(initDarkBSDTheme())
      darkStyle = darkAppearance.resolveBoxStyle(controlStyle(srDatePicker))
      darkSelectedStyle =
        darkAppearance.resolveBoxStyle(controlStyle(srDatePicker, {ssSelected}))
      lightAppearance = initAppearance(initMacOSTheme())
      lightStyle = lightAppearance.resolveBoxStyle(controlStyle(srDatePicker))
      renders = buildRenders(picker, darkAppearance)

    check darkStyle.box.fill ==
      darkAppearance.fillToken("comboBox.item.fill", fill(color(1.0, 1.0, 1.0, 1.0)))
    check darkStyle.text.color ==
      darkAppearance.colorToken("comboBox.item.text.color", color(0.0, 0.0, 0.0, 1.0))
    check darkStyle.box.fill.centerColor().r < 0.5'f32
    check darkStyle.text.color.r > 0.5'f32
    check darkSelectedStyle.box.fill ==
      darkAppearance.fillToken("accent", fill(color(0.0, 0.0, 0.0, 1.0)))
    check lightStyle.box.fill.centerColor().r > darkStyle.box.fill.centerColor().r
    check PopupDrawLevel in renders.layers

    var hasThemedCalendarSurface = false
    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == darkStyle.box.fill:
        hasThemedCalendarSurface = true
    check hasThemedCalendarSurface

  test "date picker button opens an inline picker and forwards selection":
    let
      selected = initCalendarDate(2025, 7, 24)
      root = newView(frame = rect(0, 0, 400, 360))
      window = newWindow("Date Picker", frame = rect(0, 0, 400, 360))
      button = newDatePickerButton("From", selected, rect(10, 10, 140, 32))
      action = actionSelector("testDatePickerAction")
    var
      selectedCount = 0
      callbackDate: CalendarDate
      actionCount = 0
    button.onSelect = proc(date: CalendarDate) =
      inc selectedCount
      callbackDate = date
    button.target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        check sender == DynamicAgent(button)
        inc actionCount
      ,
    )
    button.action = action
    root.addSubview(button)
    window.setContentView(root)
    button.popupPresentation = ppInline

    check button.title == "From · Jul 24, 2025"
    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(20, 20))
    check button.popupOpen()
    let picker = button.datePicker()
    check not picker.isNil
    check picker.superview() == root
    check window.hasActiveTransientSession()

    # July 23 is in the fourth calendar row and Wednesday column.
    let datePoint = picker.pointToWindow(initPoint(125.5, 166.0))
    check window.mouseDownAt(datePoint)
    check window.mouseUpAt(datePoint)
    check selectedCount == 1
    check callbackDate == initCalendarDate(2025, 7, 23)
    check actionCount == 1
    check button.selectedDate == callbackDate
    check button.title == "From · Jul 23, 2025"
    check not button.popupOpen()
    check button.datePicker().isNil
    check not window.hasActiveTransientSession()
