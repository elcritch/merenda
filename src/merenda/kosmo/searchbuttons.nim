## Standard Buttons styled for compact search toolbars.

import ../nimkit as nimkit

const
  ChevronRight = "M6 3 L11 8 L6 13 L4.8 11.8 L8.6 8 L4.8 4.2 Z"
  ChevronDown = "M3 6 L8 11 L13 6 L11.8 4.8 L8 8.6 L4.2 4.8 Z"
  ArrowUp = "M7.2 13 L7.2 5.2 L4.2 8.2 L3 7 L8 2 L13 7 L11.8 8.2 L8.8 5.2 L8.8 13 Z"
  ArrowDown = "M7.2 3 L7.2 10.8 L4.2 7.8 L3 9 L8 14 L13 9 L11.8 7.8 L8.8 10.8 L8.8 3 Z"
  Close =
    "M4.2 3 L8 6.8 L11.8 3 L13 4.2 L9.2 8 L13 11.8 L11.8 13 L8 9.2 L4.2 13 L3 11.8 L6.8 8 L3 4.2 Z"

proc searchIcon(title: string): nimkit.SvgMtsdfResource =
  let path =
    case title
    of "›": ChevronRight
    of "⌄": ChevronDown
    of "↑": ArrowUp
    of "↓": ArrowDown
    of "×", "X": Close
    else: ""
  if path.len > 0:
    result = nimkit.newSvgMtsdfResource(
      "<svg width=\"16\" height=\"16\" viewBox=\"0 0 16 16\"><path d=\"" & path &
        "\"/></svg>",
      "kosmo-search-" & title,
    )

proc newSearchButton*(title: string, symbol = false): nimkit.Button =
  result = nimkit.newButton(title)
  result.addStyleClass(nimkit.ToolbarButtonStyleClass)
  if symbol:
    result.addStyleClass(nimkit.ToolbarSymbolStyleClass)
    result.icon = searchIcon(title)

proc showSearchDisclosure*(button: nimkit.Button, expanded: bool) =
  button.title = if expanded: "⌄" else: "›"
  button.icon = searchIcon(button.title)
