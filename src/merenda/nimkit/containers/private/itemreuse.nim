## Pool mechanics; widget adapters own state cleanup and prepare-for-reuse hooks.

import std/tables
import ../../view/views

type ItemReusePool* = object
  views: Table[string, seq[View]]

proc dequeue*(pool: var ItemReusePool, identifier: string): View =
  if identifier.len > 0 and identifier in pool.views:
    let bucket = addr pool.views[identifier]
    if bucket[].len > 0:
      result = bucket[][^1]
      bucket[].setLen(bucket[].len - 1)

proc detachReusableView*(view: View) =
  if not view.isNil:
    view.hidden = true
    if not view.superview().isNil:
      view.removeFromSuperview()

proc enqueue*(pool: var ItemReusePool, identifier: string, view: View) =
  if not view.isNil and identifier.len > 0:
    view.detachReusableView()
    pool.views.mgetOrPut(identifier, @[]).add view
