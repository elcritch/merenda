import std/unittest
import merenda/nimkit
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

suite "opt-in intrinsic measurement cache":
  test "custom views are uncached by default; opting in retains one measurement":
    let view = newCountingView(initIntrinsicSize(40, 20))
    discard view.sizeThatFits()
    discard view.sizeThatFits()
    check view.measurements == 2
    view[vpCacheIntrinsicSize] = true
    check view.sizeThatFits() == initSize(40, 20)
    discard view.sizeThatFits()
    check view.measurements == 3
    view.intrinsic = initIntrinsicSize(80, 20)
    view.invalidateIntrinsicContentSize()
    check view.sizeThatFits() == initSize(80, 20)
    check view.measurements == 4
    view[vpCacheIntrinsicSize] = false
    view.intrinsic = initIntrinsicSize(90, 20)
    view[vpCacheIntrinsicSize] = true
    check view.sizeThatFits() == initSize(90, 20)
    check view.measurements == 5

  test "fallback and fitting proposal remain fresh when intrinsic result is cached":
    let view = newCountingView(NoIntrinsicContentSize)
    view[vpCacheIntrinsicSize] = true
    check view.sizeThatFits() == initSize(25, 15)
    check view.sizeThatFits(initSize(8, 6)) == initSize(8, 6)
    check view.sizeThatFits() == initSize(25, 15)
    check view.measurements == 1
    view.applyLayoutFrame(rect(0, 0, 60, 35), lfoContainer)
    check view.sizeThatFits() == initSize(60, 35)

  test "invalidation during measurement does not publish a stale cache entry":
    let view = newCountingView(initIntrinsicSize(40, 20))
    view[vpCacheIntrinsicSize] = true
    view.invalidateDuringMeasure = true
    discard view.sizeThatFits()
    discard view.sizeThatFits()
    discard view.sizeThatFits()
    check view.measurements == 2

  test "cached container observes child content, visibility and geometry":
    let form = newFormView(frame = rect(0, 0, 200, 50))
    let child = newCountingView(initIntrinsicSize(40, 20))
    form.addRow(nil, child)
    form[vpCacheIntrinsicSize] = true
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
    field[vpCacheIntrinsicSize] = true
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
    field[vpCacheIntrinsicSize] = true
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
    view[vpCacheIntrinsicSize] = true
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
