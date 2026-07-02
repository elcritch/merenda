import std/[options, tables]

import sigils/selectors

import ../foundation/notifications

type UserDefaults* = ref object of DynamicAgent
  xObjects: Table[string, DynamicAgent]

protocol UserDefaultsProvider {.selectorScope: protocol.}:
  method defaultsStore*(): DynamicAgent {.optional.}
  method defaultsScopeId*(): string {.optional.}

var sharedUserDefaultsInstance: UserDefaults

proc initUserDefaults*(defaults: UserDefaults) =
  if defaults.isNil:
    return
  defaults.xObjects = initTable[string, DynamicAgent]()

proc newUserDefaults*(): UserDefaults =
  result = UserDefaults()
  result.initUserDefaults()

proc sharedUserDefaults*(): UserDefaults =
  if sharedUserDefaultsInstance.isNil:
    sharedUserDefaultsInstance = newUserDefaults()
  sharedUserDefaultsInstance

proc hasObject*(defaults: UserDefaults, key: string): bool =
  not defaults.isNil and key in defaults.xObjects

proc objectForKey*(defaults: UserDefaults, key: string): Option[DynamicAgent] =
  if defaults.isNil or key.len == 0 or key notin defaults.xObjects:
    return none(DynamicAgent)
  some(defaults.xObjects[key])

proc setObjectForKey*(defaults: UserDefaults, key: string, value: DynamicAgent) =
  if defaults.isNil or key.len == 0:
    return
  if value.isNil:
    defaults.xObjects.del(key)
    postNotification(
      nkDefaultsDidChange,
      sender = DynamicAgent(defaults),
      payload = initDefaultsNotificationPayload(dckRemove, key),
    )
  else:
    defaults.xObjects[key] = value
    postNotification(
      nkDefaultsDidChange,
      sender = DynamicAgent(defaults),
      representedObject = value,
      payload = initDefaultsNotificationPayload(dckSet, key, value),
    )

proc removeObjectForKey*(defaults: UserDefaults, key: string) =
  if not defaults.isNil and key in defaults.xObjects:
    defaults.xObjects.del(key)
    postNotification(
      nkDefaultsDidChange,
      sender = DynamicAgent(defaults),
      payload = initDefaultsNotificationPayload(dckRemove, key),
    )

proc clear*(defaults: UserDefaults) =
  if not defaults.isNil and defaults.xObjects.len > 0:
    defaults.xObjects.clear()
    postNotification(
      nkDefaultsDidChange,
      sender = DynamicAgent(defaults),
      payload = initDefaultsNotificationPayload(dckClear),
    )
