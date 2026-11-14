import std/[monotimes, os, times, unittest]
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/directviews/dsl
import merenda/nimkit/foundation/mainthreadwork

type LifetimeOwner = ref object of Responder
  calls: int

proc lifetimeBody(context: DirectNode, owner: LifetimeOwner, value: int) =
  context.viewBody:
    Button($value):
      onAction(owner, value) do(
        receiver: LifetimeOwner, amount: int, sender: DynamicAgent
      ):
        receiver.calls += amount

proc observedLifetime(context: DirectNode, owner: LifetimeOwner, input: Sigil[int]) =
  context.bindBody(input, owner, lifetimeBody)

proc settleTitle(button: Button, expected: string) =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while button.title != expected and getMonoTime() < deadline:
    discard drainMainThreadWork()
    if button.title != expected:
      sleep(1)
  check button.title == expected

suite "direct view activation and lifetime":
  test "hiding retained content keeps observation while clear retires queued work":
    let owner = LifetimeOwner()
    let input = newSigil(1)
    let host = newDirectView()
    host.viewBody:
      component(observedLifetime, owner, input)
    let oldButton = Button(host.arrangedSubviews[0])
    check input.subcriptions.len == 1

    host.hidden = true
    input <- 2
    oldButton.settleTitle("2")
    check input.subcriptions.len == 1

    input <- 3
    host.clear()
    check input.subcriptions.len == 0
    check host.arrangedSubviews.len == 0
    discard drainMainThreadWork()
    check oldButton.title == "2"
    discard oldButton.send(performClick(), ActionArgs(sender: oldButton))
    check owner.calls == 0

    host.hidden = false
    host.viewBody:
      component(observedLifetime, owner, input)
    let newButton = Button(host.arrangedSubviews[0])
    check newButton != oldButton
    check newButton.title == "3"
    check input.subcriptions.len == 1
    discard newButton.send(performClick(), ActionArgs(sender: newButton))
    check owner.calls == 3
    host.clear()
    check input.subcriptions.len == 0
