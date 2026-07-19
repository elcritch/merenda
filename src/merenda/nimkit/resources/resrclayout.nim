## Runtime bridging for backend-neutral resource layout records.

import std/tables

import ../foundation/types
import ../themes
import ../view/views
import ./resrccore

type
  ResourceViewResolver* = proc(id: ResourceId): View {.closure.}

  ResourceLayoutInstance* = object
    guidesValue: Table[ResourceId, LayoutGuide]
    constraintsValue: Table[ResourceId, LayoutConstraint]
    ownersValue: Table[ResourceId, View]
    activationValue: Table[ResourceId, bool]
    guideOrderValue: seq[ResourceId]
    constraintOrderValue: seq[ResourceId]
    diagnosticsValue: ResourceDiagnostics

  ResolvedLayoutItem = object
    view: View
    offset: float32

proc initResourceLayoutInstance(): ResourceLayoutInstance =
  ResourceLayoutInstance(
    guidesValue: initTable[ResourceId, LayoutGuide](),
    constraintsValue: initTable[ResourceId, LayoutConstraint](),
    ownersValue: initTable[ResourceId, View](),
    activationValue: initTable[ResourceId, bool](),
  )

proc diagnostics*(layout: ResourceLayoutInstance): lent ResourceDiagnostics =
  layout.diagnosticsValue

func instantiated*(layout: ResourceLayoutInstance): bool =
  not layout.diagnosticsValue.hasErrors

proc findLayoutGuide*(
    layout: ResourceLayoutInstance, id: ResourceId, guide: var LayoutGuide
): bool =
  if layout.guidesValue.hasKey(id):
    guide = layout.guidesValue[id]
    return true

proc layoutGuide*(layout: ResourceLayoutInstance, id: ResourceId): LayoutGuide =
  if not layout.findLayoutGuide(id, result):
    raise newException(
      ResourceLookupError, "layout guide resource '" & $id & "' is unavailable"
    )

proc findLayoutConstraint*(
    layout: ResourceLayoutInstance, id: ResourceId
): LayoutConstraint =
  layout.constraintsValue.getOrDefault(id)

proc layoutConstraint*(
    layout: ResourceLayoutInstance, id: ResourceId
): LayoutConstraint =
  result = layout.findLayoutConstraint(id)
  if result.isNil:
    raise newException(
      ResourceLookupError, "layout constraint resource '" & $id & "' is unavailable"
    )

iterator layoutGuides*(
    layout: ResourceLayoutInstance
): tuple[id: ResourceId, guide: LayoutGuide] =
  for id in layout.guideOrderValue:
    yield (id, layout.guidesValue[id])

iterator layoutConstraints*(
    layout: ResourceLayoutInstance
): tuple[id: ResourceId, constraint: LayoutConstraint] =
  for id in layout.constraintOrderValue:
    yield (id, layout.constraintsValue[id])

func toLayoutAttribute(anchor: ResourceLayoutAnchor): LayoutAttribute =
  case anchor
  of rlaNotAnAnchor: atNotAnAttribute
  of rlaLeft: atLeft
  of rlaRight: atRight
  of rlaTop: atTop
  of rlaBottom: atBottom
  of rlaLeading: atLeading
  of rlaTrailing: atTrailing
  of rlaWidth: atWidth
  of rlaHeight: atHeight
  of rlaCenterX: atCenterX
  of rlaCenterY: atCenterY
  of rlaLastBaseline: atLastBaseline
  of rlaFirstBaseline: atFirstBaseline

func toLayoutRelation(relation: ResourceLayoutRelation): LayoutRelation =
  case relation
  of rlrLessThanOrEqual: lrLessThanOrEqual
  of rlrEqual: lrEqual
  of rlrGreaterThanOrEqual: lrGreaterThanOrEqual

func guideOffset(guide: LayoutGuide, anchor: ResourceLayoutAnchor): float32 =
  let value = guide.insets()
  case anchor
  of rlaLeft, rlaLeading:
    value.left
  of rlaRight, rlaTrailing:
    -value.right
  of rlaTop:
    value.top
  of rlaBottom:
    -value.bottom
  of rlaCenterX:
    (value.left - value.right) / 2.0'f32
  of rlaCenterY:
    (value.top - value.bottom) / 2.0'f32
  of rlaWidth:
    -value.horizontal
  of rlaHeight:
    -value.vertical
  of rlaNotAnAnchor, rlaFirstBaseline, rlaLastBaseline:
    0.0'f32

proc resolveItem(
    layout: ResourceLayoutInstance,
    reference: ResourceLayoutItemReference,
    anchor: ResourceLayoutAnchor,
    viewFor: ResourceViewResolver,
): ResolvedLayoutItem =
  case reference.kind
  of rliView:
    result.view = viewFor(reference.id)
  of rliGuide:
    var guide: LayoutGuide
    if layout.findLayoutGuide(reference.id, guide):
      result.view = guide.owningView()
      result.offset = guide.guideOffset(anchor)

proc activate*(layout: ResourceLayoutInstance) =
  ## Installs the constraints whose resource activation state is on.
  for id in layout.constraintOrderValue:
    let constraint = layout.constraintsValue[id]
    if layout.activationValue.getOrDefault(id):
      let owner = layout.ownersValue.getOrDefault(id)
      if not owner.isNil:
        owner.addConstraint(constraint)

proc deactivate*(layout: ResourceLayoutInstance) =
  ## Removes every installed constraint while retaining its resource mapping.
  for id in layout.constraintOrderValue:
    layout.constraintsValue[id].active = false

proc instantiateResourceLayout*(
    bundle: ResourceBundle, viewFor: ResourceViewResolver, activate = true
): ResourceLayoutInstance =
  ## Resolves resource identifiers into runtime guides and constraints.
  ##
  ## Guide endpoints are lowered to their owning view and inset anchor offset.
  ## The resource records stay independent of runtime identities.
  result = initResourceLayoutInstance()
  for index, resource in bundle.layoutGuides:
    let owner = viewFor(resource.owningViewId)
    if owner.isNil:
      result.diagnosticsValue.add(
        rdsError,
        "resource.layout.guideOwnerUnavailable",
        "layout guide owner '" & $resource.owningViewId & "' is unavailable",
        path = "layoutGuides[" & $index & "].owningViewId",
        resourceId = resource.id,
        relatedId = resource.owningViewId,
      )
    else:
      result.guidesValue[resource.id] = initLayoutGuide(owner, resource.insets)
      result.guideOrderValue.add resource.id

  for index, resource in bundle.layoutConstraints:
    let
      path = "layoutConstraints[" & $index & "]"
      owner = viewFor(resource.owningViewId)
      first = result.resolveItem(resource.firstItem, resource.firstAnchor, viewFor)
      hasSecond = not resource.secondItem.id.isEmpty
      second =
        if hasSecond:
          result.resolveItem(resource.secondItem, resource.secondAnchor, viewFor)
        else:
          ResolvedLayoutItem()
    if owner.isNil or first.view.isNil or (hasSecond and second.view.isNil):
      result.diagnosticsValue.add(
        rdsError,
        "resource.layout.endpointUnavailable",
        "layout constraint endpoints could not be resolved",
        path = path,
        resourceId = resource.id,
      )
      continue

    let runtimeConstant =
      if hasSecond:
        second.offset * resource.multiplier + resource.constant - first.offset
      else:
        resource.constant - first.offset
    let constraint = newLayoutConstraint(
      first.view,
      resource.firstAnchor.toLayoutAttribute(),
      resource.relation.toLayoutRelation(),
      second.view,
      resource.secondAnchor.toLayoutAttribute(),
      resource.multiplier,
      runtimeConstant,
      initLayoutPriority(resource.priority),
    )
    result.constraintsValue[resource.id] = constraint
    result.ownersValue[resource.id] = owner
    result.activationValue[resource.id] = resource.active
    result.constraintOrderValue.add resource.id

  if activate and result.instantiated:
    result.activate()
