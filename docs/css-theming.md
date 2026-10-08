# CSS themes

Style NimKit controls with a stylesheet while keeping your existing theme's
fonts, chrome delegates and untouched metrics. CSS uses Stylus 0.1.5 for
tokenization and compiles to the same immutable themes that NimKit uses for
drawing and sizing.

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
`table-header-cell`, `menu-bar-item`, etc. Type names are case insensitive;
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

| View/control family | Styling coverage |
| --- | --- |
| Ordinary Views | Background painting; geometry stays under NimKit layout APIs |
| Buttons and text controls | Their existing text, face, border, corner, padding, minimum-size and focus metrics |
| Other semantic control roles | Properties consumed by that role's existing style resolver |

A property only affects behavior that the role already exposes. Ordinary Views
do not acquire borders or text drawing from a CSS declaration. `padding` is a
control style metric, not a replacement for `StackView.edgeInsets` or constraints.
Margins, display/position/width/height, percentages for geometry, `em`, `rem`,
`calc()`, gradients, font fallback lists, border shorthand, padding longhands,
animations and at-rules are unsupported and diagnosed.

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
