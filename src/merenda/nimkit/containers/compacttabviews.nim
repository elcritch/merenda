## Compact, icon-only tabs for switching between utility views.

import sigils/core

import ../accessibility/accessibility
import ../controls/buttons
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/views
from ../view/viewgeometry import setFrameFromLayout

export views

const
  DefaultCompactTabBarHeight* = 32.0'f32
  DefaultCompactTabWidth* = 36.0'f32
  DefaultCompactTabIconSize* = 18.0'f32

type
  CompactTabItem* = object
    xIdentifier: string
    xTitle: string
    xIcon: SvgMtsdfResource
    xView: View
    xEnabled: bool

  CompactTabButton = ref object of Button
    xIcon: SvgMtsdfResource

  CompactTabView* = ref object of View
    xItems: seq[CompactTabItem]
    xButtons: seq[CompactTabButton]
    xSelectedIndex: int
    xTabBarHeight: float32
    xTabWidth: float32

proc selectCompactTabAtIndex*(tabs: CompactTabView, index: int): bool {.discardable.}

func initCompactTabItem*(
    identifier, title: string, icon: SvgMtsdfResource, view: View
): CompactTabItem =
  ## Create an icon tab that owns no close or document-management behavior.
  CompactTabItem(
    xIdentifier: identifier, xTitle: title, xIcon: icon, xView: view, xEnabled: true
  )

proc identifier*(item: CompactTabItem): string =
  item.xIdentifier

proc title*(item: CompactTabItem): string =
  item.xTitle

proc icon*(item: CompactTabItem): lent SvgMtsdfResource =
  item.xIcon

proc view*(item: CompactTabItem): View =
  item.xView

proc enabled*(item: CompactTabItem): bool =
  item.xEnabled

proc len*(tabs: CompactTabView): int =
  tabs.xItems.len

proc items*(tabs: CompactTabView): lent seq[CompactTabItem] =
  tabs.xItems

proc `[]`*(tabs: CompactTabView, index: Natural): CompactTabItem =
  tabs.xItems[index]

proc selectedIndex*(tabs: CompactTabView): int =
  tabs.xSelectedIndex

proc tabBarHeight*(tabs: CompactTabView): float32 =
  tabs.xTabBarHeight

proc `tabBarHeight=`*(tabs: CompactTabView, height: float32) =
  let next = max(height, 0.0'f32)
  if tabs.xTabBarHeight == next:
    return
  tabs.xTabBarHeight = next
  tabs.setNeedsLayout()

proc tabWidth*(tabs: CompactTabView): float32 =
  tabs.xTabWidth

proc `tabWidth=`*(tabs: CompactTabView, width: float32) =
  let next = max(width, 0.0'f32)
  if tabs.xTabWidth == next:
    return
  tabs.xTabWidth = next
  tabs.setNeedsLayout()

proc compactTabButtonStates(button: CompactTabButton): set[WidgetState] =
  result = button.widgetStateSet()
  if button.state() in {bsOn, bsMixed}:
    result.incl ssSelected
  if button.highlighted():
    result.incl {ssHighlighted, ssPressed}

protocol CompactTabButtonDrawing of ViewDrawingProtocol:
  method draw(button: CompactTabButton, context: DrawContext) =
    let
      states = button.compactTabButtonStates()
      styleContext = controlStyle(
        srTab, states, id = button.styleId(), classes = button.styleClasses()
      )
      selected = ssSelected in states
      faceFill = context.appearance.resolveFill(
        styleContext,
        if selected:
          fill(color(0.18, 0.42, 0.88, 0.18))
        elif ssHovered in states or ssHighlighted in states:
          fill(color(0.5, 0.5, 0.5, 0.10))
        else:
          fill(color(0.0, 0.0, 0.0, 0.0)),
        StyleFill,
      )
      iconColor = context.appearance.resolveColor(
        styleContext,
        StyleTextColor,
        if selected:
          color(0.22, 0.50, 0.92, 1.0)
        else:
          color(0.46, 0.49, 0.54, 1.0),
      )
      bounds = button.bounds()
      iconSize = min(
        DefaultCompactTabIconSize,
        max(min(bounds.size.width, bounds.size.height) - 8.0'f32, 0.0'f32),
      )
      iconRect = rect(
        bounds.origin.x + (bounds.size.width - iconSize) * 0.5'f32,
        bounds.origin.y + (bounds.size.height - iconSize) * 0.5'f32,
        iconSize,
        iconSize,
      )
    discard context.addRenderRectangle(
      context.renderRectFor(bounds), faceFill, cornerRadius = 4.0'f32
    )
    if button.xIcon.len > 0:
      context.addSvgMtsdf(iconRect, button.xIcon, fill(iconColor))
    if selected:
      let indicatorFill = context.appearance.resolveFill(
        styleContext, fill(iconColor), StyleSelectionIndicatorFill
      )
      discard context.addRenderRectangle(
        context.renderRectFor(
          rect(
            bounds.minX + 4.0'f32,
            bounds.maxY - 2.0'f32,
            max(bounds.size.width - 8.0'f32, 0.0'f32),
            2.0'f32,
          )
        ),
        indicatorFill,
        cornerRadius = 1.0'f32,
      )

protocol CompactTabViewLayout of ViewLayoutProtocol:
  method layoutSubviews(tabs: CompactTabView) =
    let bounds = tabs.bounds()
    for index, button in tabs.xButtons:
      button.setFrameFromLayout(
        rect(
          index.float32 * tabs.xTabWidth,
          0.0'f32,
          min(
            tabs.xTabWidth,
            max(bounds.size.width - index.float32 * tabs.xTabWidth, 0.0'f32),
          ),
          min(tabs.xTabBarHeight, bounds.size.height),
        )
      )
    let contentFrame = rect(
      0.0'f32,
      min(tabs.xTabBarHeight, bounds.size.height),
      bounds.size.width,
      max(bounds.size.height - tabs.xTabBarHeight, 0.0'f32),
    )
    for item in tabs.xItems:
      if not item.xView.isNil:
        item.xView.setFrameFromLayout(contentFrame)

protocol CompactTabViewDrawing of ViewDrawingProtocol:
  method draw(tabs: CompactTabView, context: DrawContext) =
    let
      styleContext = controlStyle(
        srTabPanel,
        tabs.widgetStateSet(),
        id = tabs.styleId(),
        classes = tabs.styleClasses(),
      )
      backgroundFill = context.appearance.resolveFill(
        styleContext, fill(color(0.0, 0.0, 0.0, 0.0)), StyleFill
      )
      borderColor = context.appearance.resolveColor(
        styleContext, StyleBorderColor, color(0.42, 0.44, 0.48, 0.28)
      )
    discard
      context.addRenderRectangle(context.renderRectFor(tabs.bounds()), backgroundFill)
    discard context.addRenderRectangle(
      context.renderRectFor(
        rect(0.0'f32, tabs.xTabBarHeight - 1.0'f32, tabs.bounds().size.width, 1.0'f32)
      ),
      borderColor,
    )

protocol CompactTabViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(tabs: CompactTabView): AccessibilityRole =
    arTabGroup

  method accessibilityValue(tabs: CompactTabView): string =
    if tabs.xSelectedIndex notin 0 ..< tabs.xItems.len:
      ""
    else:
      tabs.xItems[tabs.xSelectedIndex].title()

  method isAccessibilityElement(tabs: CompactTabView): bool =
    true

proc selectCompactTabAtIndex*(tabs: CompactTabView, index: int): bool =
  ## Select a utility tab and show only its associated view.
  if tabs.isNil or index notin 0 ..< tabs.xItems.len or not tabs.xItems[index].xEnabled:
    return
  tabs.xSelectedIndex = index
  for buttonIndex, button in tabs.xButtons:
    button.state = if buttonIndex == index: bsOn else: bsOff
    button.needsDisplay = true
  for itemIndex, item in tabs.xItems:
    if not item.xView.isNil:
      item.xView.hidden = itemIndex != index
  tabs.needsDisplay = true
  true

proc addCompactTabItem*(tabs: CompactTabView, item: CompactTabItem) =
  ## Add a utility tab and its content view.
  if tabs.isNil or item.xView.isNil:
    return
  let
    index = tabs.xItems.len
    button = CompactTabButton(xIcon: item.xIcon)
    weakTabs = tabs.unsafeWeakRef()
    action = actionSelector("selectCompactTab" & $index)
  initButtonFields(button, "")
  button.buttonType = btMomentary
  button.accessibilityLabel = item.xTitle
  button.toolTip = item.xTitle
  button.enabled = item.xEnabled
  discard button.withProtocol(CompactTabButtonDrawing)
  button.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      if not weakTabs.isNil:
        discard weakTabs[].selectCompactTabAtIndex(index)
    ,
  )
  button.action = action
  tabs.xItems.add item
  tabs.xButtons.add button
  tabs.addSubview(item.xView)
  tabs.addSubview(button, positioned = svpAbove)
  if tabs.xSelectedIndex < 0:
    discard tabs.selectCompactTabAtIndex(0)
  else:
    item.xView.hidden = true
  tabs.setNeedsLayout()

proc newCompactTabView*(
    items: openArray[CompactTabItem] = [], frame: Rect = AutoRect
): CompactTabView =
  ## Create an icon-only utility view switcher with no close buttons.
  result = CompactTabView(
    xSelectedIndex: -1,
    xTabBarHeight: DefaultCompactTabBarHeight,
    xTabWidth: DefaultCompactTabWidth,
  )
  result.initViewFields(frame)
  result.clipsToBounds = true
  result.accessibilityElement = true
  discard result.withProtocol(CompactTabViewLayout)
  discard result.withProtocol(CompactTabViewDrawing)
  discard result.withProtocol(CompactTabViewAccessibility)
  for item in items:
    result.addCompactTabItem(item)
  result.applyInitialFrame(frame)
