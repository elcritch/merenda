import std/unittest

import merenda/nimkit
import merenda/kosmo/kosmo

suite "Kosmo context panel":
  test "context starts collapsed and can restore its expanded height":
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
      collapsedHeight = context.frame().size.height
    check context.frame().minY == 0
    check not context.expanded()
    check collapsedHeight > 0
    check context.headerButton.title() == "Context"
    check context.headerButton.accessibilityRole() == arDisclosureButton
    check context.headerButton.accessibilityValue() == "collapsed"
    check AccessibilityActionPress in context.headerButton.accessibilityActionNames()
    check AccessibilityActionExpand in context.headerButton.accessibilityActionNames()
    check frontend.sidebarTabs.superview.frame().minY > context.frame().maxY
    let headerBounds = context.headerButton.bounds()
    require frontend.window.clickAt(
      context.headerButton.pointToWindow(
        initPoint(headerBounds.size.width / 2, headerBounds.size.height / 2)
      )
    )
    frontend.contentView.layoutSubtreeIfNeeded()
    check context.expanded()
    check context.headerButton.accessibilityValue() == "expanded"
    let expandedHeight = context.frame().size.height
    check expandedHeight > collapsedHeight

    require frontend.showFindInFiles()
    frontend.contentView.layoutSubtreeIfNeeded()
    check not context.isHidden
    check abs(context.frame().size.height - expandedHeight) < 1
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
    check abs(resizedHeight - (expandedHeight + 40)) < 1
    let oldFrame = frontend.contentView.frame()
    frontend.contentView.frame =
      rect(0, 0, oldFrame.size.width, oldFrame.size.height + 200)
    frontend.contentView.layoutSubtreeIfNeeded()
    check abs(context.frame().size.height - resizedHeight) < 1
    check frontend.sidebarTabs.superview.frame().minY > context.frame().maxY

    require context.headerButton.accessibilityPerformAction(AccessibilityActionCollapse)
    frontend.contentView.layoutSubtreeIfNeeded()
    check not context.expanded()
    check abs(context.frame().size.height - collapsedHeight) < 1
    require context.headerButton.accessibilityPerformAction(AccessibilityActionExpand)
    frontend.contentView.layoutSubtreeIfNeeded()
    check context.expanded()
    check abs(context.frame().size.height - resizedHeight) < 1

    frontend.contentView.frame = rect(0, 0, 640, 240)
    frontend.contentView.layoutSubtreeIfNeeded()
    check context.frame().size.height >= 0
    check frontend.sidebarTabs.frame().size.height >= 0
    check frontend.sidebarTabs.superview.frame().maxY <= sidebar.bounds().maxY + 1
