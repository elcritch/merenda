## Inspect drawing coordinates independently of retained translation wrappers.
import figdraw

proc resolvedNodes*(list: RenderList): seq[Fig] =
  ## Preserve node indices and hierarchy while expressing boxes in window space.
  ## These fixtures use translation transforms; matrix transforms need separate
  ## rendering tests rather than this axis-aligned projection.
  for node in list.nodes:
    var resolved = node
    var parent = node.parent
    while parent != (-1).FigIdx:
      let ancestor = list.nodes[parent.int]
      if ancestor.kind == nkTransform:
        doAssert not ancestor.transform.useMatrix
        resolved.screenBox.x += ancestor.transform.translation.x
        resolved.screenBox.y += ancestor.transform.translation.y
      parent = ancestor.parent
    result.add resolved

iterator descendantIndex*(nodes: seq[Fig], root: FigIdx): FigIdx =
  ## Traverse descendants through the renderer's placement/slot wrappers.
  for index, node in nodes:
    var parent = node.parent
    while parent != (-1).FigIdx:
      if parent == root:
        yield index.FigIdx
        break
      parent = nodes[parent.int].parent

proc firstRectangle*(list: RenderList): FigIdx =
  for index, node in list.nodes:
    if node.kind == nkRectangle:
      return index.FigIdx
  raise newException(ValueError, "expected a rendered rectangle")

proc isDescendant*(list: RenderList, index, ancestor: int): bool =
  if index < 0 or ancestor < 0:
    return
  var parent = list.nodes[index].parent
  while parent != (-1).FigIdx:
    if parent.int == ancestor:
      return true
    parent = list.nodes[parent.int].parent
