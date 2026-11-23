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
9. [x] **Kosmo hint mode.** Use `findFirstReply` over the live responder chain.
   Accept every local reply, including false, so the first surface owns the request.
   [Hint mode](src/merenda/kosmo/hintsmode.nim)
10. [x] **Undo manager and pasteboard requestor lookup.** Use `findFirstReply` over
    the live responder chain for undo managers. Exercise the requestor selector
    directly in tests. Both searches skip unhandled sends and handled `none` replies.
    [Responders](src/merenda/nimkit/responder/responders.nim)
11. [x] **Popup-list key-view commands.** Reuse `performCommandInChain` for next
    and previous key-view commands. Start at the popup's next responder and
    preserve `tryToPerform` overrides.
    [Popup lists](src/merenda/nimkit/controls/popuplists.nim)
12. [x] **Kosmo content editing.** Share the pane-membership check with focus
    detection, then use a bounded live `findFirst` for native editing commands.
    A local action implementation claims the edit even when `tryToPerform`
    returns false.
    [Editor](src/merenda/kosmo/application_editor.nim)
13. [x] **Kosmo file-filter visibility.** Share the close and expression button
    setters across initialization, show, and dismiss. Keep direct property
    assignments to preserve required dispatch and layout notification order.
    [File tree](src/merenda/kosmo/filetree.nim)
14. [ ] **Search-bar controls.** Share the Previous/Next `enabled=` send across
    initialization and match updates. Send `hidden=` to the replacement controls
    after transferring focus back to the query field.
    [Search bars](src/merenda/nimkit/controls/searchbars.nim)
15. [ ] **Token-field enabled state.** Send `enabled=` to the input and chips
    after updating the backing cell. Check that snapshotting the chip list
    preserves behavior if a callback changes it.
    [Token fields](src/merenda/nimkit/controls/tokenfields.nim)
16. [ ] **Compact-tab buttons.** Evaluate group sends for `hidden=` when the bar
    collapses and `needsDisplay=` when focus changes.
    [Compact tabs](src/merenda/nimkit/containers/compacttabviews.nim)
17. [ ] **Mouse hit policy.** Return both the first non-default `mouseHitPolicy`
    reply and its responder with `findFirstReply`. Localize the event for each
    receiver and read the next responder after the send.
    [Windows](src/merenda/nimkit/app/windows.nim)
18. [ ] **Keyboard scroll routing.** Find the first local `scrollKey` reply of
    true. With `consumeIfOffered`, remember a handled false and still give outer
    responders a chance. Keep one live pass through the chain.
    [Responders](src/merenda/nimkit/responder/responders.nim)
19. [ ] **Native IME state.** Find the first responder that supplies both selection
    and text, then query caret and marked-range state on that responder. Preserve
    the order of the initial local probes.
    [Windows](src/merenda/nimkit/app/windows.nim)
20. [ ] **Table type-to-select.** Search wrapped indexes lazily with
    `normalizedSearchTextForRow`. Preserve disabled-row skipping and use the row
    summary only when the selector is unhandled.
    [Table selection](src/merenda/nimkit/tables/tableselection.nim)
