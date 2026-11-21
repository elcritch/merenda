## Colors shared by terminal themed content and terminal views.

import ../foundation/types

type TerminalPalette* = object
  colors*: array[16, Color]
  foreground*, background*: Color
  selection*, cursor*: Color

func initTerminalPalette*(): TerminalPalette =
  TerminalPalette(
    colors: [
      color(0.10, 0.11, 0.13, 1.0),
      color(0.80, 0.22, 0.25, 1.0),
      color(0.31, 0.72, 0.36, 1.0),
      color(0.85, 0.69, 0.30, 1.0),
      color(0.30, 0.49, 0.85, 1.0),
      color(0.70, 0.36, 0.78, 1.0),
      color(0.27, 0.70, 0.73, 1.0),
      color(0.78, 0.79, 0.82, 1.0),
      color(0.35, 0.37, 0.41, 1.0),
      color(0.96, 0.39, 0.41, 1.0),
      color(0.49, 0.86, 0.49, 1.0),
      color(0.98, 0.82, 0.43, 1.0),
      color(0.46, 0.65, 0.96, 1.0),
      color(0.84, 0.51, 0.91, 1.0),
      color(0.45, 0.86, 0.88, 1.0),
      color(0.94, 0.94, 0.95, 1.0),
    ],
    foreground: color(0.86, 0.87, 0.89, 1.0),
    background: color(0.055, 0.06, 0.075, 1.0),
    selection: color(0.25, 0.43, 0.72, 0.72),
    cursor: color(0.88, 0.89, 0.91, 0.66),
  )
