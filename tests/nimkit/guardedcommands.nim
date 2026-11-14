import std/unittest
import sigils/core
import merenda/nimkit/responder/[guardedcommands, responders]
import merenda/nimkit/declarative/actions

type
  TestReceiver = ref object of Responder
    generation: int
    selected: int
    calls: int

  TestContext = object
    generation, id: int

var predicateCalls: int

proc valid(receiver: TestReceiver, context: TestContext): bool =
  inc predicateCalls
  receiver.generation == context.generation

proc execute(receiver: TestReceiver, context: TestContext) =
  inc receiver.calls
  receiver.selected = context.id

suite "guarded commands":
  test "a valid dispatch uses the original context snapshot":
    let receiver = TestReceiver(generation: 1)
    initResponder(receiver)
    var context = TestContext(generation: 1, id: 10)
    let command = initGuardedCommand(receiver, context, valid)
    context.id = 42
    check command.perform(execute)
    check receiver.calls == 1
    check receiver.selected == 10

  test "stale context cannot dispatch even before an action is redrawn":
    let receiver = TestReceiver(generation: 1)
    initResponder(receiver)
    let command = initGuardedCommand(receiver, TestContext(generation: 1, id: 4), valid)
    let action = viewAction(receiver, command) do(
      receiver: TestReceiver,
      command: GuardedCommand[TestReceiver, TestContext],
      sender: DynamicAgent
    ):
      command.perform(execute)
    receiver.generation = 2
    action.dispatchViewAction(nil)
    check receiver.calls == 0

  test "a command does not retain its receiver":
    var receiver = TestReceiver(generation: 1)
    initResponder(receiver)
    var weak: BackRef[TestReceiver]
    weak.target = receiver
    let command = initGuardedCommand(receiver, TestContext(generation: 1), valid)
    receiver = nil
    check weak.isNil
    predicateCalls = 0
    check not command.perform(execute)
    check predicateCalls == 0
