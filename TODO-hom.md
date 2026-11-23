# Higher-order messaging in NimKit and Kosmo

1. [x] **Command routing.** Share a live `findFirst` search between
   `doCommandBySelector` and `dispatchCommandInChain`. Invoke `tryToPerform` at each
   hop to preserve command overrides and the action-selector fallback.
   [Responders](src/merenda/nimkit/responder/responders.nim) · [Windows](src/merenda/nimkit/app/windows.nim)
2. [x] **Key-view navigation.** Share the forward and backward search for a view that
   answers true to `canBecomeKeyView`. Preserve selector routing, live links, the
   4,096-hop limit, and one chance for the starting view on wraparound.
   [View protocol](src/merenda/nimkit/view/viewprotos.nim)
3. [x] **Text insertion and unmarking.** Search the live responder chain for the first
   local handler of `insertText` or `unmarkText`. Both selectors return an empty tuple,
   so a successful send is the match. [Windows](src/merenda/nimkit/app/windows.nim)
4. [x] **Mouse and key event dispatch.** Share the first-true search that identifies the
   consuming responder. Localize the event separately for each receiver and honor the
   mouse dispatch `stopBefore` boundary. This requires a receiver predicate or a
   selector overload that can compute arguments per receiver.
   [Windows](src/merenda/nimkit/app/windows.nim)
5. [x] **Tooltip owner lookup.** Evaluated `follow` and kept the direct loop, which
   keeps per-view coordinates, the routed `toolTipAtPoint` call, and the early return
   together. [Windows](src/merenda/nimkit/app/windows.nim)
6. [x] **Table state provider lookup.** Search the live responder chain for the first
   responder that handles `defaultsStore` or `defaultsScopeId`. Preserve the probe
   order, short circuit, and acceptance of empty replies.
   [Table state](src/merenda/nimkit/tables/tablestate.nim)
7. [x] **Menu model loading.** Keep the direct loop. It reads the current data
   source at each index and appends only handled replies. `collectEach` would keep
   sending to the starting data source if a callback replaces it, and would
   collect intermediate replies before filtering. [Menus](src/merenda/nimkit/controls/menus.nim)
8. [x] **Document tab and matrix model loading.** Keep the direct loops. Each
   reads the current source at every index, skips unhandled replies, and restores
   selection after collecting models. `collectEach` would keep querying a source
   after a callback replaces it or a matrix switches to static models.
   [Document tabs](src/merenda/nimkit/containers/documenttabs.nim) · [Matrices](src/merenda/nimkit/controls/matrices.nim)
9. [ ] **Kosmo hint mode.** Use a first-handled-reply operation if Sigils adds one.
   A handled false ends the live walk because the inner surface owns the request.
   [Hint mode](src/merenda/kosmo/hintsmode.nim)
10. [x] **Undo manager and pasteboard requestor lookup.** Use `findFirstReply` over
    the live responder chain for undo managers. Exercise the requestor selector
    directly in tests. Both searches skip unhandled sends and handled `none` replies.
    [Responders](src/merenda/nimkit/responder/responders.nim)
