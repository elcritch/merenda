import merenda/nimkit/controls/cells
import merenda/nimkit/responder/actiontargets
import merenda/nimkit/foundation/selectors

proc cellRetainsInlineAdapter*(): bool =
  let receiver = newResponder()
  let cell = newActionCell()
  block:
    let adapter = newActionTarget(actionSelector("test.directCellImport"), receiver) do(
      receiver: Responder, sender: DynamicAgent
    ):
      discard
    cell.setTarget(adapter)
  result = not cell.retainedTarget().isNil
