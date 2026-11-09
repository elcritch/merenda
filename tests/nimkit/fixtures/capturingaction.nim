## Negative compile fixture: an inline action must reject captured locals.
## `nim ic tests/nimkit/fixtures/capturingaction.nim` must fail with illegal capture.
import merenda/nimkit/responder/[responders, actiontargets]
import merenda/nimkit/foundation/selectors

proc installCapturingAction() =
  let receiver = newResponder()
  var calls = 0
  discard newActionTarget(actionSelector("test.illegalCapture"), receiver) do(
    receiver: Responder, sender: DynamicAgent
  ):
    inc calls

installCapturingAction()
