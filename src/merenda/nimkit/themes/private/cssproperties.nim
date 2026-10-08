## Internal CSS property vocabulary shared by compilation and typed resolution.

import ../../foundation/types

type
  CssPropertyKind* = enum
    cpkColor
    cpkFill
    cpkLength
    cpkSize
    cpkInsets
    cpkShadows
    cpkKeyword

  CssPropertySpec* = object
    name*, key*: string
    kind*: CssPropertyKind
    minimum*, maximum*: float32
    keywords*: string
    metric*, unitless*: bool

  CssGeometryProperty* = object
    name*, key*: string
    attribute*: LayoutAttribute
    relation*: LayoutRelation
    priority*: LayoutPriority
    edge*: bool

func property(
    name, key: string,
    kind: CssPropertyKind,
    metric = false,
    minimum = 0.0'f32,
    maximum = float32.high,
    keywords = "",
    unitless = false,
): CssPropertySpec =
  CssPropertySpec(
    name: name,
    key: key,
    kind: kind,
    metric: metric,
    minimum: minimum,
    maximum: maximum,
    keywords: keywords,
    unitless: unitless,
  )

const
  ExtendedCssProperties* = [
    property("-nimkit-selection-color", "selection.color", cpkColor),
    property("-nimkit-cursor-color", "cursor.color", cpkColor),
    property("-nimkit-mark-color", "mark.color", cpkColor),
    property("-nimkit-text-highlight-color", "text.highlight.color", cpkColor),
    property("-nimkit-text-shadow-color", "text.shadow.color", cpkColor),
    property("-nimkit-knob-border-color", "knob.border.color", cpkColor),
    property("-nimkit-pinstripe-color", "background.pinstripe.color", cpkColor),
    property(
      "-nimkit-pinstripe-highlight-color", "background.pinstripe.highlight.color",
      cpkColor,
    ),
    property("-nimkit-knob-fill", "knob.fill", cpkFill),
    property("-nimkit-highlight-fill", "highlight.fill", cpkFill),
    property("-nimkit-maximum-highlight-fill", "highlight.fill.maximum", cpkFill),
    property("-nimkit-alternating-fill", "alternating.fill", cpkFill),
    property("-nimkit-indicator-fill", "indicator.fill", cpkFill),
    property("-nimkit-drop-indicator-fill", "drop.indicator.fill", cpkFill),
    property("-nimkit-insertion-indicator-fill", "insertion.indicator.fill", cpkFill),
    property("-nimkit-column-selection-fill", "column.selection.fill", cpkFill),
    property("-nimkit-column-hover-fill", "column.hover.fill", cpkFill),
    property("-nimkit-selection-indicator-fill", "selection.indicator.fill", cpkFill),
    property("-nimkit-indicator-size", "indicator.size", cpkLength, metric = true),
    property("-nimkit-indicator-spacing", "indicator.spacing", cpkLength, metric = true),
    property(
      "-nimkit-width-factor",
      "width.factor",
      cpkLength,
      metric = true,
      minimum = 0.000001,
      unitless = true,
    ),
    property("-nimkit-knob-size", "knob.size", cpkLength, metric = true),
    property("-nimkit-knob-inset", "knob.inset", cpkLength, metric = true),
    property(
      "-nimkit-knob-size-factor",
      "knob.size.factor",
      cpkLength,
      metric = true,
      minimum = 0.000001,
      unitless = true,
    ),
    property(
      "-nimkit-knob-value-tint",
      "knob.value.tint",
      cpkLength,
      maximum = 1,
      unitless = true,
    ),
    property("-nimkit-edge-inset", "edge.inset", cpkLength, metric = true),
    property("-nimkit-item-gap", "item.gap", cpkLength, metric = true),
    property("-nimkit-overlap", "overlap", cpkLength, metric = true),
    property("-nimkit-row-height", "row.height", cpkLength, metric = true),
    property("-nimkit-header-height", "header.height", cpkLength, metric = true),
    property(
      "-nimkit-resize-handle-width", "resize.handle.width", cpkLength, metric = true
    ),
    property("-nimkit-drag-threshold", "drag.threshold", cpkLength),
    property("-nimkit-autoscroll-edge", "autoscroll.edge", cpkLength),
    property("-nimkit-title-height", "title.height", cpkLength, metric = true),
    property("-nimkit-title-gap", "title.gap", cpkLength, metric = true),
    property(
      "-nimkit-separator-thickness", "separator.thickness", cpkLength, metric = true
    ),
    property(
      "-nimkit-selection-indicator-size",
      "selection.indicator.size",
      cpkLength,
      metric = true,
    ),
    property(
      "-nimkit-selection-indicator-radius", "selection.indicator.corner.radius",
      cpkLength,
    ),
    property("-nimkit-pinstripe-period", "background.pinstripe.period", cpkLength),
    property("-nimkit-pinstripe-height", "background.pinstripe.height", cpkLength),
    property("-nimkit-minimum-size", "minimum.size", cpkSize, metric = true),
    property("-nimkit-maximum-size", "maximum.size", cpkSize, metric = true),
    property("-nimkit-segment-size", "segment.size", cpkSize, metric = true),
    property("-nimkit-text-insets", "text.insets", cpkInsets, metric = true),
    property(
      "-nimkit-selection-indicator-insets",
      "selection.indicator.insets",
      cpkInsets,
      metric = true,
    ),
    property("-nimkit-knob-shadows", "knob.shadows", cpkShadows),
    property("-nimkit-language", "text.language", cpkKeyword, metric = true),
    property(
      "-nimkit-selection-indicator-position",
      "selection.indicator.position",
      cpkKeyword,
      keywords = "none|top|bottom|left|right|leading|trailing",
    ),
    property(
      "-nimkit-close-button-position",
      "close.button.position",
      cpkKeyword,
      metric = true,
      keywords = "left|right|leading|trailing",
    ),
    property("row-gap", "container.row.gap", cpkLength, metric = true),
    property("column-gap", "container.column.gap", cpkLength, metric = true),
    property("-nimkit-content-insets", "container.insets", cpkInsets, metric = true),
    property(
      "-nimkit-orientation",
      "container.orientation",
      cpkKeyword,
      metric = true,
      keywords = "horizontal|vertical",
    ),
    property(
      "-nimkit-alignment",
      "container.alignment",
      cpkKeyword,
      metric = true,
      keywords = "fill|leading|center|trailing",
    ),
    property(
      "-nimkit-row-alignment",
      "container.row.alignment",
      cpkKeyword,
      metric = true,
      keywords = "fill|leading|center|trailing",
    ),
    property(
      "-nimkit-column-alignment",
      "container.column.alignment",
      cpkKeyword,
      metric = true,
      keywords = "fill|leading|center|trailing",
    ),
    property(
      "-nimkit-distribution",
      "container.distribution",
      cpkKeyword,
      metric = true,
      keywords = "fill|fill-equally|natural|equal-spacing",
    ),
  ]

  # Order is part of CSS constraint admission: bounds, pins, preferred sizes.
  CssGeometryProperties* = [
    CssGeometryProperty(
      name: "min-width",
      key: "layout.min.width",
      attribute: atWidth,
      relation: lrGreaterThanOrEqual,
      priority: LayoutPriorityRequired,
    ),
    CssGeometryProperty(
      name: "min-height",
      key: "layout.min.height",
      attribute: atHeight,
      relation: lrGreaterThanOrEqual,
      priority: LayoutPriorityRequired,
    ),
    CssGeometryProperty(
      name: "max-width",
      key: "layout.max.width",
      attribute: atWidth,
      relation: lrLessThanOrEqual,
      priority: LayoutPriorityRequired,
    ),
    CssGeometryProperty(
      name: "max-height",
      key: "layout.max.height",
      attribute: atHeight,
      relation: lrLessThanOrEqual,
      priority: LayoutPriorityRequired,
    ),
    CssGeometryProperty(
      name: "left",
      key: "layout.left",
      attribute: atLeft,
      priority: LayoutPriorityRequired,
      edge: true,
    ),
    CssGeometryProperty(
      name: "top",
      key: "layout.top",
      attribute: atTop,
      priority: LayoutPriorityRequired,
      edge: true,
    ),
    CssGeometryProperty(
      name: "right",
      key: "layout.right",
      attribute: atRight,
      priority: LayoutPriorityRequired,
      edge: true,
    ),
    CssGeometryProperty(
      name: "bottom",
      key: "layout.bottom",
      attribute: atBottom,
      priority: LayoutPriorityRequired,
      edge: true,
    ),
    CssGeometryProperty(
      name: "width",
      key: "layout.width",
      attribute: atWidth,
      priority: LayoutPriority(999),
    ),
    CssGeometryProperty(
      name: "height",
      key: "layout.height",
      attribute: atHeight,
      priority: LayoutPriority(999),
    ),
  ]

func cssPropertyByName*(name: string, spec: var CssPropertySpec): bool =
  for candidate in ExtendedCssProperties:
    if candidate.name == name:
      spec = candidate
      return true

func cssPropertyByKey*(key: string, spec: var CssPropertySpec): bool =
  for candidate in ExtendedCssProperties:
    if candidate.key == key:
      spec = candidate
      return true

func cssGeometryByName*(name: string, spec: var CssGeometryProperty): bool =
  for candidate in CssGeometryProperties:
    if candidate.name == name:
      spec = candidate
      return true

func cssGeometryByKey*(key: string, spec: var CssGeometryProperty): bool =
  for candidate in CssGeometryProperties:
    if candidate.key == key:
      spec = candidate
      return true
