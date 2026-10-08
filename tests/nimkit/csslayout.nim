import std/[os, strutils, unittest]
import figdraw except CornerRadii

import merenda/nimkit
import merenda/nimkit/view/viewbase

type CssIntrinsicView = ref object of View
  naturalSize: Size

type CssTableRowDelegate = ref object of Responder

protocol CssTableRowDelegateMethods of TableViewDelegate:
  method tableRowHeight(
      delegate: CssTableRowDelegate, table: TableView, row: int
  ): float32 =
    if row == 0: 20.0'f32 else: table.rowHeight

protocol CssIntrinsicLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: CssIntrinsicView): IntrinsicSize =
    initIntrinsicSize(view.naturalSize)

proc fixedView(width, height: float32): CssIntrinsicView =
  result = CssIntrinsicView(naturalSize: initSize(width, height))
  initViewFields(result, rect(0, 0, width, height))
  result.autoresizingMaskConstraints = false
  discard result.withProtocol(CssIntrinsicLayout)

proc cssTheme(source: string, base: Theme = initTheme()): Theme =
  let parsed = parseCssTheme(source, base)
  doAssert parsed.diagnostics.len == 0, $parsed.diagnostics
  parsed.theme

proc installCss(view: View, source: string) =
  view.appearance = initAppearance(cssTheme(source))

proc hasDiagnostic(view: View, text: string, fitting = false): bool =
  for diagnostic in view.cssLayoutDiagnostics(fitting):
    if text in diagnostic.message:
      return true

proc cssInputCount(view: View): int =
  for input in view.generatedLayoutSummary():
    if input.source == lisCss:
      result += input.equations

suite "NimKit CSS layout":
  test "edge shorthand expands and tracks parent resize without authored constraints":
    let root = newView(frame = rect(0, 0, 320, 200))
    let child = newView(frame = rect(1, 2, 40, 20))
    child.styleClasses = @["content"]
    root.addSubview(child)
    root.installCss(".content { inset: 12px 20px; }")
    root.layoutSubtreeIfNeeded()
    check child.frame == rect(20, 12, 280, 176)
    check child.constraints.len == 0
    check child.autoresizingMaskConstraints
    check root.cssInputCount == 4
    check root.cssLayoutDiagnostics.len == 0
    root.frame = rect(0, 0, 420, 260)
    root.layoutSubtreeIfNeeded()
    check child.frame == rect(20, 12, 380, 236)
    check root.layoutFeedbackCycles == 0
    let generation = root.layoutGeneration
    root.layoutSubtreeIfNeeded()
    check root.layoutGeneration == generation

  test "CSS pins use the same nested alignment coordinates as native anchors":
    let root = newView(frame = rect(0, 0, 480, 240))
    let parent = newView(frame = rect(140, 30, 220, 120))
    let styled = newView(frame = rect(0, 0, 10, 10))
    let native = newView(frame = rect(0, 0, 10, 10))
    parent.bounds = rect(7, 9, 220, 120)
    parent.alignmentInsets = insets(3, 4, 5, 6)
    styled.alignmentInsets = insets(1, 2, 3, 4)
    native.alignmentInsets = styled.alignmentInsets
    styled.styleId = "styled"
    root.addSubview(parent)
    parent.addSubview(styled)
    parent.addSubview(native)
    native.pinEdges(toView = parent, insets = insets(12, 18))
    root.installCss("#styled { -nimkit-pin-edges: 12px 18px; }")
    root.layoutSubtreeIfNeeded()
    check styled.frame == native.frame
    check root.cssLayoutDiagnostics.len == 0
    parent.flipped = false
    root.layoutSubtreeIfNeeded()
    check styled.frame == native.frame
    check root.cssLayoutDiagnostics.len == 0

  test "preferred percentages clamp to required bounds and pins precede preferred sizes":
    let root = newView(frame = rect(0, 0, 400, 200))
    let child = newView(frame = rect(0, 0, 10, 10))
    child.styleId = "panel"
    root.addSubview(child)
    root.installCss(
      "#panel { left: 8px; top: 10px; width: 25%; min-width: 120px; height: 40px; }"
    )
    root.layoutSubtreeIfNeeded()
    check child.frame == rect(8, 10, 120, 40)
    root.frame = rect(0, 0, 800, 200)
    root.layoutSubtreeIfNeeded()
    check child.frame.size.width == 200
    root.installCss(
      "#panel { left: 8px; right: 12px; width: 60px; top: 10px; height: 40px; }"
    )
    root.layoutSubtreeIfNeeded()
    check child.frame.size.width == 780
    check root.cssLayoutDiagnostics.len == 0

  test "sibling anchors ratios and named priorities resolve in one solve":
    let root = newView(frame = rect(0, 0, 400, 240))
    let sidebar = newView(frame = rect(0, 0, 20, 20))
    let editor = newView(frame = rect(0, 0, 20, 20))
    sidebar.styleId = "sidebar"
    editor.styleId = "editor"
    root.addSubview(sidebar)
    root.addSubview(editor)
    root.installCss(
      """
      #sidebar { left: 16px; top: 20px; width: 100px; height: 180px; }
      #editor { right: 16px; bottom: 20px;
        -nimkit-constraints: left == #sidebar.right + 12px,
                             top == #sidebar.top,
                             width >= 100px priority(high); }
    """
    )
    root.layoutSubtreeIfNeeded()
    check sidebar.frame == rect(16, 20, 100, 180)
    check editor.frame == rect(128, 20, 256, 200)
    check root.cssLayoutDiagnostics.len == 0
    let ratio = cssTheme(
      ".preview { -nimkit-constraints: width == self.height * 1.5, height = 40px priority(required); }"
    )
    editor.styleClasses = @["preview"]
    root.appearance = initAppearance(ratio)
    root.layoutSubtreeIfNeeded()
    check editor.frame.size == initSize(60, 40)

  test "referenced unstyled siblings retain autoresizing and current target geometry":
    let root = newView(frame = rect(0, 0, 300, 150))
    let sibling = newView(frame = rect(30, 10, 40, 20))
    let subject = newView(frame = rect(0, 0, 5, 5))
    sibling.styleId = "reference"
    sibling.autoresizingMask = {cxMinXMargin}
    subject.styleId = "subject"
    root.addSubview(sibling)
    root.addSubview(subject)
    root.installCss(
      "#subject { width: 20px; height: 20px; -nimkit-constraints: left == #reference.right + 5px, top == #reference.top; }"
    )
    root.layoutSubtreeIfNeeded()
    check subject.frame.origin.x == 75
    root.frame = rect(0, 0, 400, 150)
    root.layoutSubtreeIfNeeded()
    check sibling.frame.origin.x == 130
    check subject.frame.origin.x == 175

  test "authored required constraints win and all rejected CSS restores autoresizing":
    let root = newView(frame = rect(0, 0, 300, 150))
    let child = newView(frame = rect(20, 15, 40, 25))
    child.styleId = "subject"
    root.addSubview(child)
    let width = child[atWidth].equalTo(40)
    width.activate()
    root.installCss("#subject { min-width: 80px; }")
    root.layoutSubtreeIfNeeded()
    check child.frame == rect(20, 15, 40, 25)
    check width.isActive
    check root.hasDiagnostic("conflicts")
    check root.cssInputCount == 0
    width.deactivate()
    child.autoresizingMask = {cxMinXMargin}
    root.installCss("#subject { -nimkit-constraints: width == parent.width - 1000px; }")
    root.layoutSubtreeIfNeeded()
    check root.hasDiagnostic("conflicts")
    check root.cssInputCount == 0
    check child.frame.size.width == 40
    root.frame = rect(0, 0, 400, 150)
    root.layoutSubtreeIfNeeded()
    check child.frame.origin.x == 120

  test "missing and duplicate sibling targets are diagnosed without losing native geometry":
    let root = newView(frame = rect(0, 0, 300, 150))
    let child = newView(frame = rect(20, 15, 40, 25))
    child.styleId = "subject"
    root.addSubview(child)
    root.installCss("#subject { -nimkit-constraints: left == #missing.right; }")
    root.layoutSubtreeIfNeeded()
    check root.hasDiagnostic("missing")
    check child.frame == rect(20, 15, 40, 25)
    let first = newView(frame = rect(0, 0, 20, 20))
    let second = newView(frame = rect(0, 0, 20, 20))
    first.styleId = "duplicate"
    second.styleId = "duplicate"
    root.addSubview(first)
    root.addSubview(second)
    root.installCss("#subject { -nimkit-constraints: left == #duplicate.right; }")
    root.layoutSubtreeIfNeeded()
    check root.hasDiagnostic("Duplicate")
    check root.cssInputCount == 0

  test "managed subjects and sibling targets are rejected while additional subviews remain eligible":
    let stack = newStackView(laHorizontal, frame = rect(0, 0, 200, 60))
    let arranged = fixedView(40, 20)
    let extra = newView(frame = rect(0, 0, 10, 10))
    arranged.styleId = "arranged"
    extra.styleId = "extra"
    stack.addArrangedSubview(arranged)
    stack.addSubview(extra)
    stack.installCss(
      "#arranged { width: 999px; } #extra { -nimkit-constraints: left == #arranged.right; }"
    )
    stack.layoutSubtreeIfNeeded()
    check stack.hasDiagnostic("arranged by")
    check stack.hasDiagnostic("target is managed")
    stack.installCss("#extra { inset: 5px; }")
    stack.layoutSubtreeIfNeeded()
    check extra.frame == rect(5, 5, 190, 50)
    check stack.cssLayoutDiagnostics.len == 0

  test "root fitting and layout use separate scratch eligibility and diagnostics in either order":
    for fittingFirst in [true, false]:
      let root = newView(frame = rect(0, 0, 300, 150))
      root.styleId = "root"
      root.installCss("#root { width: 96px; height: 44px; left: 12px; }")
      if fittingFirst:
        check root.fittingSize == initSize(96, 44)
      root.layoutSubtreeIfNeeded()
      check root.frame == rect(0, 0, 300, 150)
      check root.hasDiagnostic("root keeps")
      check root.cssInputCount == 0
      check root.fittingSize == initSize(96, 44)
      check root.hasDiagnostic("root keeps")
      check root.hasDiagnostic("not its position", fitting = true)
      root.setNeedsLayout()
      root.layoutSubtreeIfNeeded()
      check root.frame.size == initSize(300, 150)
      check root.cssInputCount == 0

  test "managed fitting roots accept their own dimensions and reject outside references":
    let stack = newStackView(laHorizontal)
    let child = newView(frame = rect(0, 0, 10, 10))
    child.styleId = "child"
    stack.addArrangedSubview(child)
    stack.installCss(
      "#child { width: 70px; height: 30px; -nimkit-constraints: left == parent.left; }"
    )
    check child.fittingSize == initSize(70, 30)
    check child.hasDiagnostic("not its position", fitting = true)
    check child.frame.size == initSize(10, 10)

  test "scalar variables shorthands auto and list none follow per key cascade":
    let first = cssTheme(
      """
      :root { --gap: 8px; --size: 80px; }
      #panel { inset: var(--gap); width: var(--size);
               -nimkit-constraints: height == 30px; }
      #panel { right: auto; left: 12px; width: auto; -nimkit-constraints: none; }
    """
    )
    let context = controlStyle(srView, id = "panel")
    check first.resolveLayoutConstraints(context, StyleLayoutLeft)[0].constant == 12
    check first.resolveLayoutConstraints(context, StyleLayoutTop)[0].constant == 8
    check first.resolveLayoutConstraints(context, StyleLayoutRight).len == 0
    check first.resolveLayoutConstraints(context, StyleLayoutWidth).len == 0
    check first.resolveLayoutConstraints(context).len == 0
    let invalid = parseCssTheme(
      "#panel { width: 40px; width: var(--color); } :root { --color: red; }"
    )
    check invalid.diagnostics.len == 1
    check invalid.theme.resolveLayoutConstraints(context, StyleLayoutWidth)[0].constant ==
      40
    let repaired = cssTheme(":root { --color: 70px; }", invalid.theme)
    check repaired.resolveLayoutConstraints(context, StyleLayoutWidth)[0].constant == 70

  test "geometry changes react to role state classes ids reload and reparenting":
    let root = newView(frame = rect(0, 0, 300, 180))
    let parent = newView(frame = rect(0, 0, 150, 180))
    let button = newButton("CSS", frame = rect(0, 0, 20, 20))
    button.styleId = "apply"
    root.addSubview(button)
    root.addSubview(parent)
    root.installCss(
      "button { width: 80px; height: 30px; } button:hover { width: 100px; } #apply.wide { width: 120px; } .pinned { inset: 5px; }"
    )
    root.layoutSubtreeIfNeeded()
    check button.frame.size.width == 80
    button.setWidgetState(ssHovered, true)
    root.layoutSubtreeIfNeeded()
    check button.frame.size.width == 100
    button.styleClasses = @["wide"]
    root.layoutSubtreeIfNeeded()
    check button.frame.size.width == 120
    button.styleId = "other"
    root.layoutSubtreeIfNeeded()
    check button.frame.size.width == 100
    button.styleClasses = @["pinned"]
    parent.addSubview(button)
    root.layoutSubtreeIfNeeded()
    check button.frame == rect(5, 5, 140, 170)
    root.appearance = initAppearance(initTheme())
    root.layoutSubtreeIfNeeded()
    check root.cssInputCount == 0
    let oldFrame = button.frame
    root.layoutSubtreeIfNeeded()
    check button.frame == oldFrame

  test "constraint snapshots and public accessors own their lists and target ids":
    let theme = cssTheme(".item { -nimkit-constraints: left == #peer.right + 8px; }")
    let context = controlStyle(srView, classes = @["item"])
    var resolved = theme.resolveLayoutConstraints(context)
    resolved[0].targetId[0] = 'X'
    resolved[0].constant = 99
    check theme.resolveLayoutConstraints(context)[0].targetId == "peer"
    check theme.resolveLayoutConstraints(context)[0].constant == 8
    let snapshot = initThemeBuilder(theme).finish()
    var value: StyleValue
    for rule in snapshot.rules:
      if rule.patch.getStyle(StyleLayoutConstraints, value):
        break
    require value.kind == svConstraints
    value.constraints[0].targetId = "changed"
    check snapshot.resolveLayoutConstraints(context)[0].targetId == "peer"

  test "malformed lists are atomic and invalid dimensions priorities and axes are rejected":
    for declaration in [
      "width == 10px, left ==", "left == 12px", "width == parent.left",
      "left == parent.top", "width == self.height * 0", "width == 1px priority(1001)",
      "width == 1px priority(0)", "width == self.height * 1e999", "width == calc(2px)",
      "width == var(--length)", "width == 10px,",
    ]:
      let parsed = parseCssTheme(
        ".item { -nimkit-constraints: width == 30px; -nimkit-constraints: " & declaration &
          "; }"
      )
      check parsed.diagnostics.len == 1
      check parsed.theme.resolveLayoutConstraints(
        controlStyle(srView, classes = @["item"])
      )[0].constant == 30
    for property in [
      "min-width: 20%", "max-height: 50%", "width: -1px", "height: 1e999px"
    ]:
      check parseCssTheme(".item { " & property & "; }").diagnostics.len == 1

  test "projected CSS generation budgets preserve frames and report the failed attempt":
    let root = newView(frame = rect(0, 0, 300, 180))
    let child = newView(frame = rect(12, 18, 40, 20))
    child.styleId = "child"
    root.addSubview(child)
    var declarations: seq[string]
    for index in 0 ..< 40:
      declarations.add "width >= " & $index & "px priority(low)"
    root.installCss("#child { -nimkit-constraints: " & declarations.join(", ") & "; }")
    root.xLayoutSolveLimits = LayoutSolveLimits(maxConstraints: 20)
    root.layoutSubtreeIfNeeded()
    check root.xLastLayoutSolveDiagnostic.failed
    check root.xLastLayoutSolveDiagnostic.limit == lslConstraints
    check child.frame == rect(12, 18, 40, 20)
    check root.cssInputCount == 0
    check root.hasDiagnostic("budget")
    root.xLayoutSolveLimits = defaultLayoutSolveLimits()
    root.layoutSubtreeIfNeeded()
    check not root.xLastLayoutSolveDiagnostic.failed
    check root.cssInputCount == 40

  test "StackView resolves one CSS configuration for intrinsic and arranged geometry":
    let stack = newStackView(laHorizontal, frame = rect(0, 0, 100, 80))
    let first = fixedView(40, 20)
    let second = fixedView(30, 10)
    stack.spacing = 3
    stack.edgeInsets = insets(1)
    stack.addArrangedSubview(first, second)
    stack.installCss(
      "stack-view { -nimkit-orientation: vertical; gap: 7px 99px; -nimkit-content-insets: 2px 4px; -nimkit-alignment: trailing; -nimkit-distribution: natural; }"
    )
    check stack.intrinsicContentSize == initIntrinsicSize(48, 41)
    stack.sizeToFit()
    stack.layoutSubtreeIfNeeded()
    check first.frame == rect(4, 2, 40, 20)
    check second.frame == rect(14, 29, 30, 10)
    check stack.orientation == laHorizontal
    check stack.spacing == 3
    check stack.edgeInsets == insets(1)
    stack.appearance = initAppearance(initTheme())
    check stack.intrinsicContentSize == initIntrinsicSize(75, 22)

  test "GridView maps physical row and column gaps and alignment to sizing and layout":
    let grid = newGridView(frame = rect(0, 0, 200, 80))
    let first = fixedView(20, 10)
    let second = fixedView(30, 20)
    grid.spacing[dcol] = 1
    grid.spacing[drow] = 2
    grid.addSubview(first, row = 0, col = 0)
    grid.addSubview(second, row = 1, col = 1)
    grid.installCss(
      "grid-view { gap: 7px 5px; -nimkit-content-insets: 1px 2px 3px 4px; -nimkit-column-alignment: center; -nimkit-row-alignment: trailing; }"
    )
    check grid.intrinsicContentSize == initIntrinsicSize(61, 41)
    grid.sizeToFit()
    grid.layoutSubtreeIfNeeded()
    check first.frame == rect(4, 1, 20, 10)
    check second.frame == rect(29, 18, 30, 20)
    check grid.spacing[drow] == 2
    check grid.spacing[dcol] == 1
    grid.appearance = initAppearance(initTheme())
    check grid.intrinsicContentSize == initIntrinsicSize(51, 32)

  test "extended keys feed concrete control styles and enforce typed variable ranges":
    let theme = cssTheme(
      """
      checkbox { -nimkit-indicator-size: 22px; -nimkit-indicator-spacing: 9px; }
      slider { -nimkit-knob-size: 18px; -nimkit-knob-fill: red; -nimkit-knob-value-tint: 0.7; }
      text-field { -nimkit-selection-color: blue; -nimkit-cursor-color: green; -nimkit-language: en; }
      table-view { -nimkit-row-height: 32px; -nimkit-header-height: 40px; }
      box { -nimkit-title-height: 28px; -nimkit-title-gap: 8px; }
    """
    )
    let choice = theme.resolveChoiceButtonStyle(controlStyle(srCheckBox))
    check choice.indicatorSize == 22
    check choice.indicatorSpacing == 9
    let slider = theme.resolveSliderStyle(controlStyle(srSlider))
    check slider.knobSize == 18
    check slider.knob.fill == parseHtmlColor("red")
    let field = theme.resolveTextFieldStyle(controlStyle(srTextField))
    check field.selectionColor == parseHtmlColor("blue")
    check theme.resolveColor(
      controlStyle(srTextField), StyleCursorColor, color(0, 0, 0)
    ) == parseHtmlColor("green")
    check $field.text.language == "en"
    check theme.resolveTableViewStyle(controlStyle(srTableView)).rowHeight == 32
    check theme.resolveBoxStyle(controlStyle(srBox)).titleHeight == 28
    for declaration in [
      "-nimkit-knob-value-tint: 2", "-nimkit-width-factor: 0",
      "-nimkit-orientation: diagonal", "-nimkit-content-insets: -2px",
    ]:
      check parseCssTheme("* { " & declaration & "; }").diagnostics.len == 1

  test "native state layout rules and per key overrides participate in invalidation":
    let root = newView(frame = rect(0, 0, 300, 180))
    let child = newView(frame = rect(0, 0, 20, 20))
    root.addSubview(child)
    var builder = initThemeBuilder(initTheme())
    builder[srView, StyleLayoutWidth] =
      styleConstraints([StyleLayoutConstraint(attribute: atWidth, constant: 50)])
    builder[initStyleSelector(srView, {ssHovered}), StyleLayoutWidth] =
      styleConstraints([StyleLayoutConstraint(attribute: atWidth, constant: 70)])
    root.appearance = initAppearance(builder.finish())
    root.layoutSubtreeIfNeeded()
    check child.frame.size.width == 50
    child.setWidgetState(ssHovered, true)
    root.layoutSubtreeIfNeeded()
    check child.frame.size.width == 70
    builder = initThemeBuilder(cssTheme("view { width: 80px; height: 25px; }"))
    builder[srView, StyleLayoutWidth] =
      styleConstraints([StyleLayoutConstraint(attribute: atWidth, constant: 100)])
    root.appearance = initAppearance(builder.finish())
    root.layoutSubtreeIfNeeded()
    check child.frame.size == initSize(100, 25)

  test "mutable native roles invalidate CSS geometry and MenuBar retains owned button frames":
    let root = newView(frame = rect(0, 0, 400, 180))
    let scroll = newScrollView(frame = rect(0, 0, 100, 60))
    let collection = newCollectionView(frame = rect(0, 0, 100, 60))
    root.addSubview(scroll)
    root.addSubview(collection)
    root.installCss(
      "scroll-view { width: 80px; } table-view { width: 90px; } cascading-scroll-view { width: 120px; } cascading-column { width: 130px; }"
    )
    root.layoutSubtreeIfNeeded()
    check scroll.frame.size.width == 80
    check collection.frame.size.width == 90
    scroll.scrollViewRole = srCascadingScrollView
    collection.collectionRole = srCascadingColumn
    root.layoutSubtreeIfNeeded()
    check scroll.frame.size.width == 120
    check collection.frame.size.width == 130
    let menu = newMenu("Main")
    let item = newMenuItem("File")
    item.submenu = newMenu("File")
    discard menu.addItem(item)
    let bar = newMenuBar(menu, rect(0, 0, 200, 28))
    root.addSubview(bar)
    root.installCss("menu-bar { width: 240px; } menu-bar-item { width: 999px; }")
    root.layoutSubtreeIfNeeded()
    check bar.frame.size.width == 240
    require bar.subviews.len == 1
    check bar.subviews[0].frame.size.width < 240
    check root.hasDiagnostic("arranged by")

  test "selection indicator radius reaches the DocumentTabs render consumer":
    let tabs = newDocumentTabs(frame = rect(0, 0, 360, 34))
    discard tabs.addDocumentTabItem(newDocumentTabItem("Selected", "selected"))
    let theme = cssTheme(
      "document-tab:selected { -nimkit-selection-indicator-fill: #f102a3; -nimkit-selection-indicator-size: 6px; -nimkit-selection-indicator-radius: 3px; }"
    )
    check theme.resolveLength(
      controlStyle(srDocumentTab, {ssSelected}), StyleSelectionIndicatorCornerRadius, 0
    ) == 3
    let renders = buildRenders(tabs, initAppearance(theme))
    var found = false
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == fill(parseHtmlColor("#f102a3")):
        found = true
        check node.corners == [3'u16, 3'u16, 3'u16, 3'u16]
    check found

  test "constraint records do not retain named target views after removal":
    let root = newView(frame = rect(0, 0, 300, 180))
    let subject = newView(frame = rect(0, 0, 20, 20))
    subject.styleId = "subject"
    root.addSubview(subject)
    root.installCss("#subject { -nimkit-constraints: left == #peer.right; }")
    var observed: BackRef[View]
    block:
      let peer = newView(frame = rect(10, 10, 20, 20))
      observed.target = peer
      peer.styleId = "peer"
      root.addSubview(peer)
      root.layoutSubtreeIfNeeded()
      check subject.frame.origin.x == 30
      peer.removeFromSuperview()
    check observed.isNil
    root.layoutSubtreeIfNeeded()
    check root.hasDiagnostic("missing")

  test "admission retries share one cumulative constraint work budget":
    let root = newView(frame = rect(0, 0, 300, 180))
    let child = newView(frame = rect(10, 12, 40, 20))
    child.styleId = "child"
    root.addSubview(child)
    child[atWidth].equalTo(40).activate()
    root.installCss("#child { min-width: 80px; }")
    root.xLayoutSolveLimits = LayoutSolveLimits(maxConstraints: 20)
    root.layoutSubtreeIfNeeded()
    check root.xLastLayoutSolveDiagnostic.failed
    check root.xLastLayoutSolveDiagnostic.limit == lslConstraints
    check root.xLastLayoutSolveDiagnostic.constraints > 20
    check child.frame == rect(10, 12, 40, 20)

  test "finite CSS inputs cannot commit overflowing geometry or fitting results":
    let root = newView(frame = rect(0, 0, 400, 180))
    let child = newView(frame = rect(10, 12, 40, 20))
    child.styleId = "child"
    root.addSubview(child)
    root.installCss("#child { width: 1e38%; height: 20px; }")
    root.layoutSubtreeIfNeeded()
    check child.frame == rect(10, 12, 40, 20)
    check root.hasDiagnostic("finite coordinate range")
    check root.xLastLayoutSolveDiagnostic.failed
    root.installCss("#child { left: 3e38px; width: 3e38px; height: 20px; }")
    root.layoutSubtreeIfNeeded()
    check child.frame == rect(10, 12, 40, 20)
    check root.hasDiagnostic("finite coordinate range")
    child.installCss(
      "#child { -nimkit-constraints: width == self.height * 10, height == 1e38px; }"
    )
    check child.fittingSize == initSize(40, 20)
    check child.hasDiagnostic("finite coordinate range", fitting = true)

  test "CSS scalar variables reject native list tokens while native constraints can use them":
    var builder = initThemeBuilder(initTheme())
    builder["--width"] =
      styleConstraints([StyleLayoutConstraint(attribute: atWidth, constant: 60)])
    let parsed =
      parseCssTheme("view { width: 40px; width: var(--width); }", builder.finish())
    check parsed.diagnostics.len == 1
    check parsed.theme.resolveLayoutConstraints(controlStyle(srView), StyleLayoutWidth)[
      0
    ].constant == 40
    builder[srView, StyleLayoutWidth] = styleToken("--width")
    check builder.finish().resolveLayoutConstraints(
      controlStyle(srView), StyleLayoutWidth
    )[0].constant == 60

  test "baseline equations and numeric priorities agree with authored constraints":
    let root = newView(frame = rect(0, 0, 300, 180))
    let peer = newView(frame = rect(20, 50, 40, 30))
    let styled = newView(frame = rect(0, 0, 40, 20))
    let native = newView(frame = rect(0, 0, 40, 20))
    peer.styleId = "peer"
    styled.styleId = "styled"
    peer.firstBaselineOffset = 12
    styled.firstBaselineOffset = 7
    native.firstBaselineOffset = 7
    root.addSubview(peer)
    root.addSubview(styled)
    root.addSubview(native)

    newLayoutConstraint(
      native,
      atFirstBaseline,
      lrEqual,
      peer,
      atFirstBaseline,
      constant = 3,
      priority = LayoutPriority(800),
    )
    .activate()
    native[atWidth].equalTo(40).activate()
    native[atHeight].equalTo(20).activate()
    root.installCss(
      "#styled { width: 40px; height: 20px; -nimkit-constraints: first-baseline == #peer.first-baseline + 3px priority(800); }"
    )
    root.layoutSubtreeIfNeeded()
    check styled.frame.origin.y == native.frame.origin.y
    peer.styleId = "renamed"
    root.layoutSubtreeIfNeeded()
    check root.hasDiagnostic("missing")

  test "native container state rules invalidate CSS container sizing":
    let stack = newStackView(laHorizontal, frame = rect(0, 0, 100, 80))
    stack.addArrangedSubview(fixedView(40, 20), fixedView(30, 10))
    var builder = initThemeBuilder(initTheme())
    builder[initStyleSelector(srStackView, {ssHovered}), StyleContainerOrientation] =
      styleKeyword("vertical")
    builder[initStyleSelector(srStackView, {ssHovered}), StyleContainerRowGap] = 7.0'f32
    stack.appearance = initAppearance(builder.finish())
    stack.layoutSubtreeIfNeeded()
    stack.setWidgetState(ssHovered, true)
    check stack.needsLayout
    check stack.intrinsicContentSize == initIntrinsicSize(40, 37)
    stack.layoutSubtreeIfNeeded()
    check stack.arrangedSubviews[1].frame.origin.y >= 27

  test "TableView rejects CSS geometry on its row hosted field editor":
    let window = newWindow("CSS editor ownership", frame = rect(0, 0, 400, 180))
    let root = newView(frame = rect(0, 0, 400, 180))
    let table = newTableView(frame = rect(0, 0, 300, 140))
    let model = newTableModel(
      [tableRow("row", cells = [tableCell("name", toObj("Text"))])],
      [initTableModelColumn("name", width = 180)],
    )
    table.bindTableModel(model)
    root.addSubview(table)
    window.setContentView(root)
    discard buildRenders(root)
    require table.beginEditingCell(0, table.columnWithIdentifier("name"))
    let editor = window.fieldEditor()
    editor.styleId = "editor"
    root.installCss("#editor { width: 999px; }")
    root.layoutSubtreeIfNeeded()
    check root.hasDiagnostic("arranged by")
    check editor.frame.size.width < 300
    discard table.cancelEditingCell()
    window.setContentView(nil)

  test "checked in demo stylesheet parses and pins its panels without runtime diagnostics":
    let path =
      currentSourcePath().parentDir.parentDir.parentDir / "examples/css_theme_demo.css"
    let parsed = loadCssTheme(path, initThemeByName("macos"))
    check parsed.diagnostics.len == 0
    let root = newView(frame = rect(0, 0, 820, 540))
    let toolbar = newStackView(laHorizontal)
    let sidebar = newStackView(laVertical)
    let editor = newStackView(laVertical)
    let status = newStatusLabel("Status")
    for view in [View(toolbar), View(sidebar), View(editor), View(status)]:
      root.addSubview(view)
    toolbar.styleId = "toolbar"
    sidebar.styleId = "sidebar"
    editor.styleId = "editor"
    status.styleId = "status"
    toolbar.addArrangedSubview(newTitleLabel("NimKit CSS"), newButton("Reload CSS"))
    sidebar.addArrangedSubview(newCheckBox("Show guides"), newSlider(value = 0.65))
    editor.addArrangedSubview(newTextField("Example"))
    root.appearance = initAppearance(parsed.theme)
    root.layoutSubtreeIfNeeded()
    check root.cssLayoutDiagnostics.len == 0
    check toolbar.frame == rect(16, 12, 788, 56)
    check sidebar.frame == rect(16, 80, 205, 420)
    check editor.frame == rect(237, 80, 567, 420)

  test "tiny CSS root pinstripe metrics produce bounded advancing renders":
    let root = newView(frame = rect(0, 0, 200, 10000))
    root.usesThemedRootBackground = true
    root.installCss(
      "view { -nimkit-pinstripe-period: 1e-12px; -nimkit-pinstripe-height: 1e-12px; -nimkit-pinstripe-color: red; -nimkit-pinstripe-highlight-color: blue; }"
    )
    let renders = buildRenders(root)
    var rectangles = 0
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle:
        inc rectangles
    check rectangles > 1
    check rectangles <= 8193

  test "Table CSS row and header metrics update real geometry with native setter precedence":
    let table = newTableView(frame = rect(0, 0, 300, 180))
    table.addColumn(newTableColumn("name", width = 180))
    table.rowCount = 3
    let nativeRowHeight = table.rowHeight
    let nativeHeaderHeight = table.tableHeaderHeight
    table.installCss(
      "table-view { -nimkit-row-height: 32px; -nimkit-header-height: 40px; } table-view:hover { -nimkit-row-height: 36px; }"
    )
    table.layoutSubtreeIfNeeded()
    check table.rowHeight == 32
    check table.tableHeaderRect.size.height == 40
    check table.visibleRowSummaries[0].rect.size.height == 32
    table.setWidgetState(ssHovered, true)
    table.layoutSubtreeIfNeeded()
    check table.visibleRowSummaries[0].rect.size.height == 36
    table.installCss(
      "table-view { -nimkit-row-height: 28px; -nimkit-header-height: 30px; }"
    )
    table.layoutSubtreeIfNeeded()
    check table.visibleRowSummaries[0].rect.size.height == 28
    check table.tableHeaderRect.size.height == 30
    table.appearance = initAppearance(initTheme())
    table.layoutSubtreeIfNeeded()
    check table.rowHeight == nativeRowHeight
    check table.tableHeaderHeight == nativeHeaderHeight
    table.rowHeight = nativeRowHeight
    table.tableHeaderHeight = nativeHeaderHeight
    table.installCss(
      "table-view { -nimkit-row-height: 99px; -nimkit-header-height: 99px; }"
    )
    table.layoutSubtreeIfNeeded()
    check table.rowHeight == nativeRowHeight
    check table.tableHeaderRect.size.height == nativeHeaderHeight
    for property in [
      "-nimkit-column-width", "-nimkit-column-min-width", "-nimkit-column-max-width"
    ]:
      check parseCssTheme("table-view { " & property & ": 100px; }").diagnostics.len == 1

  test "Table CSS row metrics refresh delegate backed height and offset caches":
    let table = newTableView(frame = rect(0, 0, 300, 180))
    let delegate = CssTableRowDelegate()
    initResponder(delegate)
    discard delegate.withProtocol(CssTableRowDelegateMethods)
    table.addColumn(newTableColumn("name", width = 180))
    table.rowCount = 3
    table.delegate = delegate
    table.installCss(
      "table-view { -nimkit-row-height: 32px; } table-view:hover { -nimkit-row-height: 36px; }"
    )
    table.layoutSubtreeIfNeeded()
    let initialRows = table.visibleRowSummaries
    require initialRows.len == 3
    check initialRows[0].rect.size.height == 20
    check initialRows[1].rect.size.height == 32
    check initialRows[2].rect.origin.y - initialRows[1].rect.origin.y == 32
    table.setWidgetState(ssHovered, true)
    table.layoutSubtreeIfNeeded()
    let hoveredRows = table.visibleRowSummaries
    require hoveredRows.len == 3
    check hoveredRows[0].rect.size.height == 20
    check hoveredRows[1].rect.size.height == 36
    check hoveredRows[2].rect.origin.y - hoveredRows[1].rect.origin.y == 36
    table.installCss("table-view { -nimkit-row-height: 28px; }")
    table.layoutSubtreeIfNeeded()
    let reloadedRows = table.visibleRowSummaries
    require reloadedRows.len == 3
    check reloadedRows[0].rect.size.height == 20
    check reloadedRows[1].rect.size.height == 28
    check reloadedRows[2].rect.origin.y - reloadedRows[1].rect.origin.y == 28
