# Declarative views: first prototype

The evaluation point is an editable task list. Inserting or reordering other rows,
changing an unrelated counter, and rebuilding a description must preserve the
same text field, field editor, focus, selection, and marked text. Actions must
continue to address the correct task after a reorder.

```sh
nim ic -r examples/declarative_views_demo.nim
```

The left pane is a live declarative mount. Select text in a title, then click
**Insert at top**, **Reverse**, or **Counter +1**. Those demonstration buttons are
non-focusable so the click itself does not end editing. The right pane uses the
same row description for Dragology's detached previews; dragging there updates
the live model. Preview controls are drawing content, not interactive controls.

## Authoring

```nim
import merenda/nimkit

proc taskRow(task: Task, owner: TaskController): ViewSpec =
  viewBody:
    HStack(spacing = 10):
      Label(task.id)
      TextField(task.title, sizing = svspFillAvailableWidth):
        onChange(owner, task.id) do(
          receiver: TaskController, id: string, sender: DynamicAgent
        ):
          receiver.renameTask(id, TextField(sender).stringValue)

proc taskList(owner: TaskController, tasks: seq[Task]): ViewSpec =
  viewBody:
    VStack(spacing = 12):
      for task in tasks:
        keyed(task.id):
          taskRow(task, owner)

let host = newDeclarativeView(taskList(controller, model.tasks))
# After an application-owned model change:
host.update(taskList(controller, model.tasks))
```

`viewBody` produces a value. It collects `VStack`, `HStack`, `Label`, `Button`, and
`TextField` expressions and calls ordinary typed constructors. Helper procs return
`ViewSpec`; local `let`/`var`, `if`, `when`, `case`, `for`, and `block` retain Nim
semantics. `viewBody` and `keyed` blocks each need exactly one root. Event bindings are
stored in the description; handlers do not run while building it.
Built-in nodes require capitalized type names: `VStack`, `HStack`, `Label`,
`Button`, and `TextField`. Lowercase node spellings are compile errors. Identity
helpers such as `keyed` and component procedures keep ordinary function names;
event-handler bodies retain ordinary Nim syntax.

The underlying `vstackSpec`, `hstackSpec`, `labelSpec`, `buttonSpec`,
`textFieldSpec`, and `keyedSpec` constructors also work without macros. This gives
us a direct way to compare syntax and runtime behavior separately.

Declarative stacks default to `svdNatural` distribution, keeping controls at their
fitting sizes. Use a child's `sizing` to consume spare space, or set the stack's
`distribution` explicitly when equal or proportional filling is intended.

## Actions beside the layout

```nim
Button("Reverse", focusable = false):
  onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
    receiver.model.tasks.reverse()
    receiver.refresh()
```

`onAction` and `onChange` blocks call `viewAction`, which uses the existing
`newActionTarget` adapter. The adapter is retained, its receiver is a zeroing weak
reference, and its handler is non-capturing (`nimcall`). No manual owner lookup or
nil check is needed. A dead receiver makes the action a no-op. The sender is the
live button or text field, following the normal NimKit action convention.

For repeated rows, the second argument binds explicit context; it becomes the
handler's second parameter, as in the text-field example above. Context is copied
using normal Nim semantics and refreshed with the description. Use value IDs;
storing an owning controller reference in context would still retain it. This
context overload is also available directly on `newActionTarget`.

Existing named actions can be supplied directly without an inline handler:

```nim
buttonSpec("Reverse", onAction = initViewAction(reverseTasks(), controller))
```

`initViewAction` preserves `ActionTarget` ownership rules: ordinary responder
targets are weak, and explicitly supplied `ActionAdapter`/`ClosureTarget` values
are retained. `viewAction(controller) do (...)` also works with the typed
constructors outside `viewBody`. Capturing closures remain possible through an
explicit `newActionTarget(selector, callback)` adapter, with its usual ownership
responsibilities; the inline receiver form rejects accidental captures.

## Identity and ownership

- Explicit keys are unique among siblings, and take precedence over structural
  identity. Keys are separate from ordinary view identifiers and drag markers.
- The macro assigns a structural slot to each expression. An optional preceding
  sibling does not shift later slots. Repeated expressions in loops need explicit
  keys; otherwise duplicate sibling identities are rejected.
- Direct constructor calls without keys or macro slots use sibling position.
- The same key and widget kind under the same parent reuse the existing widget.
  A changed key or kind replaces it. Moving between different parents creates a
  new instance; cross-parent state transfer is not implemented.
- A mount owns its child hierarchy and its event adapters. Model ownership remains
  with the application. Rebuilding refreshes callbacks even when properties do
  not change. Removing a node disconnects text events and disables retained
  button targets. `host.clear()` explicitly releases the mounted tree.
- Call `clear()` during teardown if individual controls can outlive their host;
  it also makes those externally retained controls inert.
- Inline handlers use ActionTarget's weak receivers, so a controller can own its
  host without a callback retaining the controller. Explicit closure adapters
  retain their captures and require the same ownership care as other controls.

Duplicate sibling keys are validated before touching the installed tree. The
runtime does not promise transactional rollback if an arbitrary overriding widget
setter raises. Reentrant updates from setters are rejected; ordinary event
callbacks can synchronously update or clear their host.

## Editing and updates

The reconciler uses existing property setters and StackView's in-place child
reordering. It does not detach reused rows. It writes text only when the authored
value changed and the current editor does not already contain that value. Thus
an unrelated update leaves a local edit alone, and echoing an edit through the
model does not reset selection or composition. An explicitly changed external
value is authoritative and may replace the current editing contents.

Programmatic field patches suppress the declarative `onChange` callback. Other
NimKit observers retain their normal behavior. A user edit uses the most recently
installed callback. Local state slots, automatic Sigil dependency tracking,
batched recomposition, and asynchronous effects are deferred.

`host.updateStats` reports created, reused, removed, and moved node counts for the
last update. These are reconciliation counts, not timing benchmarks. They let us
compare a no-op update, a one-row insertion, and a reorder without relying on
visual similarity alone.

## The Dragology overlap

```nim
proc previewBuilder(model: Model, env: DragEnvironment): View =
  buildDetachedView(body(model))
```

`buildDetachedView` constructs a fresh detached tree from the same description but
installs no action targets or text subscriptions. Dragology applies the captured
bounds and appearance, performs layout, and captures rendering as before. Mark
row descriptions with `draggable = true` and a stable `identifier` to use them as
drag elements. Existing constraints on drag markers still apply: nonempty unique
IDs, nonnested marked subtrees, and an unmarked root.

A description builder must still avoid effects and live widget mutation. A
callback being stored in a value does not make arbitrary builder code pure.

## Evaluation and next comparisons

The shared NimKit test runner includes `tests/nimkit/declarativeviews.nim`:

- A selected text field survives insertion, reorder, and unrelated updates.
- Marked text survives reevaluation; controlled edits can synchronously echo back.
- Event bindings refresh after keyed moves, and removed controls become inert.
- Inline handlers reject captures, release their receiver, and can clear their
  own mount during dispatch.
- Invalid keys leave the installed tree unchanged; key/kind changes replace it.
- Optional siblings preserve structural identity.
- Detached previews do not invoke model handlers and match live row geometry.

This iteration deliberately covers four widget kinds and existing stack layout.
It does not establish a universal adapter API, ordered modifier system, lazy
lists, local remembered state, restoration, or cross-parent identity. The next
useful comparisons are explicit model updates versus scoped Sigil subscriptions,
full description evaluation versus subtree evaluation, and typed adapters for a
custom widget. The current tests and demo provide the baseline for those changes.
