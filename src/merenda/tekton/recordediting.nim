## Typed inspectors for layout, window, command, asset, and other flat resources.

import std/[options, strutils, typetraits]

import ../nimkit/foundation/types
import ../nimkit/themes
import ../nimkit/resources/[resrccore, resrcdocument, resrcregistry]
import ./valueediting

type
  ResourceRecordField* = object
    descriptor*: ResourcePropertyDescriptor
    value*: ResourceValue

  ResourceRecordFieldEdit* = object
    parsed*: bool
    message*: string
    value*: ResourceValue
    edit*: ResourceEditResult

proc fieldValue[T](value: T): ResourceValue =
  when T is ResourceId:
    resourceValue($value)
  elif T is enum:
    resourceValue($value)
  elif T is ResourceLayoutItemReference:
    resourceValue(
      resourceReference(if value.kind == rliGuide: rrLayoutGuide else: rrView, value.id)
    )
  else:
    resourceValue(value)

proc addField[T](fields: var seq[ResourceRecordField], propertyName: string, value: T) =
  let encoded = fieldValue(value)
  var descriptor = ResourcePropertyDescriptor(
    name: propertyName,
    nimTypeName: name(T),
    acceptedKinds: {encoded.kind},
    editable: true,
  )
  when T is enum:
    for choice in T:
      descriptor.options.add fieldValue(choice)
  fields.add ResourceRecordField(descriptor: descriptor, value: encoded)

proc fieldsFor[T](record: T): seq[ResourceRecordField] =
  for propertyName, value in fieldPairs(record):
    if propertyName != "id":
      when value is ResourceText:
        result.addField(propertyName, value.fallback)
        result.addField(propertyName & ".key", value.key)
      elif value is
          string | bool | int | float32 | enum | ResourceId | ResourceLayoutItemReference |
          Rect | Size | EdgeInsets | Color:
        result.addField(propertyName, value)

proc recordFields*(
    document: ResourceDocument, id: ResourceId
): seq[ResourceRecordField] =
  let path = document.findNodePath(id)
  if path.isNone:
    return
  case path.get().kind
  of rnkLayoutGuide:
    result = fieldsFor(document.layoutGuide(id))
  of rnkLayoutConstraint:
    result = fieldsFor(document.layoutConstraint(id))
  of rnkWindow:
    result = fieldsFor(document.window(id))
  of rnkCommand:
    result = fieldsFor(document.command(id))
  of rnkImage:
    result = fieldsFor(document.image(id))
  of rnkLocalization:
    result = fieldsFor(document.localization(id))
  of rnkKeyBindings:
    result = fieldsFor(document.keyBindings(id))
  of rnkTheme:
    result = fieldsFor(document.theme(id))
  else:
    discard

proc parseField[T](text: string, field: var T): ResourceValueParseResult =
  let current = fieldValue(field)
  result = parseResourceValue(text, {current.kind}, current)
  if not result.parsed:
    return
  let value = result.value
  when T is string:
    field = value.stringValue
  elif T is bool:
    field = value.boolValue
  elif T is int:
    field = value.intValue
  elif T is float32:
    field = value.floatValue
  elif T is ResourceId:
    field = resourceId(value.stringValue)
  elif T is enum:
    try:
      field = parseEnum[T](value.stringValue)
    except ValueError:
      result.parsed = false
      result.message = "choose a valid " & name(T) & " value"
  elif T is ResourceLayoutItemReference:
    if value.referenceValue.kind in {rrView, rrLayoutGuide}:
      field = resourceLayoutItem(
        value.referenceValue.id,
        if value.referenceValue.kind == rrLayoutGuide: rliGuide else: rliView,
      )
    else:
      result.parsed = false
      result.message = "use a view or layout guide reference"
  elif T is Rect:
    field = value.rectValue
  elif T is Size:
    field = value.sizeValue
  elif T is EdgeInsets:
    field = value.insetsValue
  elif T is Color:
    field = value.colorValue

proc editField[T: ResourceRecord](
    document: ResourceDocument, record: T, propertyName, text: string, commit: bool
): ResourceRecordFieldEdit =
  var candidate = record
  var parsed: ResourceValueParseResult
  for fieldName, value in fieldPairs(candidate):
    if fieldName != "id":
      when value is ResourceText:
        if propertyName == fieldName:
          parsed = parseField(text, value.fallback)
        elif propertyName == fieldName & ".key":
          parsed = parseField(text, value.key)
      elif value is
          string | bool | int | float32 | enum | ResourceId | ResourceLayoutItemReference |
          Rect | Size | EdgeInsets | Color:
        if propertyName == fieldName:
          parsed = parseField(text, value)
  result.parsed = parsed.parsed
  result.value = parsed.value
  result.message = parsed.message
  if result.parsed:
    if commit:
      result.edit =
        document.replaceResource(record.id, candidate, "Change " & propertyName)
  elif result.message.len == 0:
    result.message = "property is unavailable or cannot be edited"

proc editRecordField*(
    document: ResourceDocument,
    id: ResourceId,
    propertyName, text: string,
    commit = true,
): ResourceRecordFieldEdit =
  ## With commit=false, validates input without touching history or the draft.
  let path = document.findNodePath(id)
  if path.isNone:
    result.message = "resource is unavailable"
    return
  case path.get().kind
  of rnkLayoutGuide:
    result = document.editField(document.layoutGuide(id), propertyName, text, commit)
  of rnkLayoutConstraint:
    result =
      document.editField(document.layoutConstraint(id), propertyName, text, commit)
  of rnkWindow:
    result = document.editField(document.window(id), propertyName, text, commit)
  of rnkCommand:
    result = document.editField(document.command(id), propertyName, text, commit)
  of rnkImage:
    result = document.editField(document.image(id), propertyName, text, commit)
  of rnkLocalization:
    result = document.editField(document.localization(id), propertyName, text, commit)
  of rnkKeyBindings:
    result = document.editField(document.keyBindings(id), propertyName, text, commit)
  of rnkTheme:
    result = document.editField(document.theme(id), propertyName, text, commit)
  else:
    result.message = "resource does not have editable fields"
