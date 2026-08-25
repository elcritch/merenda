## Generic split docking containers for document-style workspaces.

import sigils/core

import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/viewgeometry
import ../view/views
import ./splitviews

export splitviews, views

type
  DockPosition* = enum
    dpCenter
    dpLeft
    dpRight
    dpTop
    dpBottom

  DockPanel* = ref object of View
    xContentView: View

  DockDropTarget* = object
    panel*: DockPanel
    position*: DockPosition
    rect*: Rect

  DockView* = ref object of View
    xPanels: seq[DockPanel]
    xRootView: View
    xDropTarget: DockDropTarget
    xDropIndicator: DockDropIndicator

  DockDropIndicator = ref object of View
    xFill: Color
    xBorderColor: Color

const
  DockEdgeFraction = 0.25'f32
  DockIndicatorFill = color(0.20, 0.48, 0.94, 0.24)
  DockIndicatorBorderColor = color(0.30, 0.60, 1.0, 0.90)

proc valid*(target: DockDropTarget): bool =
  not target.panel.isNil and not target.rect.isEmpty

protocol DockPanelLayout of ViewLayoutProtocol:
  method layoutSubviews(panel: DockPanel) =
    if not panel.xContentView.isNil:
      panel.xContentView.setFrameFromLayout(panel.bounds())

proc initDockPanelFields*(
    panel: DockPanel, contentView: View = nil, frame: Rect = AutoRect
) =
  initViewFields(panel, frame)
  panel.background = color(0.0, 0.0, 0.0, 0.0)
  discard panel.withProtocol(DockPanelLayout)
  panel.xContentView = contentView
  if not contentView.isNil:
    panel.addSubview(contentView)

proc newDockPanel*(contentView: View = nil, frame: Rect = AutoRect): DockPanel =
  result = DockPanel()
  result.initDockPanelFields(contentView, frame)

proc contentView*(panel: DockPanel): View =
  panel.xContentView

proc `contentView=`*(panel: DockPanel, contentView: View) =
  if panel.xContentView == contentView:
    return
  if not panel.xContentView.isNil and panel.xContentView.superview() == panel:
    panel.xContentView.removeFromSuperview()
  panel.xContentView = contentView
  if not contentView.isNil:
    panel.addSubview(contentView)
  panel.setNeedsLayout()

protocol DockDropIndicatorDrawing of ViewDrawingProtocol:
  method draw(indicator: DockDropIndicator, context: DrawContext) =
    let bounds = indicator.bounds()
    discard context.addRenderRectangle(
      context.renderRectFor(bounds),
      fill(indicator.xFill),
      indicator.xBorderColor,
      1.5'f32,
      3.0'f32,
    )

protocol DockDropIndicatorHitTesting of ViewProtocol:
  method pointInside(indicator: DockDropIndicator, point: Point): bool =
    discard indicator
    discard point
    false

proc newDockDropIndicator(): DockDropIndicator =
  result =
    DockDropIndicator(xFill: DockIndicatorFill, xBorderColor: DockIndicatorBorderColor)
  initViewFields(result)
  result.hidden = true
  discard result.withProtocol(DockDropIndicatorDrawing)
  discard result.withProtocol(DockDropIndicatorHitTesting)

protocol DockViewLayout of ViewLayoutProtocol:
  method layoutSubviews(dockView: DockView) =
    if not dockView.xRootView.isNil:
      dockView.xRootView.setFrameFromLayout(dockView.bounds())

proc setRootView(dockView: DockView, view: View) =
  if dockView.xRootView == view:
    return
  if not dockView.xRootView.isNil and dockView.xRootView.superview() == dockView:
    dockView.xRootView.removeFromSuperview()
  dockView.xRootView = view
  if not view.isNil:
    dockView.addSubview(view, svpBelow, dockView.xDropIndicator)
  dockView.setNeedsLayout()

proc initDockViewFields*(dockView: DockView, frame: Rect = AutoRect) =
  initViewFields(dockView, frame)
  dockView.background = color(0.0, 0.0, 0.0, 0.0)
  dockView.xDropIndicator = newDockDropIndicator()
  dockView.addSubview(dockView.xDropIndicator)
  discard dockView.withProtocol(DockViewLayout)

proc newDockView*(frame: Rect = AutoRect): DockView =
  result = DockView()
  result.initDockViewFields(frame)

proc panels*(dockView: DockView): lent seq[DockPanel] =
  dockView.xPanels

proc len*(dockView: DockView): int =
  dockView.xPanels.len

proc rootView*(dockView: DockView): View =
  dockView.xRootView

proc addPanel*(dockView: DockView, panel: DockPanel): bool {.discardable.} =
  if panel.isNil or panel in dockView.xPanels:
    return false
  if not dockView.xRootView.isNil:
    return false
  dockView.xPanels.add panel
  dockView.setRootView(panel)
  true

func splitAxis(position: DockPosition): LayoutAxis =
  case position
  of dpLeft, dpRight: laHorizontal
  of dpTop, dpBottom: laVertical
  of dpCenter: laHorizontal

func insertsBefore(position: DockPosition): bool =
  position in {dpLeft, dpTop}

proc replaceSplitPane(parent: SplitView, oldPane, newPane: View) =
  let index = parent.paneIndex(oldPane)
  if index < 0:
    return
  parent.removePane(oldPane)
  parent.insertPane(newPane, index)

proc splitPanel*(
    dockView: DockView, target, panel: DockPanel, position: DockPosition
): bool {.discardable.} =
  if target.isNil or panel.isNil or target notin dockView.xPanels or
      panel in dockView.xPanels or position == dpCenter:
    return false

  let
    axis = position.splitAxis()
    parent = target.superview()
  if parent of SplitView and SplitView(parent).splitAxis == axis:
    let targetIndex = SplitView(parent).paneIndex(target)
    SplitView(parent).insertPane(
      panel, targetIndex + (if position.insertsBefore(): 0 else: 1)
    )
  else:
    let splitView = newSplitView(axis)
    if parent == dockView:
      dockView.setRootView(splitView)
    elif parent of SplitView:
      SplitView(parent).replaceSplitPane(target, splitView)
    else:
      return false
    if position.insertsBefore():
      splitView.addPane(panel)
      splitView.addPane(target)
    else:
      splitView.addPane(target)
      splitView.addPane(panel)

  dockView.xPanels.add panel
  dockView.setNeedsLayout()
  true

proc collapseSplit(dockView: DockView, splitView: SplitView) =
  if splitView.paneCount() != 1:
    return
  let
    survivor = splitView.panes()[0]
    parent = splitView.superview()
  splitView.removePane(survivor)
  if parent == dockView:
    dockView.setRootView(survivor)
  elif parent of SplitView:
    SplitView(parent).replaceSplitPane(splitView, survivor)

proc removePanel*(dockView: DockView, panel: DockPanel): bool {.discardable.} =
  let index = dockView.xPanels.find(panel)
  if index < 0:
    return false
  let parent = panel.superview()
  if parent == dockView:
    dockView.setRootView(nil)
  elif parent of SplitView:
    let splitView = SplitView(parent)
    splitView.removePane(panel)
    dockView.collapseSplit(splitView)
  elif not parent.isNil:
    panel.removeFromSuperview()
  dockView.xPanels.delete(index)
  dockView.setNeedsLayout()
  true

func edgePosition(bounds: Rect, point: Point): DockPosition =
  if bounds.isEmpty:
    return dpCenter
  let
    horizontal = (point.x - bounds.minX) / bounds.size.width
    vertical = (point.y - bounds.minY) / bounds.size.height
    leftDistance = horizontal
    rightDistance = 1.0'f32 - horizontal
    topDistance = vertical
    bottomDistance = 1.0'f32 - vertical
    nearest = min(min(leftDistance, rightDistance), min(topDistance, bottomDistance))
  if nearest > DockEdgeFraction:
    dpCenter
  elif nearest == leftDistance:
    dpLeft
  elif nearest == rightDistance:
    dpRight
  elif nearest == topDistance:
    dpTop
  else:
    dpBottom

func targetRect(bounds: Rect, position: DockPosition): Rect =
  case position
  of dpCenter:
    bounds
  of dpLeft:
    rect(bounds.minX, bounds.minY, bounds.size.width * 0.5'f32, bounds.size.height)
  of dpRight:
    rect(
      bounds.minX + bounds.size.width * 0.5'f32,
      bounds.minY,
      bounds.size.width * 0.5'f32,
      bounds.size.height,
    )
  of dpTop:
    rect(bounds.minX, bounds.minY, bounds.size.width, bounds.size.height * 0.5'f32)
  of dpBottom:
    rect(
      bounds.minX,
      bounds.minY + bounds.size.height * 0.5'f32,
      bounds.size.width,
      bounds.size.height * 0.5'f32,
    )

proc dropTargetAtPoint*(dockView: DockView, point: Point): DockDropTarget =
  for panel in dockView.xPanels:
    let panelRect = panel.rectToView(panel.bounds(), dockView)
    if panelRect.contains(point):
      let position = panelRect.edgePosition(point)
      return DockDropTarget(
        panel: panel, position: position, rect: panelRect.targetRect(position)
      )

proc dropTarget*(dockView: DockView): DockDropTarget =
  dockView.xDropTarget

proc `dropTarget=`*(dockView: DockView, target: DockDropTarget) =
  dockView.xDropTarget = target
  if target.valid():
    dockView.xDropIndicator.frame = target.rect
    dockView.xDropIndicator.hidden = false
    dockView.xDropIndicator.needsDisplay = true
  else:
    dockView.xDropIndicator.hidden = true

proc clearDropTarget*(dockView: DockView) =
  dockView.dropTarget = DockDropTarget()
