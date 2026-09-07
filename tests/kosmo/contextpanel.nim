import std/unittest

import merenda/nimkit
import merenda/kosmo/kosmo

suite "Kosmo context panel":
  test "context stays above Files and Find and preserves its height on resize":
    let frontend =
      newKosmoApplication(newApplication("Context Test"), monitorsGitStatus = false)
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    let
      sidebar = frontend.sidebarPane
      context = sidebar.contextPanel
      split = sidebar.splitView
    check split.splitAxis == laVertical
    check split.paneCount() == 2
    check context.frame().minY == 0
    check abs(context.frame().size.height - KosmoContextPanelHeight) < 1
    check frontend.sidebarTabs.superview.frame().minY > context.frame().maxY
    require frontend.showFindInFiles()
    frontend.contentView.layoutSubtreeIfNeeded()
    check not context.isHidden
    check abs(context.frame().size.height - KosmoContextPanelHeight) < 1
    require frontend.showFileExplorer()

    let
      divider = split.dividerRect(0)
      start = split.pointToWindow(
        initPoint(
          divider.minX + divider.size.width / 2, divider.minY + divider.size.height / 2
        )
      )
      finish = initPoint(start.x, start.y + 40)
    require frontend.window.mouseDownAt(start)
    require frontend.window.mouseDraggedAt(finish)
    require frontend.window.mouseUpAt(finish)
    frontend.contentView.layoutSubtreeIfNeeded()
    let resizedHeight = context.frame().size.height
    check abs(resizedHeight - (KosmoContextPanelHeight + 40)) < 1
    let oldFrame = frontend.contentView.frame()
    frontend.contentView.frame =
      rect(0, 0, oldFrame.size.width, oldFrame.size.height + 200)
    frontend.contentView.layoutSubtreeIfNeeded()
    check abs(context.frame().size.height - resizedHeight) < 1
    check frontend.sidebarTabs.superview.frame().minY > context.frame().maxY

    frontend.contentView.frame = rect(0, 0, 640, 240)
    frontend.contentView.layoutSubtreeIfNeeded()
    check context.frame().size.height >= 0
    check frontend.sidebarTabs.frame().size.height >= 0
    check frontend.sidebarTabs.superview.frame().maxY <= sidebar.bounds().maxY + 1
