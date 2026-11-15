when not defined(merendaIntrinsicCache):
  {.error: "build with -d:merendaIntrinsicCache for the cache comparison".}

import std/[monotimes, strformat, times]
import merenda/nimkit/containers/stackviews
import merenda/nimkit/foundation/[selectors, types]
import merenda/nimkit/view/viewgeometry

var reads: int

type MeasuredView = ref object of View

protocol MeasuredLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: MeasuredView): IntrinsicSize =
    inc reads
    initIntrinsicSize(20, 10)

proc measuredView(): MeasuredView =
  result = MeasuredView()
  initViewFields(result, rect(0, 0, 20, 10))
  result.autoresizingMaskConstraints = false
  discard result.withProtocol(MeasuredLayout)

for count in [10, 100, 300]:
  for enabled in [false, true]:
    let stack = newStackView(laVertical, frame = rect(0, 0, 100, float32(count * 10)))
    stack.distribution = svdNatural
    stack.alignment = svaLeading
    stack.spacing = 0
    for i in 0 ..< count:
      let child = measuredView()
      child{vpCacheIntrinsicSize} = enabled
      stack.addArrangedSubview(child)
    discard stack.sendLocalIfHandled(layoutSubviews())
    discard stack.intrinsicContentSize()
    for sample in 1 .. 5:
      reads = 0
      let start = getMonoTime()
      for iteration in 0 ..< 10:
        discard stack.intrinsicContentSize()
        discard stack.sendLocalIfHandled(layoutSubviews())
      let us = float((getMonoTime() - start).inNanoseconds) / 10000.0
      echo &"{count},{enabled},{sample},{us:.3f},{reads}"
