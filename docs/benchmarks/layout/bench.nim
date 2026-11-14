import std/[monotimes, times, strformat]
import merenda/nimkit/containers/[formviews, stackviews]
import merenda/nimkit/foundation/types
import merenda/nimkit/view/viewgeometry

proc micros(start: MonoTime): float =
  float((getMonoTime() - start).inNanoseconds) / 1000.0

for count in [10, 100, 300]:
  for sample in 1 .. 5:
    let form = newFormView(frame = rect(0, 0, 500, float32(count * 25)))
    let stack = newStackView(laVertical, frame = rect(0, 0, 500, float32(count * 25)))
    var children: seq[View]
    var start = getMonoTime()
    for i in 0 ..< count:
      let label = newView(frame = rect(0, 0, 50, 20))
      let field = newView(frame = rect(0, 0, 100, 20))
      form.addRow(label, field)
      let child = newView(frame = rect(0, 0, 100, 20))
      children.add child
      stack.addArrangedSubview(child)
    let create = micros(start)
    start = getMonoTime()
    discard form.sizeThatFits()
    discard stack.sizeThatFits()
    let measure = micros(start)
    start = getMonoTime()
    form.layoutSubtreeIfNeeded()
    stack.layoutSubtreeIfNeeded()
    let layout = micros(start)
    start = getMonoTime()
    when declared(arrangeSubviewPrefix):
      var reversed: seq[ArrangedSubview]
      for i in 0 ..< count:
        reversed.add ArrangedSubview(view: children[count - i - 1])
      stack.arrangeSubviewPrefix(reversed)
    else:
      for i in 0 ..< count:
        stack.insertArrangedSubview(children[count - i - 1], i)
    let reorder = micros(start)
    echo &"{count},{sample},{create:.3f},{measure:.3f},{layout:.3f},{reorder:.3f}"
