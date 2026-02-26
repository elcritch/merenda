import ./runtime
import ./controls
import ./cells
import ./images
import ./imagecells

proc imageCell(self: NSImageView): NSImageCell =
  let controlCell = self.cell()
  if controlCell.isNil or not controlCell.isKindOfClass(NSImageCell):
    var created = NSImageCell.new()
    self.setCell(ownFromId[NSCell](created.value))
    return created
  ownFromId[NSImageCell](controlCell.value)

objcImpl:
  type NSImageView* = object of NSControl
    xTarget {.set: setTarget, get: target.}: ID
    xAction {.set: setAction, get: action.}: SEL
    xAllowsCutCopyPaste {.set: setAllowsCutCopyPaste, get: allowsCutCopyPaste.}: bool
    xAnimates {.set: setAnimates, get: animates.}: bool

  method init*(self: var NSImageView): NSImageView =
    result =
      asTypeRaw[NSImageView](callSuperIdFrom(NSImageView, self, getSelector("init")))
    if result.isNil:
      return
    var cell = NSImageCell.new()
    result.setCell(ownFromId[NSCell](cell.value))

  method refusesFirstResponder*(self: NSImageView): bool =
    true

  method image*(self: NSImageView): NSImage =
    imageCell(self).image()

  method imageAlignment*(self: NSImageView): NSImageAlignment =
    imageCell(self).imageAlignment()

  method imageFrameStyle*(self: NSImageView): int =
    imageCell(self).imageFrameStyle()

  method imageScaling*(self: NSImageView): int =
    imageCell(self).imageScaling()

  method isEditable*(self: NSImageView): bool =
    imageCell(self).isEditable()

  method setEditable*(self: NSImageView, flag: bool) =
    imageCell(self).setEditable(flag)

  method setImage*(self: NSImageView, image: NSImage) =
    imageCell(self).setImage(image)

  method setValuePath*(self: NSImageView, path: NSString) =
    var allocated = NSImage.alloc()
    let image = allocated.initWithContentsOfFile(path)
    allocated.value = nil
    if image.isNil:
      imageCell(self).setImage(NSImage(value: nil))
      return
    imageCell(self).setImage(image)

  method setValueURL*(self: NSImageView, url: NSString) =
    self.setValuePath(url)

  method setImageAlignment*(self: NSImageView, alignment: NSImageAlignment) =
    imageCell(self).setImageAlignment(alignment)

  method setImageFrameStyle*(self: NSImageView, frameStyle: int) =
    imageCell(self).setImageFrameStyle(frameStyle)

  method setImageScaling*(self: NSImageView, scaling: int) =
    imageCell(self).setImageScaling(scaling)

  method dealloc(self: NSImageView) {.used.} =
    self.xTarget.value = nil
    destroyIvarFields(self)
    discard callSuperIdFrom(NSImageView, self, getSelector("dealloc"))

proc cellClass*(t: typedesc[NSImageView]): ObjcClass =
  getClass(NSImageCell)

proc imageRectForBounds*(self: NSImageView, rect: NSRect): NSRect =
  imageCell(self).imageRectForBounds(rect)

proc new*(t: typedesc[NSImageView]): NSImageView =
  var allocated = NSImageView.alloc()
  result = initOwned(move(allocated))
