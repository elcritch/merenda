## Internal eviction decisions for Kosmo's Markdown preview cache.

import std/tables

type
  MarkdownPreviewBudgetKind* = enum
    mpbkPreview
    mpbkPendingOwner
    mpbkSavedState
    mpbkRetiredView

  MarkdownPreviewBudgetEntry* = object
    ## A snapshot of known retained payloads. IDs do not own their referents.
    paneId*: uint64
    lastUsed*: uint64
    pinned*: bool
    kind*: MarkdownPreviewBudgetKind
    viewBytes*: uint64
    ownerId*: uint64 ## Zero means the owner cost is exclusive to this entry.
    ownerBytes*: uint64
    ownerIncomplete*: bool ## Some owner payloads cannot currently be measured.
    viewIncomplete*: bool ## Some view payloads cannot currently be measured.

  MarkdownPreviewBudgetResult* = object
    victims*: seq[int] ## Indices into the original input, in eviction order.
    retainedBytes*: uint64 ## Saturates if known costs exceed uint64.
    overByteBudget*: bool
    overPaneLimit*: bool
    incomplete*: bool ## At least one retained entry has an incomplete estimate.

proc addBytes(total: var uint64, value: uint64, overflow: var bool) =
  if value > high(uint64) - total:
    total = high(uint64)
    overflow = true
  else:
    total += value

proc markdownPreviewEvictions*(
    entries: openArray[MarkdownPreviewBudgetEntry],
    byteBudget: uint64,
    paneLimit: Natural,
): MarkdownPreviewBudgetResult =
  ## Apply a soft byte budget and a per-pane count limit. Pinned entries are
  ## never selected; unresolved pressure is reported when they exceed a limit.
  ## Pending owners, retired layouts and saved state are pinned and do not
  ## count as previews.
  ## Estimates for an owner ID are deduplicated using their largest known value.
  var
    removed = newSeq[bool](entries.len)
    ownerCosts = initTable[uint64, uint64]()
    ownerIncomplete = initTable[uint64, bool]()
  # An entry can carry a stale smaller estimate of the same live owner. Keep
  # the highest known cost from this snapshot until its last consumer leaves.
  for entry in entries:
    if entry.kind in {mpbkPreview, mpbkPendingOwner} and entry.ownerId != 0:
      ownerCosts[entry.ownerId] =
        max(ownerCosts.getOrDefault(entry.ownerId), entry.ownerBytes)
      ownerIncomplete[entry.ownerId] =
        ownerIncomplete.getOrDefault(entry.ownerId) or entry.ownerIncomplete
  while true:
    var
      paneCounts = initTable[uint64, int]()
      chargedOwners = initTable[uint64, bool]()
      total: uint64
      overflow = false
      incomplete = false
    for index, entry in entries:
      if not removed[index]:
        if entry.kind == mpbkPreview:
          paneCounts[entry.paneId] = paneCounts.getOrDefault(entry.paneId) + 1
        if entry.kind != mpbkPendingOwner:
          total.addBytes(entry.viewBytes, overflow)
          incomplete = incomplete or entry.viewIncomplete
        if entry.kind in {mpbkPreview, mpbkPendingOwner}:
          if entry.ownerId == 0:
            total.addBytes(entry.ownerBytes, overflow)
            incomplete = incomplete or entry.ownerIncomplete
          elif not chargedOwners.hasKey(entry.ownerId):
            chargedOwners[entry.ownerId] = true
            total.addBytes(ownerCosts[entry.ownerId], overflow)
            incomplete = incomplete or ownerIncomplete[entry.ownerId]
    let overBytes = overflow or total > byteBudget
    var overCount = false
    for count in paneCounts.values:
      if count > int(paneLimit):
        overCount = true
        break

    var selected = -1
    if overCount:
      for index, entry in entries:
        if not removed[index] and not entry.pinned and entry.kind == mpbkPreview and
            paneCounts[entry.paneId] > int(paneLimit) and
            (selected < 0 or entry.lastUsed < entries[selected].lastUsed):
          selected = index
    if selected < 0 and overBytes:
      for index, entry in entries:
        if not removed[index] and not entry.pinned and entry.kind == mpbkPreview and
            (selected < 0 or entry.lastUsed < entries[selected].lastUsed):
          selected = index
    if selected < 0:
      result.retainedBytes = total
      result.overByteBudget = overBytes
      result.overPaneLimit = overCount
      result.incomplete = incomplete
      return
    removed[selected] = true
    result.victims.add selected
