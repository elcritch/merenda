## Compare process peak memory with and without compiled-in intrinsic cache fields.
import merenda/nimkit
import merenda/nimkit/directviews
import ../examples/direct_collection_demo

proc treeCount(view: View): int =
  result = 1
  for child in view.subviews:
    result += child.treeCount()

let demo = newDirectCollectionDemo(5000, false)
let window = newWindow("Memory fixture", frame = rect(0, 0, 640, 480))
window.setContentView(demo.view)
discard window.buildRenders()
let row = DirectView(demo.view.itemViewAtIndex(0))
doAssert not row.isNil
let field = TextField(StackView(row.arrangedSubviews[0]).arrangedSubviews[1])
doAssert window.makeFirstResponder(field)
demo.view.scrollView.contentOffset = initPoint(0, 1200)
discard window.buildRenders()
echo "view_bytes=",
  sizeof(typeof(default(View)[])),
  ",tree_views=",
  demo.view.treeCount(),
  ",mounted_rows=",
  demo.view.visibleItemViews.len
# Release normally; external peak-RSS measurements include setup and teardown.
demo.rows.close()
window.close()
