## Generic documents hosted by a Kosmo editor pane.

import ../nimkit as nimkit

type KosmoPaneDocument* = ref object
  ## An identity-bearing document with content and tab presentation.
  identifier*: string
  title*: string
  tooltip*: string
  contentView*: nimkit.View
  preferredFirstResponder*: nimkit.View
  closeable*: bool
  modified*: bool
  style*: nimkit.DocumentTabStyle
  styleClasses*: seq[string]
  onClose*: proc(document: KosmoPaneDocument): bool {.closure.}
  onSave*: proc(document: KosmoPaneDocument): bool {.closure.}
  onDuplicate*: proc(document: KosmoPaneDocument): KosmoPaneDocument {.closure.}

proc newKosmoPaneDocument*(
    identifier, title: string,
    contentView: nimkit.View,
    preferredFirstResponder: nimkit.View = nil,
    tooltip = "",
    closeable = true,
    style = nimkit.dtsAutomatic,
    styleClasses: openArray[string] = [],
    onClose: proc(document: KosmoPaneDocument): bool {.closure.} = nil,
    onSave: proc(document: KosmoPaneDocument): bool {.closure.} = nil,
    onDuplicate: proc(document: KosmoPaneDocument): KosmoPaneDocument {.closure.} = nil,
): KosmoPaneDocument =
  ## Create a pane document that can participate in Kosmo's tab lifecycle.
  KosmoPaneDocument(
    identifier: identifier,
    title: title,
    tooltip: tooltip,
    contentView: contentView,
    preferredFirstResponder:
      if preferredFirstResponder.isNil: contentView else: preferredFirstResponder,
    closeable: closeable,
    style: style,
    styleClasses: @styleClasses,
    onClose: onClose,
    onSave: onSave,
    onDuplicate: onDuplicate,
  )

func documentTabModel*(document: KosmoPaneDocument): nimkit.DocumentTabModel =
  ## Return the native tab presentation for `document`.
  if document.isNil:
    return
  nimkit.initDocumentTabModel(
    identifier = document.identifier,
    title = document.title,
    closeable = document.closeable,
    modified = document.modified,
    style = document.style,
    styleClasses = document.styleClasses,
    tooltip = document.tooltip,
  )

proc close*(document: KosmoPaneDocument): bool {.discardable.} =
  ## Ask a document to release its resources, allowing it to veto closing.
  if document.isNil:
    return
  if document.onClose.isNil:
    return true
  document.onClose(document)

proc save*(document: KosmoPaneDocument): bool {.discardable.} =
  ## Save a document when it provides a save operation.
  if document.isNil or document.onSave.isNil:
    return
  document.onSave(document)

proc duplicate*(document: KosmoPaneDocument): KosmoPaneDocument =
  ## Create an independent instance suitable for display in another pane.
  if not document.isNil and not document.onDuplicate.isNil:
    result = document.onDuplicate(document)
