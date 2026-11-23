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
4. [ ] **Mouse and key event dispatch.** Share the first-true search that identifies the
   consuming responder. Localize the event separately for each receiver and honor the
   mouse dispatch `stopBefore` boundary. This requires a receiver predicate or a
   selector overload that can compute arguments per receiver.
   [Windows](src/merenda/nimkit/app/windows.nim)
5. [ ] **Tooltip owner lookup.** Search the live superview chain for the first nonempty
   `toolTipAtPoint` reply. Convert pointer coordinates separately for each view and
   preserve the selector's existing routing. [Windows](src/merenda/nimkit/app/windows.nim)
6. [ ] **Table state provider lookup.** Search the live responder chain for the first
   responder that handles `defaultsStore` or `defaultsScopeId`. Preserve the probe
   order, short circuit, and acceptance of empty replies.
   [Table state](src/merenda/nimkit/tables/tablestate.nim)
7. [ ] **Menu model loading.** Evaluate `collectEach` for ordered
   `menuItemModelAtIndex` replies and omit unhandled indexes. Verify that using one
   data source for the full reload is appropriate. The loop reads the data source at
   every index. [Menus](src/merenda/nimkit/controls/menus.nim)
8. [ ] **Document tab model loading.** Evaluate the same `collectEach` pattern for
   `documentTabModelAtIndex` and `matrixItemModelAtIndex`. Preserve selection
   restoration and decide whether a reload should retain its starting data source.
   [Document tabs](src/merenda/nimkit/containers/documenttabs.nim) · [Matrices](src/merenda/nimkit/controls/matrices.nim)
9. [ ] **Kosmo hint mode.** Use a first-handled-reply operation if Sigils adds one.
   A handled false ends the live walk because the inner surface owns the request.
   [Hint mode](src/merenda/kosmo/hintsmode.nim)
10. [ ] **Undo manager and pasteboard requestor lookup.** Share a first-matching-reply
    operation if Sigils adds one. Skip unhandled sends and handled `none` replies.
    Return the object from the original send to the winning provider.
    [Responders](src/merenda/nimkit/responder/responders.nim)
