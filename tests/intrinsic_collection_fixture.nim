## Cache policy for paired measurements of the editable collection demo.
import merenda/nimkit
import merenda/nimkit/directviews
import ../examples/direct_collection_demo

proc newIntrinsicCollectionFixture*(
    count: int, cache: bool
): tuple[view: CollectionView, rows: CollectionRows] =
  newDirectCollectionDemo(
    count,
    proc(row: DirectView, controller: ArrayController, id: string) =
      buildCollectionRow(row, controller, id)
      let stack = StackView(row.arrangedSubviews[0])
      for child in stack.arrangedSubviews:
        child{vpCacheIntrinsicSize} = cache,
  )
