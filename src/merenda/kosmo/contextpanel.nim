## The collapsible context area above Kosmo's Files and Find tabs.

import sigils/core

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout

const
  KosmoContextPanelHeaderHeight* = 24.0'f32
  KosmoContextPanelHeight* = 216.0'f32
    ## Initial expanded height: approximately twelve compact text lines.

type
  KosmoContextPanel* = ref object of nimkit.View
    headerButton*: nimkit.Button
    xExpanded: bool
    xExpandedHeight: float32

  KosmoContextHeaderButton = ref object of nimkit.Button
    panel: WeakRef[KosmoContextPanel]
    closedTriangle, openTriangle: nimkit.SvgMtsdfResource

func expanded*(panel: KosmoContextPanel): bool =
  not panel.isNil and panel.xExpanded

func preferredHeight*(panel: KosmoContextPanel): float32 =
  if panel.expanded(): panel.xExpandedHeight else: KosmoContextPanelHeaderHeight

proc syncHeader(panel: KosmoContextPanel) =
  if panel.isNil or panel.headerButton.isNil:
    return
  panel.headerButton.toolTip =
    if panel.expanded(): "Collapse Context" else: "Expand Context"
  panel.headerButton.needsDisplay = true

proc `expanded=`*(panel: KosmoContextPanel, expanded: bool) =
  ## Expand or collapse Context, preserving the most recent expanded height.
  if panel.isNil or panel.xExpanded == expanded:
    return
  let parent = panel.superview()
  if parent of nimkit.SplitView:
    let splitView = nimkit.SplitView(parent)
    if splitView.paneIndex(panel) == 0:
      if not expanded:
        panel.xExpandedHeight =
          max(splitView.positionOfDivider(0), KosmoContextPanelHeaderHeight)
        splitView.setPositionOfDivider(0, KosmoContextPanelHeaderHeight)
        splitView.setPaneSizeLimits(
          0,
          minSize = KosmoContextPanelHeaderHeight,
          maxSize = KosmoContextPanelHeaderHeight,
        )
      else:
        splitView.setPaneSizeLimits(0, minSize = KosmoContextPanelHeaderHeight)
        splitView.setPositionOfDivider(0, panel.xExpandedHeight)
  panel.xExpanded = expanded
  panel.syncHeader()
  panel.postAccessibilityNotification(nimkit.anExpandedChanged)

proc toggleExpanded*(panel: KosmoContextPanel): bool {.discardable.} =
  ## Toggle Context and report whether the panel exists.
  if panel.isNil:
    return
  panel.expanded = not panel.expanded()
  true

proc activateHeader(button: KosmoContextHeaderButton): bool =
  if button.isNil or button.panel.isNil:
    return
  button.panel[].toggleExpanded()

protocol KosmoContextHeaderDrawing of nimkit.ViewDrawingProtocol:
  method draw(button: KosmoContextHeaderButton, context: nimkit.DrawContext) =
    if button.panel.isNil:
      return
    let
      bounds = button.bounds()
      states = button.widgetStateSet()
      labelStyle = context.appearance.resolveTextFieldStyle(
        nimkit.controlStyle(
          nimkit.srTextField, states, classes = @[nimkit.LabelStyleClass]
        )
      ).text
      arrowRect = nimkit.rect(9, (bounds.size.height - 9) / 2, 9, 9)
      titleRect = nimkit.rect(24, 0, max(bounds.size.width - 32, 0), bounds.size.height)
      headerStyle = nimkit.controlStyle(nimkit.srTableHeader, states)
      background = context.appearance.resolveFill(
        headerStyle, nimkit.fill(nimkit.color(0.88, 0.88, 0.89, 1))
      )
      separator = context.appearance.resolveColor(
        headerStyle, nimkit.StyleBorderColor, nimkit.color(0, 0, 0, 0.16)
      )
    var textStyle = labelStyle
    textStyle.fontSize = 11
    textStyle.fontFace = textStyle.boldFontFace
    context.addRectangle(bounds, background)
    context.addRectangle(
      nimkit.rect(0, 0, bounds.size.width, 1), nimkit.fill(nimkit.color(1, 1, 1, 0.18))
    )
    context.addRectangle(
      nimkit.rect(0, max(bounds.size.height - 1, 0), bounds.size.width, 1),
      nimkit.fill(separator),
    )
    if button.highlighted():
      context.addRectangle(bounds, nimkit.fill(nimkit.color(0, 0, 0, 0.08)))
    context.addSvgMtsdf(
      arrowRect,
      (if button.panel[].expanded(): button.openTriangle else: button.closedTriangle),
      nimkit.fill(textStyle.color),
    )
    context.addText(titleRect, "Context", textStyle)
    if button.isFocusVisible():
      let buttonStyle = context.appearance.resolveButtonStyle(
        nimkit.controlStyle(
          nimkit.srButton,
          states,
          id = button.styleId(),
          classes = button.styleClasses(),
        )
      )
      context.addFocusRing(context.renderRectFor(bounds), buttonStyle.box)

protocol KosmoContextHeaderAccessibility of nimkit.AccessibilityProtocol:
  method accessibilityRole(button: KosmoContextHeaderButton): nimkit.AccessibilityRole =
    nimkit.arDisclosureButton

  method accessibilityLabel(button: KosmoContextHeaderButton): string =
    "Context"

  method accessibilityValue(button: KosmoContextHeaderButton): string =
    if not button.panel.isNil and button.panel[].expanded(): "expanded" else: "collapsed"

  method accessibilityActionNames(button: KosmoContextHeaderButton): seq[string] =
    result = @[nimkit.AccessibilityActionPress]
    if not button.panel.isNil and button.panel[].expanded():
      result.add nimkit.AccessibilityActionCollapse
    else:
      result.add nimkit.AccessibilityActionExpand

  method accessibilityPerformAction(
      button: KosmoContextHeaderButton, action: string
  ): bool =
    if action == nimkit.AccessibilityActionPress:
      return button.activateHeader()
    if button.panel.isNil:
      return
    let expanded = button.panel[].expanded()
    if action == nimkit.AccessibilityActionExpand and not expanded or
        action == nimkit.AccessibilityActionCollapse and expanded:
      return button.activateHeader()

protocol KosmoContextPanelLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoContextPanel) =
    panel.headerButton.setFrameFromLayout(
      nimkit.rect(0, 0, panel.bounds().size.width, KosmoContextPanelHeaderHeight)
    )

proc newKosmoContextPanel*(): KosmoContextPanel =
  ## Create a collapsed Context panel ready for contextual content.
  result = KosmoContextPanel(xExpandedHeight: KosmoContextPanelHeight)
  result.initViewFields()
  result.identifier = "kosmo.context"
  result.accessibilityLabel = "Context"
  result.clipsToBounds = true

  let header = KosmoContextHeaderButton(panel: result.unsafeWeakRef())
  header.closedTriangle = nimkit.newSvgMtsdfResource(
    """<svg width="9" height="9" viewBox="0 0 9 9"><path d="M2 0 L8 4.5 L2 9 Z"/></svg>""",
    "kosmo-context-closed",
  )
  header.openTriangle = nimkit.newSvgMtsdfResource(
    """<svg width="9" height="9" viewBox="0 0 9 9"><path d="M0 2 L9 2 L4.5 8 Z"/></svg>""",
    "kosmo-context-open",
  )
  header.initButtonFields("Context")
  discard header.withProtocol(KosmoContextHeaderDrawing)
  discard header.withProtocol(KosmoContextHeaderAccessibility)
  let weakHeader = header.unsafeWeakRef()
  let toggleAction = nimkit.actionSelector("kosmo.toggleContext")
  header.action = toggleAction
  header.target = nimkit.newActionTarget(toggleAction) do(sender: nimkit.DynamicAgent):
    discard sender
    if not weakHeader.isNil:
      discard weakHeader[].activateHeader()
  header.accessibilityIdentifier = "kosmo.context.header"
  result.headerButton = header
  result.syncHeader()
  result.addSubview(header)
  discard result.withProtocol(KosmoContextPanelLayout)
