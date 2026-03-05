import std/unittest

import knutella/appkit

suite "appkit nscell font defaults":
  test "setType text cell uses Cocotron system font size":
    let cell = NSCell.new()
    cell.setType(NSTextCellType)
    check(abs(cell.font().pointSize() - 12.0) < 0.01)

  test "setControlSize applies Cocotron user font size mapping":
    let cell = NSCell.new()

    cell.setControlSize(NSRegularControlSize)
    check(abs(cell.font().pointSize() - 13.0) < 0.01)

    cell.setControlSize(NSSmallControlSize)
    check(abs(cell.font().pointSize() - 11.0) < 0.01)

    cell.setControlSize(NSMiniControlSize)
    check(abs(cell.font().pointSize() - 9.0) < 0.01)
