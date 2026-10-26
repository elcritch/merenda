## Compact actions shared by Kosmo's document viewer toolbars.

import ../nimkit as nimkit

const RefreshIconSvg =
  """<svg width="16" height="16" viewBox="0 0 24 24"><path d="M19 4v6h-6l2.4-2.4A6 6 0 1 0 18 12h2a8 8 0 1 1-3.2-6.4L19 4z"/></svg>"""

var refreshIcon {.threadvar.}: nimkit.SvgMtsdfResource

proc newViewerRefreshButton*(label: string): nimkit.Button =
  ## Create a compact icon button with a readable accessibility label and tooltip.
  if refreshIcon.len == 0:
    refreshIcon = nimkit.newSvgMtsdfResource(RefreshIconSvg, "kosmo-viewer-refresh")
  result = nimkit.newButton(label)
  result.addStyleClass(nimkit.ToolbarButtonStyleClass)
  result.icon = refreshIcon
  result.accessibilityLabel = label
  result.toolTip = label
