import std/unittest

import merenda/nimkit

suite "NimKit popup color wells":
  test "color choices update selection state and send actions":
    let
      choices =
        @[
          initPopupColorChoice("Red", color(0.9, 0.2, 0.2, 1.0)),
          initPopupColorChoice("Blue", color(0.2, 0.4, 0.9, 1.0)),
        ]
      well = newPopupColorWell(choices, choices[0].color)
      action = actionSelector("testColorWellAction")
    var actionCount = 0
    well.target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        check sender == DynamicAgent(well)
        inc actionCount
      ,
    )
    well.action = action

    check well.selectedIndex() == 0
    check well.menu().items()[0].state() == bsOn
    check well.menu().items()[1].state() == bsOff
    check well.activateColorAtIndex(1)
    check well.color() == choices[1].color
    check well.selectedIndex() == 1
    check well.menu().items()[0].state() == bsOff
    check well.menu().items()[1].state() == bsOn
    check actionCount == 1
    check well.menu().items()[0].perform(Responder(well))
    check well.color() == choices[0].color
    check actionCount == 2

  test "default palette retains custom colors":
    let
      custom = color(0.13, 0.27, 0.41, 0.73)
      well = newPopupColorWell(custom)
    check well.color() == custom
    check well.selectedIndex() == -1
    check well.choices().len >= 8
