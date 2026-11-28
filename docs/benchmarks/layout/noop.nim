import std/[monotimes, times, strformat]
import merenda/nimkit/containers/stackviews
import merenda/nimkit/core/types

proc micros(start: MonoTime): float =
  float((getMonoTime() - start).inNanoseconds) / 1000.0

for count in [10, 100, 300]:
  let
    stack = newStackView(laVertical)
    iterations = max(10, 3000 div count)
  var children: seq[View]
  for i in 0 ..< count:
    let child = newView()
    children.add child
    stack.addArrangedSubview(child)
  for sample in 1 .. 5:
    var start = getMonoTime()
    for iteration in 0 ..< iterations:
      for i, child in children:
        let arranged = stack.arrangedSubviews
        if i >= arranged.len or arranged[i] != child:
          stack.insertArrangedSubview(child, i, svspAutomatic)
        elif stack.arrangedSubviewSizingPolicy(child) != svspAutomatic:
          stack.setArrangedSubviewSizingPolicy(child, svspAutomatic)
    let before = micros(start) / float(iterations)
    start = getMonoTime()
    for iteration in 0 ..< iterations:
      var batch: seq[ArrangedSubview]
      for child in children:
        batch.add ArrangedSubview(view: child, sizingPolicy: svspAutomatic)
      stack.arrangeSubviewPrefix(batch)
    let after = micros(start) / float(iterations)
    echo &"{count},{sample},{iterations},{before:.3f},{after:.3f}"
