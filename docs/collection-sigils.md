# Observable keyed collections

NimKit uses `CollectionSigil[K, T]` from `sigils/collections`. Items and snapshots
remain plain Nim values. The collection owns the snapshot and key index, and
projections are read-only. `merenda/nimkit` and the existing
`merenda/nimkit/app/collectionsigils` import path re-export the API.

```nim
type Task = object
  id: int
  title: string

proc taskId(task: Task): int = task.id

let tasks = newCollectionSigil(@[Task(id: 1, title: "Draft")], taskId)
let order = tasks.order       # CollectionValue[seq[int]]
let first = tasks.item(1)     # CollectionValue[Opt[Task]]
tasks[1] = Task(id: 1, title: "Ready")
assert first{}.get.title == "Ready"
assert order{} == @[1]
```

- `tasks{}` / `snapshot()` returns the whole value snapshot; `<-` replaces it.
- `tasks[id]` and `tasks.get(id)` look up a **key** and raise `KeyError` when it
  is absent. Use `contains` to check membership. `len`, `items`, and `pairs`
  are also available.
- `tasks.order` notifies observers when membership or ordering changes.
- `tasks.item(id)` notifies observers when the key appears or disappears, or its
  value compares unequal. The projection reads as `Opt[T]`, with `none` for an
  absent key and `some` for a present key, including a present nil reference.
  It follows the identity across reinsertion.
- `tasks[id] = value` replaces an existing item and requires the same key.

Whole snapshots, order, and item projections support Sigils' scoped `{}` reads
and explicit `change` subscriptions. NimKit's `bindValue` accepts all three.
Read-only projections have no setter; commands publish through the collection,
so they cannot accidentally diverge from the authoritative model.

Publication validates unique keys, builds the new index, and compares observed
items **before mutation**. Every snapshot and projection is updated before the
first notification. A duplicate-key error leaves the collection unchanged.
Synchronous recursive publication raises `ValueError`; schedule dependent writes
after the current publication. Subscriber exceptions do not roll back committed
state or promise delivery to remaining subscribers.

Projections are allocated on demand. Repeated `item(id)` calls share a live
observation. A projection retains its collection, and the collection holds a
zeroing link back to it. NimKit bindings retain their inputs, and Sigils
computations retain the temporary projections they read. Both release projections
they no longer observe. Publication and occasional allocation sweeps prune expired
entries.

All operations belong on the owning GUI thread. Reference-bearing item fields
retain their usual Nim aliasing semantics. Use replacement publication to make
changes observable.

Snapshot replacement is O(n + m), where m is the number of observed identities;
only changed observations notify bindings. Indexed lookup is expected O(1).
Single-item assignment still copies and validates a snapshot; it is not an O(1)
persistent-data-structure update. Undo snapshots, sorting/filtering, and virtualized
table/collection presentation remain controller responsibilities.
