import std/[monotimes, times]
import merenda/nimkit
import merenda/nimkit/view/viewgeometry
for depth in [10, 100, 500]:
  let root = newView()
  var parent = root
  for _ in 1 ..< depth:
    let child = newView()
    parent.addSubview(child)
    parent = child
  discard root.resolvedIntrinsicContentSize()
  let startCached = getMonoTime()
  for _ in 0 ..< 1000:
    discard root.resolvedIntrinsicContentSize()
  let cached = (getMonoTime() - startCached).inMicroseconds
  root{vpCacheIntrinsicSize} = false
  let startUncached = getMonoTime()
  for _ in 0 ..< 1000:
    discard root.resolvedIntrinsicContentSize()
  let uncached = (getMonoTime() - startUncached).inMicroseconds
  echo depth, ",", cached, ",", uncached
