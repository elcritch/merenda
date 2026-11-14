# Undo history

`UndoManager` stores groups of inverse operations. Grouping combines commands into
one history entry; it does not roll back mutations if a command or the surrounding
operation fails. Keep groups synchronous and end or discard them before starting
asynchronous work.

For a continuous value-editing gesture, use `registerMergeableValueChange` with a
nonempty key that uniquely identifies the document, target, and property. Pass the previous
and new values and an `apply` non-raising callback that assigns the supplied value without
registering another undo operation. The first callback is retained throughout
a merged gesture, so each key must refer to the same target and behavior. Register the change after applying it. Adjacent
changes merge only when the key and value type match and the previous new value
matches the next old value. Call `breakUndoCoalescing` at the end of a gesture.
A checkpoint, another command, grouping, undo, redo, or a history clear also
ends coalescing. Different targets must use different keys, even if their values
happen to be equal.

`historyLimit` bounds the total number of undo and redo groups; zero means
unlimited. Reducing the limit prunes distant groups immediately. A clean checkpoint
still describes the same document state, even when it is no longer reachable via
history. The limit counts groups, not memory: closures may retain arbitrary data,
so it does not impose a retained-byte budget.

Undo and redo callbacks should complete without raising. Replay is not transactional:
if a callback raises, already applied changes are not rolled back and the popped
history group is not restored. Callers that need conflict detection or recovery
must resolve it before replay or provide their own recovery policy.
