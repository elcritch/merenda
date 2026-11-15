import std/unittest
import sigils/core
import merenda/nimkit
import merenda/nimkit/app/backend
import merenda/nimkit/view/viewgeometry

type CountingView = ref object of View
  intrinsic: IntrinsicSize
  measurements: int
  invalidateDuringMeasure: bool

protocol CountingLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: CountingView): IntrinsicSize =
    inc view.measurements
    if view.invalidateDuringMeasure:
      view.invalidateDuringMeasure = false
      view.invalidateIntrinsicContentSize()
    view.intrinsic

protocol AlternateCountingLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: CountingView): IntrinsicSize =
    inc view.measurements
    initIntrinsicSize(view.intrinsic.width * 2, view.intrinsic.height)

proc newCountingView(value: IntrinsicSize): CountingView =
  result = CountingView(intrinsic: value)
  initViewFields(result, rect(0, 0, 25, 15))
  discard result.withProtocol(CountingLayout)

type GeometryView = ref object of View
  measurements: int

protocol GeometryLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: GeometryView): IntrinsicSize =
    inc view.measurements
    let frame = view.frame()
    initIntrinsicSize(
      frame.origin.x + frame.size.width, frame.origin.y + frame.size.height
    )

proc newGeometryView(): GeometryView =
  result = GeometryView()
  initViewFields(result, rect(0, 0, 25, 15))
  discard result.withProtocol(GeometryLayout)

type DependentView = ref object of View
  source: CountingView
  measurements: int

protocol DependentLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: DependentView): IntrinsicSize =
    inc view.measurements
    view.source.resolvedIntrinsicContentSize()

proc newDependentView(source: CountingView, cache: bool): DependentView =
  result = DependentView(source: source)
  initViewFields(result)
  discard result.withProtocol(DependentLayout)
  result{vpCacheIntrinsicSize} = cache

type SizingCell = ref object of Cell
  natural: IntrinsicSize

protocol SizingCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: SizingCell): IntrinsicSize =
    cell.natural

proc newSizingCell(size: IntrinsicSize): SizingCell =
  result = SizingCell(natural: size)
  initCellFields(result)
  discard result.withProtocol(SizingCellMeasurement)

type CachePolicyObserver = ref object of Responder
  child: View
  armed: bool

proc toggleDuringRemoval(
    observer: CachePolicyObserver, reason: LayoutInvalidationReason
) {.slot.} =
  if observer.armed and reason == lirSuperview:
    observer.armed = false
    observer.child{vpCacheIntrinsicSize} = true

proc toggleAfterAddition(observer: CachePolicyObserver, child: View) {.slot.} =
  if observer.armed:
    observer.armed = false
    child{vpCacheIntrinsicSize} = false

proc actualUncachedCount(view: View): uint32 =
  if not view{vpCacheIntrinsicSize}:
    inc result
  for child in view.subviews:
    result += child.actualUncachedCount()

proc checkUncachedCount(view: View) =
  check view.xIntrinsicMeasurement.uncachedSubtree == view.actualUncachedCount()
  for child in view.subviews:
    child.checkUncachedCount()

suite "intrinsic measurement cache":
  test "views cache by default and can opt out":
    let view = newCountingView(initIntrinsicSize(40, 20))
    check view{vpCacheIntrinsicSize}
    discard view.sizeThatFits()
    discard view.sizeThatFits()
    check view.measurements == 1
    view{vpCacheIntrinsicSize} = false
    check view.sizeThatFits() == initSize(40, 20)
    discard view.sizeThatFits()
    check view.measurements == 3
    view{vpCacheIntrinsicSize} = true
    view.intrinsic = initIntrinsicSize(80, 20)
    view.invalidateIntrinsicContentSize()
    check view.sizeThatFits() == initSize(80, 20)
    check view.measurements == 4
    view{vpCacheIntrinsicSize} = false
    view.intrinsic = initIntrinsicSize(90, 20)
    view{vpCacheIntrinsicSize} = true
    check view.sizeThatFits() == initSize(90, 20)
    check view.measurements == 5

  test "fallback and fitting proposal remain fresh when intrinsic result is cached":
    let view = newCountingView(NoIntrinsicContentSize)
    view{vpCacheIntrinsicSize} = true
    check view.sizeThatFits() == initSize(25, 15)
    check view.sizeThatFits(initSize(8, 6)) == initSize(8, 6)
    check view.sizeThatFits() == initSize(25, 15)
    check view.measurements == 1
    view.applyLayoutFrame(rect(0, 0, 60, 35), lfoContainer)
    check view.sizeThatFits() == initSize(60, 35)

  test "invalidation during measurement does not publish a stale cache entry":
    let view = newCountingView(initIntrinsicSize(40, 20))
    view{vpCacheIntrinsicSize} = true
    view.invalidateDuringMeasure = true
    discard view.sizeThatFits()
    discard view.sizeThatFits()
    discard view.sizeThatFits()
    check view.measurements == 2

  test "protocol replacement can be followed by explicit invalidation":
    let view = newCountingView(initIntrinsicSize(40, 20))
    view{vpCacheIntrinsicSize} = true
    check view.resolvedIntrinsicContentSize() == initIntrinsicSize(40, 20)
    discard view.withProtocol(AlternateCountingLayout)
    view.invalidateIntrinsicContentSize()
    check view.resolvedIntrinsicContentSize() == initIntrinsicSize(80, 20)
    check view.resolvedIntrinsicContentSize() == initIntrinsicSize(80, 20)
    check view.measurements == 2

  test "external dependencies update after explicit dependent invalidation":
    let source = newCountingView(initIntrinsicSize(40, 20))
    let baseline = newDependentView(source, false)
    let cached = newDependentView(source, true)
    check baseline.resolvedIntrinsicContentSize() ==
      cached.resolvedIntrinsicContentSize()
    check cached.resolvedIntrinsicContentSize() == initIntrinsicSize(40, 20)
    source.intrinsic = initIntrinsicSize(75, 30)
    source.invalidateIntrinsicContentSize()
    cached.invalidateIntrinsicContentSize()
    check baseline.resolvedIntrinsicContentSize() ==
      cached.resolvedIntrinsicContentSize()
    check cached.resolvedIntrinsicContentSize() == initIntrinsicSize(75, 30)
    check cached.measurements == 2

  test "an uncached descendant prevents stale ancestor measurements":
    let child = newCountingView(initIntrinsicSize(40, 20))
    let parent = newDependentView(child, true)
    parent.addSubview(child)
    check parent.resolvedIntrinsicContentSize() == initIntrinsicSize(40, 20)
    child{vpCacheIntrinsicSize} = false
    child.intrinsic = initIntrinsicSize(75, 30)
    check parent.resolvedIntrinsicContentSize() == initIntrinsicSize(75, 30)
    child{vpCacheIntrinsicSize} = true
    check parent.resolvedIntrinsicContentSize() == initIntrinsicSize(75, 30)
    check parent.resolvedIntrinsicContentSize() == initIntrinsicSize(75, 30)

  test "uncached subtree counts follow policy and hierarchy changes":
    let first = newView()
    let second = newView()
    let branch = newView()
    let one = newView()
    let two = newView()
    one{vpCacheIntrinsicSize} = false
    two{vpCacheIntrinsicSize} = false
    branch.addSubview(one)
    branch.insertSubview(two, 0)
    first.addSubview(branch)
    first.checkUncachedCount()
    check branch.xIntrinsicMeasurement.uncachedSubtree == 2
    check first.xIntrinsicMeasurement.uncachedSubtree == 2
    branch{vpCacheIntrinsicSize} = false
    check first.xIntrinsicMeasurement.uncachedSubtree == 3
    branch{vpCacheIntrinsicSize} = true
    first.checkUncachedCount()
    first.insertSubview(branch, 0)
    first.checkUncachedCount()
    second.addSubview(branch)
    first.checkUncachedCount()
    second.checkUncachedCount()
    check first.xIntrinsicMeasurement.uncachedSubtree == 0
    check second.xIntrinsicMeasurement.uncachedSubtree == 2
    one{vpCacheIntrinsicSize} = true
    check branch.xIntrinsicMeasurement.uncachedSubtree == 1
    check second.xIntrinsicMeasurement.uncachedSubtree == 1
    branch.removeFromSuperview()
    second.checkUncachedCount()
    branch.checkUncachedCount()
    check second.xIntrinsicMeasurement.uncachedSubtree == 0
    check branch.xIntrinsicMeasurement.uncachedSubtree == 1
    two{vpCacheIntrinsicSize} = true
    check branch.xIntrinsicMeasurement.uncachedSubtree == 0
    two{vpCacheIntrinsicSize} = false
    first.addSubview(branch)
    check first.replaceSubview(branch, nil)
    first.checkUncachedCount()
    branch.checkUncachedCount()
    let replacement = newView()
    replacement{vpCacheIntrinsicSize} = false
    first.addSubview(newView())
    check first.replaceSubview(first.subviews[0], replacement)
    first.checkUncachedCount()
    let window = newWindow("Cache hierarchy", frame = rect(0, 0, 80, 40))
    window.setContentView(branch)
    branch.checkUncachedCount()
    window.setContentView(first)
    branch.checkUncachedCount()
    first.checkUncachedCount()
    window.close()

  test "policy changes during removal do not bubble to the old parent":
    let parent = newView()
    let child = newView()
    child{vpCacheIntrinsicSize} = false
    parent.addSubview(child)
    let observer = CachePolicyObserver(child: child, armed: true)
    initResponder(observer)
    child.connect(layoutInputChanged, observer, toggleDuringRemoval)
    child.removeFromSuperview()
    child.disconnect(layoutInputChanged, observer, toggleDuringRemoval)
    check not observer.armed
    parent.checkUncachedCount()
    child.checkUncachedCount()

  test "policy changes during addition bubble to the new parent":
    let parent = newView()
    let child = newView()
    let observer = CachePolicyObserver(armed: true)
    initResponder(observer)
    parent.connect(didAddSubview, observer, toggleAfterAddition)
    parent.addSubview(child)
    parent.disconnect(didAddSubview, observer, toggleAfterAddition)
    check not observer.armed
    check parent.xIntrinsicMeasurement.uncachedSubtree == 1
    parent.checkUncachedCount()

  test "cell replacement and cell metrics invalidate an opted-in control":
    let first = newSizingCell(initIntrinsicSize(40, 20))
    let control = Control()
    initControlFields(control, cell = first)
    control{vpCacheIntrinsicSize} = true
    check control.resolvedIntrinsicContentSize() == initIntrinsicSize(40, 20)
    first.natural = initIntrinsicSize(60, 25)
    first.invalidateControlMetrics()
    check control.resolvedIntrinsicContentSize() == initIntrinsicSize(60, 25)
    let replacement = newSizingCell(initIntrinsicSize(100, 30))
    control.setCell(replacement)
    check control.resolvedIntrinsicContentSize() == initIntrinsicSize(100, 30)
    first.natural = initIntrinsicSize(200, 40)
    first.invalidateControlMetrics()
    check control.resolvedIntrinsicContentSize() == initIntrinsicSize(100, 30)

  test "cached container observes child content, visibility and geometry":
    let form = newFormView(frame = rect(0, 0, 200, 50))
    let child = newCountingView(initIntrinsicSize(40, 20))
    form.addRow(nil, child)
    form{vpCacheIntrinsicSize} = true
    check form.resolvedIntrinsicContentSize().width == 40
    child.intrinsic = initIntrinsicSize(70, 20)
    child.invalidateIntrinsicContentSize()
    check form.resolvedIntrinsicContentSize().width == 70
    child.hidden = true
    check form.resolvedIntrinsicContentSize().width == 0
    child.hidden = false
    child.intrinsic = NoIntrinsicContentSize
    child.invalidateIntrinsicContentSize()
    check form.resolvedIntrinsicContentSize().width == 25
    child.applyLayoutFrame(rect(0, 0, 60, 35), lfoContainer)
    check form.resolvedIntrinsicContentSize().width == 60
    child.removeFromSuperview()
    check form.resolvedIntrinsicContentSize().width == 0

  test "text and appearance changes invalidate opted-in controls":
    let field = newTextField("Short")
    field.editable = false
    field.selectable = false
    field{vpCacheIntrinsicSize} = true
    let before = field.sizeThatFits()
    field.text = "A much longer text field"
    check field.sizeThatFits().width > before.width
    let oldSize = field.sizeThatFits()
    var appearance = initAppearance()
    appearance[srTextField, StyleMinimumSize] = initSize(400, 50)
    appearance[srTextField, StyleFontSize] = 28.0
    field.appearance = appearance
    check field.sizeThatFits().width >= 400
    check field.sizeThatFits().height > oldSize.height

  test "inherited appearance changes and reparenting invalidate child measurements":
    let first = newView()
    let second = newView()
    var firstStyle = initAppearance()
    var secondStyle = initAppearance()
    firstStyle[srTextField, StyleMinimumSize] = initSize(100, 30)
    firstStyle[srTextField, StyleFontSize] = 12.0
    secondStyle[srTextField, StyleMinimumSize] = initSize(300, 55)
    secondStyle[srTextField, StyleFontSize] = 28.0
    first.appearance = firstStyle
    second.appearance = secondStyle
    let field = newTextField("Hello")
    field.editable = false
    field.selectable = false
    first.addSubview(field)
    field{vpCacheIntrinsicSize} = true
    let initial = field.sizeThatFits()
    second.addSubview(field)
    let moved = field.sizeThatFits()
    check moved.width >= 300
    check moved.height >= 55
    check moved.width > initial.width
    secondStyle[srTextField, StyleMinimumSize] = initSize(450, 65)
    secondStyle[srTextField, StyleFontSize] = 35.0
    second.appearance = secondStyle
    let changed = field.sizeThatFits()
    check changed.width >= 450
    check changed.height >= 65

  test "solver and container frame changes invalidate custom geometry measurements":
    let view = newGeometryView()
    view{vpCacheIntrinsicSize} = true
    check view.sizeThatFits() == initSize(25, 15)
    discard view.sizeThatFits()
    check view.measurements == 1
    view.applyLayoutFrame(rect(7, 3, 60, 35), lfoSolver)
    check view.sizeThatFits() == initSize(67, 38)
    check view.measurements == 2
    view.applyLayoutFrame(rect(7, 3, 60, 35), lfoSolver)
    discard view.sizeThatFits()
    check view.measurements == 2
    view.applyLayoutFrame(rect(9, 4, 80, 40), lfoContainer)
    check view.sizeThatFits() == initSize(89, 44)
    check view.measurements == 3

type
  ControlFixture = object
    root: StackView
    label: Label
    field: TextField
    button: Button

  ReentrantView = ref object of View
    intrinsic: IntrinsicSize
    measurements: int
    changeDuringMeasure: bool

protocol ReentrantLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: ReentrantView): IntrinsicSize =
    inc view.measurements
    result = view.intrinsic
    if view.changeDuringMeasure:
      view.changeDuringMeasure = false
      view.intrinsic = initIntrinsicSize(80, 25)
      view.invalidateIntrinsicContentSize()

proc newReentrantView(cache: bool): ReentrantView =
  result = ReentrantView(intrinsic: initIntrinsicSize(40, 20))
  initViewFields(result, rect(0, 0, 40, 20))
  discard result.withProtocol(ReentrantLayout)
  result{vpCacheIntrinsicSize} = cache

proc newControlFixture(cache: bool): ControlFixture =
  result.root = newStackView(laHorizontal, frame = rect(0, 0, 480, 80))
  result.root.distribution = svdNatural
  result.root.spacing = 8
  result.label = newLabel("Caption")
  result.field = newTextField("Short")
  result.button = newButton("Apply")
  for view in [View(result.label), View(result.field), View(result.button)]:
    view{vpCacheIntrinsicSize} = cache
    result.root.addArrangedSubview(view)

proc compareControlFixtures(left, right: ControlFixture) =
  discard buildRenders(left.root)
  discard buildRenders(right.root)
  check not left.root.xLastLayoutSolveDiagnostic.failed
  check not right.root.xLastLayoutSolveDiagnostic.failed
  check left.root.frame == right.root.frame
  for pair in [
    (View(left.label), View(right.label)),
    (View(left.field), View(right.field)),
    (View(left.button), View(right.button)),
  ]:
    check pair[0].resolvedIntrinsicContentSize() ==
      pair[1].resolvedIntrinsicContentSize()
    check pair[0].sizeThatFits() == pair[1].sizeThatFits()
    check pair[0].frame == pair[1].frame

suite "intrinsic cache compared with uncached layout":
  test "state-dependent theme metrics and button cell changes invalidate equally":
    let baseline = newControlFixture(false)
    let cached = newControlFixture(true)
    var builder = initThemeBuilder()
    builder[srButton, StyleFontSize] = 12.0
    builder[srButton, {ssHovered}, StyleFontSize] = 36.0
    let appearance = initAppearance(builder.finish())
    baseline.root.appearance = appearance
    cached.root.appearance = appearance
    compareControlFixtures(baseline, cached)
    let original = baseline.button.resolvedIntrinsicContentSize()
    baseline.button.hovered = true
    cached.button.hovered = true
    compareControlFixtures(baseline, cached)
    check baseline.button.resolvedIntrinsicContentSize().height > original.height
    baseline.button.hovered = false
    cached.button.hovered = false
    baseline.button.reservedTitles = ["A much longer reserved button title"]
    cached.button.reservedTitles = ["A much longer reserved button title"]
    compareControlFixtures(baseline, cached)
    check baseline.button.resolvedIntrinsicContentSize().width > original.width

  test "built-in leaf controls keep sizes and frames across content and style changes":
    let baseline = newControlFixture(false)
    let cached = newControlFixture(true)
    compareControlFixtures(baseline, cached)
    # Repeat the query before every mutation so the opted-in values are warm.
    compareControlFixtures(baseline, cached)
    let originalLabel = baseline.label.resolvedIntrinsicContentSize()

    baseline.field.stringValue = "A substantially longer value"
    cached.field.stringValue = "A substantially longer value"
    baseline.label.stringValue = "A longer label"
    cached.label.stringValue = "A longer label"
    baseline.button.title = "Apply changes"
    cached.button.title = "Apply changes"
    compareControlFixtures(baseline, cached)
    check baseline.label.resolvedIntrinsicContentSize().width > originalLabel.width

    let originalField = baseline.field.resolvedIntrinsicContentSize()
    var appearance = initAppearance()
    appearance[srTextField, StyleFontName] =
      styleKeyword(platformDefaultFontName(frMonospace))
    appearance[srTextField, StyleFontSize] = 28.0
    appearance[srButton, StyleFontSize] = 24.0
    baseline.root.appearance = appearance
    cached.root.appearance = appearance
    compareControlFixtures(baseline, cached)
    check baseline.field.resolvedIntrinsicContentSize().height > originalField.height

    appearance[srTextField, StyleMinimumSize] = initSize(160, 45)
    baseline.root.appearance = appearance
    cached.root.appearance = appearance
    baseline.label.labelStyle = lsHeading
    cached.label.labelStyle = lsHeading
    compareControlFixtures(baseline, cached)
    check baseline.field.resolvedIntrinsicContentSize().width >= 160

    baseline.button.hidden = true
    cached.button.hidden = true
    compareControlFixtures(baseline, cached)
    baseline.button.hidden = false
    cached.button.hidden = false
    baseline.root.frame = rect(0, 0, 700, 110)
    cached.root.frame = rect(0, 0, 700, 110)
    compareControlFixtures(baseline, cached)

  test "reentrant intrinsic changes match uncached reads and do not publish stale results":
    let baseline = newReentrantView(false)
    let cached = newReentrantView(true)
    baseline.changeDuringMeasure = true
    cached.changeDuringMeasure = true
    let first = baseline.resolvedIntrinsicContentSize()
    check first == initIntrinsicSize(40, 20)
    check first == cached.resolvedIntrinsicContentSize()
    let next = baseline.resolvedIntrinsicContentSize()
    check next == initIntrinsicSize(80, 25)
    check next == cached.resolvedIntrinsicContentSize()
    check cached.resolvedIntrinsicContentSize() == initIntrinsicSize(80, 25)
    check baseline.measurements == 2
    check cached.measurements == 2

  test "active field-editor input preserves cached and uncached geometry":
    let baseline = newControlFixture(false)
    let cached = newControlFixture(true)
    let first = newWindow("Uncached intrinsic", frame = rect(0, 0, 480, 80))
    let second = newWindow("Cached intrinsic", frame = rect(0, 0, 480, 80))
    first.setContentView(baseline.root)
    second.setContentView(cached.root)
    defer:
      first.close()
      second.close()
    compareControlFixtures(baseline, cached)
    require first.makeFirstResponder(baseline.field)
    require second.makeFirstResponder(cached.field)
    require first.dispatchTextInput("A longer provisional value")
    require second.dispatchTextInput("A longer provisional value")
    check baseline.field.stringValue == cached.field.stringValue
    compareControlFixtures(baseline, cached)
    let marked =
      HostTextComposition(text: "かな", selectedStart: 1, replacementStart: -1)
    require first.dispatchTextComposition(marked)
    require second.dispatchTextComposition(marked)
    check TextView(baseline.field.currentEditor).markedRange ==
      TextView(cached.field.currentEditor).markedRange
    check TextView(baseline.field.currentEditor).selectedRange ==
      TextView(cached.field.currentEditor).selectedRange
    compareControlFixtures(baseline, cached)
    require first.dispatchTextInput("漢字")
    require second.dispatchTextInput("漢字")
    check baseline.field.stringValue == cached.field.stringValue
    compareControlFixtures(baseline, cached)
    require first.makeFirstResponder(nil)
    require second.makeFirstResponder(nil)
    compareControlFixtures(baseline, cached)
