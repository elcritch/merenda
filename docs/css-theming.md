# CSS themes

Style NimKit controls with a stylesheet while keeping your existing theme's
fonts, chrome delegates and untouched metrics. CSS uses Stylus 0.1.5 for
tokenization and compiles to the same immutable themes that NimKit uses for
drawing, sizing and native constraint layout.

```nim
import merenda/nimkit

let parsed = parseCssTheme("""
  :root { --accent: #406de0; --gap: 8px; }
  button.primary {
    background: var(--accent);
    color: white;
    padding: var(--gap);
    border-radius: 10px;
  }
  button.primary:hover { background: #5683f2; }
  text-field:focus { -nimkit-focus-ring-color: #406de0; }
""", initThemeByName("macos"))

button.addStyleClass("primary")
window.setAppearance(initAppearance(parsed.theme))
```

Use `loadCssTheme("theme.css", base)` to read a file. Both functions return
`CssThemeResult`, containing a usable `theme` and `diagnostics`. Diagnostics
identify invalid or unsupported declarations with a one-based source line and
byte column. Invalid literal declarations are skipped. Invalid selectors discard
their whole rule, including a selector list, so an unsupported selector cannot
accidentally style unrelated controls. Missing files raise `IOError` or `OSError`.
The caller decides whether diagnostics should prevent installation.

The [CSS demo](../examples/css_theme_demo.nim) loads a
[sidecar stylesheet](../examples/css_theme_demo.css). Edit it and click **Reload
CSS** to rebuild the window's appearance. Reloading is explicit; no watcher runs
in the background.

## Selectors

Selectors use semantic control roles, `view.styleId`, `view.styleClasses`, and
the control's current widget states. For example:

```css
#save { color: white; }
.primary.toolbar:hover { background: royalblue; }
button.primary, text-field.search:focus { border-width: 2px; }
* { font-size: 15px; }
```

Role names are the `StyleRole` suffix in lowercase kebab case: `button`,
`text-field`, `text-view`, `mono-text-view`, `scroll-view`, `document-tab`,
`table-header-cell`, `menu-bar-item`, `stack-view`, `grid-view`, etc. Type names are case insensitive;
ids and classes are case sensitive. `checkbox` aliases `check-box`, `radio`
aliases `radio-button`, and `label` means `text-field` with its built-in `label`
class. Native semantic role inheritance still applies: `button` also styles
steppers, and `tab` also styles document tabs and menu bar items.

Supported pseudo classes are `:hover`, `:active`, `:focus`, `:focus-visible`,
`:focus-within`, `:disabled`, `:selected`, `:checked`, `:open`, `:highlighted`,
`:pressed`, `:accent`, `:alternating`, and `:invalid`. `:checked` aliases
`:selected`. State availability follows the existing control behavior; listing
a pseudo class does not add a new state transition to a widget.

`:root` is a standalone theme-variable selector. A mixed list such as
`button, :root` is invalid. Tree combinators (`>`, space, `+`, `~`), attribute
selectors, functional pseudo classes and repeated ids are unsupported and
diagnosed. Compound controls expose their existing semantic style roles rather
than a browser DOM of arbitrary internal descendants.

## Properties

Lengths use `px` or unitless numbers, interpreted as NimKit logical pixels.
Colors accept names, `transparent`, 3/4/6/8 digit hex notation, `rgb()` and
`rgba()` with numeric or percentage components.

| Property | Meaning |
| --- | --- |
| `color` | Control text color |
| `background`, `background-color` | View background or control face fill |
| `border-color`, `border-width` | Existing control border |
| `border-radius` | One to four corner radii in CSS order |
| `font-family` | One family name, quoted when it contains spaces; clears exact face overrides |
| `font-size` | Control text size |
| `font-style` | `normal`, `italic`, or `oblique` |
| `padding` | One to four values in CSS order, applied to control text/padding metrics |
| `box-shadow` | `none`, or comma-separated drop/inset shadows |
| `-nimkit-chrome` | Installed chrome delegate name, such as `flat-transparent` |
| `-nimkit-minimum-size` | One uniform size or two width/height values |
| `-nimkit-focus-ring-color` | Focus ring color |
| `-nimkit-focus-ring-width` | Focus ring width |
| `-nimkit-focus-ring-inset` | Focus ring inset; negative values extend outward |

Shadow syntax is `[inset] x y [blur [spread]] [color]`. Offsets, spread and
focus-ring inset may be negative; ordinary padding, blur, border width, size
and corner radii may not. Nonfinite lengths are rejected.

All numeric values must be finite. Sizes, insets, gaps and ordinary metrics
must be nonnegative; constraint edge offsets may be signed. Unitless factors
are strictly positive; knob value tint is between 0 and 1. A scalar variable
can supply one size/inset/gap value and is revalidated for the destination key.
A size accepts one uniform or two width/height values; insets use CSS
(top/right/bottom/left) order. Fill extensions currently accept solid colors.

The tables name the exact public StyleKey and its existing consumer. A property
only affects behavior that the widget exposes. Ordinary Views paint backgrounds
and participate in constraints; their text, borders and chrome still belong to
control drawing. `-nimkit-minimum-size` is an intrinsic/control metric;
`min-width` is a required solver bound.

| Extended property | StyleKey | Consumer | Metric state dependency |
| --- | --- | --- | --- |
| `-nimkit-selection-color` | `StyleSelectionColor` | TextField/TextView selection | No |
| `-nimkit-cursor-color` | `StyleCursorColor` | MonoTextView cursor | No |
| `-nimkit-mark-color` | `StyleMarkColor` | CheckBox/Radio marks, ComboBox arrow, SplitView grip | No |
| `-nimkit-text-highlight-color` | `StyleTextHighlightColor` | Button text highlight | No |
| `-nimkit-text-shadow-color` | `StyleTextShadowColor` | Button text shadow | No |
| `-nimkit-knob-fill` | `StyleKnobFill` | Slider/Switch/Scroller knob | No |
| `-nimkit-knob-border-color` | `StyleKnobBorderColor` | Slider/Switch/Scroller knob | No |
| `-nimkit-knob-shadows` | `StyleKnobShadows` | Slider/Switch/Scroller knob | No |
| `-nimkit-highlight-fill` | `StyleHighlightFill` | Slider/Progress active track | No |
| `-nimkit-maximum-highlight-fill` | `StyleMaximumHighlightFill` | Slider maximum active track | No |
| `-nimkit-alternating-fill` | `StyleAlternatingFill` | Table row drawing | No |
| `-nimkit-indicator-fill` | `StyleIndicatorFill` | ComboBox arrow face | No |
| `-nimkit-drop-indicator-fill` | `StyleDropIndicatorFill` | Table/Outline drop marker | No |
| `-nimkit-insertion-indicator-fill` | `StyleInsertionIndicatorFill` | Table header insertion marker | No |
| `-nimkit-column-selection-fill` | `StyleColumnSelectionFill` | Table selected column | No |
| `-nimkit-column-hover-fill` | `StyleColumnHoverFill` | Table hovered column | No |
| `-nimkit-indicator-size` | `StyleIndicatorSize` | Choice/Switch sizing, Slider/Progress track height, ComboBox arrow, Split grip, IconLabel | Yes |
| `-nimkit-indicator-spacing` | `StyleIndicatorSpacing` | Choice/IconLabel sizing | Yes |
| `-nimkit-width-factor` | `StyleWidthFactor` | Switch width; unitless number ≥ 0.000001 | Yes |
| `-nimkit-knob-size` | `StyleKnobSize` | Slider/Progress knob metric | Yes |
| `-nimkit-knob-inset` | `StyleKnobInset` | Switch knob inset | Yes |
| `-nimkit-knob-size-factor` | `StyleKnobSizeFactor` | Switch knob shape; unitless number ≥ 0.000001 | Yes |
| `-nimkit-knob-value-tint` | `StyleKnobValueTint` | Slider tint; unitless 0–1 | No |
| `-nimkit-edge-inset` | `StyleEdgeInset` | Tab inset | Yes |
| `-nimkit-item-gap` | `StyleItemGap` | Tab gap | Yes |
| `-nimkit-overlap` | `StyleOverlap` | Tab panel overlap | Yes |
| `-nimkit-row-height` | `StyleRowHeight` | Table default row geometry | Yes |
| `-nimkit-header-height` | `StyleHeaderHeight` | Table header geometry | Yes |
| `-nimkit-resize-handle-width` | `StyleResizeHandleWidth` | Table header resize hit region | Yes |
| `-nimkit-drag-threshold` | `StyleDragThreshold` | Table header drag threshold | No |
| `-nimkit-autoscroll-edge` | `StyleAutoscrollEdge` | Table header drag autoscroll | No |
| `-nimkit-title-height` | `StyleTitleHeight` | Box title height | Yes |
| `-nimkit-title-gap` | `StyleTitleGap` | Box title gap | Yes |
| `-nimkit-separator-thickness` | `StyleSeparatorThickness` | Box/Split separator thickness | Yes |
| `-nimkit-minimum-size` | `StyleMinimumSize` | Control intrinsic minimum | Yes |
| `-nimkit-maximum-size` | `StyleMaximumSize` | Tab maximum width | Yes |
| `-nimkit-segment-size` | `StyleSegmentSize` | Tab segment height | Yes |
| `-nimkit-text-insets` | `StyleTextInsets` | Control text layout | Yes |
| `-nimkit-language` | `StyleLanguage` | Text shaping; language tag keyword/string | Yes |
| `-nimkit-selection-indicator-position` | `StyleSelectionIndicatorPosition` | DocumentTabs; `none/top/bottom/left/right/leading/trailing` | No |
| `-nimkit-selection-indicator-fill` | `StyleSelectionIndicatorFill` | DocumentTabs/CompactTabView indicator | No |
| `-nimkit-selection-indicator-insets` | `StyleSelectionIndicatorInsets` | DocumentTabs indicator insets | Yes |
| `-nimkit-selection-indicator-size` | `StyleSelectionIndicatorSize` | DocumentTabs indicator thickness | Yes |
| `-nimkit-selection-indicator-radius` | `StyleSelectionIndicatorCornerRadius` | DocumentTabs indicator corners | No |
| `-nimkit-close-button-position` | `StyleCloseButtonPosition` | DocumentTabs; `left/right/leading/trailing` | Yes |
| `-nimkit-pinstripe-color` | `StyleBackgroundPinstripeColor` | Themed root background stripes | No |
| `-nimkit-pinstripe-highlight-color` | `StyleBackgroundPinstripeHighlightColor` | Themed root background stripe highlight | No |
| `-nimkit-pinstripe-period` | `StyleBackgroundPinstripePeriod` | Themed root background stripe spacing | No |
| `-nimkit-pinstripe-height` | `StyleBackgroundPinstripeHeight` | Themed root background stripe thickness | No |

Table row/header metrics resolve live until `rowHeight=`/`tableHeaderHeight=`
explicitly supplies a native value, including an assignment of the current native
default. Per-row overrides and delegate heights retain their native precedence.
Replacing CSS restores untouched native fallback values. Table column width,
minimum and maximum width remain native constructor/setter/model properties;
`-nimkit-column-width`, `-nimkit-column-min-width` and `-nimkit-column-max-width`
are unsupported and diagnosed.

Pinstripes apply only when `usesThemedRootBackground` is enabled. Zero period or
height disables them. The renderer increases pitch to at least one logical pixel,
twice the stripe height, and enough to fit at most 4096 bands; it also stops if
floating-point positions stop advancing.

## Edge pinning and constraints

Style geometry through the native solver:

```css
#toolbar { left: 16px; right: 16px; top: 12px; height: 36px; }
#sidebar { left: 16px; top: 60px; bottom: 16px; width: 25%; min-width: 120px; }
#editor {
  right: 16px; bottom: 16px;
  -nimkit-constraints: left == #sidebar.right + 12px,
                       top == #toolbar.bottom + 12px,
                       width >= 180px priority(high);
}
.preview { -nimkit-constraints: width == self.height * 1.5; }
.content { inset: 12px 20px; }
```

| Property | StyleKey | Constraint |
| --- | --- | --- |
| `width`, `height` | `StyleLayoutWidth`, `StyleLayoutHeight` | Preferred equality at priority 999; nonnegative length or parent-relative percentage |
| `min-width`, `min-height` | `StyleLayoutMinWidth`, `StyleLayoutMinHeight` | Required lower bound; nonnegative length |
| `max-width`, `max-height` | `StyleLayoutMaxWidth`, `StyleLayoutMaxHeight` | Required upper bound; nonnegative length |
| `left`, `top` | `StyleLayoutLeft`, `StyleLayoutTop` | Required matching parent edge plus signed offset |
| `right`, `bottom` | `StyleLayoutRight`, `StyleLayoutBottom` | Required matching parent edge minus signed offset |
| `inset`, `-nimkit-pin-edges` | Four edge keys above | 1–4 values in CSS order; mixed `auto` components permitted |
| `-nimkit-constraints` | `StyleLayoutConstraints` | Explicit comma-separated anchor equations |

`auto` clears an individual size/bound/edge declaration, and `none` clears the
explicit list. Percentages apply only to `width`/`height`; zero percent is valid.
Required bounds clamp preferred dimensions, and opposing pins determine size
even when a preferred width/height is present. These dimensions describe the
native alignment rectangle, with the same bounds offsets, baseline offsets,
alignment insets and flipped coordinates as authored anchors.

An explicit equation has this grammar:

```
attribute (== | = | >= | <=)
  (length | target.attribute [* number] [(+ | -) length])
  [priority(required | high | low | fitting | number)]
```

Attributes are `left/right/leading/trailing/center-x`, `top/bottom/center-y`,
`first-baseline/last-baseline`, `width/height`. Targets are `self`, `parent`, and
`#styleId` among direct siblings. IDs are case sensitive and must identify one
sibling. Position axes must match; width/height ratios may mix the two dimensions.
Multipliers are positive and finite and apply only to dimensions. A constant RHS
requires width/height. Priorities are finite numbers from 1 to 1000; named native
priorities are required=1000, high=750, low=250, fitting=50. The list defaults to
required. `!important` controls cascade selection independently of priority.
`var()` and `calc()` expressions inside lists are unsupported; scalar properties
accept a single length variable. A winning list replaces the complete earlier
list; sizes and edges each have their own cascade key.

Native authored constraints and nonnegative sizes take precedence over required
CSS conflicts. CSS admission visits subjects in solve-tree traversal order.
Within each subject it admits min-width/min-height, then max-width/max-height,
left/top/right/bottom, width/height, and finally explicit entries in order.
A malformed list is skipped atomically during compilation.
An unavailable target or conflicting required entry is skipped at runtime. When
all entries for a subject are rejected, the solve restores its native
participation and diagnoses the rejected entries. RHS references alone do not
suppress their target's autoresizing. CSS retains the autoresizing flag and
existing authored constraint collections; replacing CSS resumes native layout
from the current geometry.

Arranging containers retain ownership of their arranged/content/internal
children. CSS geometry on those children or references to them are diagnosed
and skipped because they move after solving. StackView/GridView, Box, ScrollView,
SplitView, tabs, forms, docks, table/collection/cascading owners, MenuBar,
DateTimePicker and active field editors identify their exact managed views;
ordinary additional subviews remain eligible. CSS may style the container's own
frame. A custom arranging widget can implement `managesSubviewLayout` in its
`ViewLayoutProtocol`. Its optional `layoutStyleContext` supplies its semantic
role and effective widget states.

The solve root keeps its native frame during layout. Style a child to pin it
within that frame. A fitting root can use its own width/height constraints,
including when its parent normally arranges it, but cannot position itself or
reference targets outside the measured subtree. CSS fitting measurements retain
the layout cache and frame; layout and fitting keep separate diagnostics.

```nim
root.layoutSubtreeIfNeeded()
for diagnostic in root.cssLayoutDiagnostics():
  echo diagnostic.viewId, ": ", diagnostic.property, ": ", diagnostic.message
# Measurement diagnostics use root.cssLayoutDiagnostics(fitting = true).
```

Runtime diagnostics describe the latest attempt in that mode, including budget
failures and nonfinite solved geometry. Failed attempts keep prior frames and
cache; they retry after input or solve limits change. Compile diagnostics retain
source locations. Layout work uses existing `LayoutSolveLimits`, including
projected list size before copying, cumulative retry work and one deadline.

## StackView and GridView layout

Container properties resolve without writing the backing fields behind native
setters. One resolved configuration feeds each measurement or arrangement, so
replacing CSS restores the setter fallbacks.

```css
stack-view { gap: 12px; -nimkit-content-insets: 8px 16px; }
stack-view.sidebar { -nimkit-orientation: vertical; -nimkit-distribution: natural; }
grid-view { gap: 10px 18px; -nimkit-column-alignment: center; }
```

| Property | StyleKey | Consumer / values |
| --- | --- | --- |
| `gap` | Row/column gap keys | 1–2 nonnegative lengths; first row, second column |
| `row-gap` | `StyleContainerRowGap` | Physical vertical gap |
| `column-gap` | `StyleContainerColumnGap` | Physical horizontal gap |
| `-nimkit-content-insets` | `StyleContainerInsets` | Stack/Grid insets in CSS order |
| `-nimkit-orientation` | `StyleContainerOrientation` | Stack: `horizontal/vertical` |
| `-nimkit-alignment` | `StyleContainerAlignment`, both axis alignment keys | Stack cross axis; Grid both axes: `fill/leading/center/trailing` |
| `-nimkit-row-alignment` | `StyleContainerRowAlignment` | Grid vertical: `fill/leading/center/trailing` |
| `-nimkit-column-alignment` | `StyleContainerColumnAlignment` | Grid horizontal: `fill/leading/center/trailing` |
| `-nimkit-distribution` | `StyleContainerDistribution` | Stack: `fill/fill-equally/natural/equal-spacing` |

All container and geometry keys are metric state dependencies, including native
ThemeBuilder rules. Stack chooses its main-axis gap after resolving orientation.
Grid uses physical axes. Per-item native sizing policies still apply; CSS does
not introduce per-item browser flow rules. Shorthand importance/specificity/order
applies to every expanded key, so later longhands override their own axis/edge.

Margins, display/position, `em`, `rem`, gradients, font fallback lists, border
shorthand, padding longhands, animations and at-rules are unsupported and
source-diagnosed. CSS does not set events/actions, reactive bindings, resources,
content, accessibility identity or model data.

## Variables, cascade and scope

Root variables contain typed colors, single lengths, keywords/strings or direct
aliases:

```css
:root {
  --accent: #406de0;
  --space: 8px;
  --family: "Ubuntu";
  --action: var(--accent);
}
button { color: var(--action); padding: var(--space); font-family: var(--family); }
```

Variables resolve after all root declarations, so forward references work.
`var(--space)` converts a single length to uniform padding or corner radii.
Arbitrary token substitution, variable expressions, fallback arguments and
variables on ordinary selector rules are unsupported. Missing references,
cycles, reference chains beyond 16 steps and wrong target types produce
diagnostics and leave valid lower declarations in force. The variable candidate
is retained: appending a valid root definition can restore it, and changing a
variable's type revalidates earlier candidates. The diagnostics for retained
rules use the original rule's line/column.

Precedence is the original native theme, then CSS, then explicit programmatic
theme/appearance overrides made after CSS. Within CSS, `!important` wins first,
then specificity (ids; classes and pseudo classes; types), then source order.
Shorthands carry the same rank to every expanded key. A native write after CSS
overrides only that key and remains above subsequently appended stylesheets.
Root-variable importance and native token overrides also survive appends and
builder round trips.

Reparse against the original base to replace a stylesheet:

```nim
let base = initThemeByName("macos")
window.setAppearance(initAppearance(loadCssTheme("theme.css", base).theme))
```

Parse against a previous result to append a stylesheet in the same cascade:

```nim
let first = loadCssTheme("theme.css", base)
let combined = loadCssTheme("application.css", first.theme)
```

Install appearances through the existing application, window or view APIs.
Window/application appearances flow to their inherited subtrees; a view's
explicit appearance keeps its own scope. CSS text properties do not inherit
from a parent view, and variables are theme-wide. Widget state changes redraw
normally; CSS state rules affecting metrics also invalidate intrinsic sizing and
layout. Button hover keeps color interpolation while applying current-state
text and geometry metrics immediately.

Escaped identifiers and NUL outside strings/comments are rejected before
tokenization. Quoted family names support apostrophes and escaped quotes or
backslashes; other CSS string escape forms are diagnosed. The adapter preserves
Stylus 0.1.5 unchanged and guards its tokenizer's nonadvancing edge cases.
