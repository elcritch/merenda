import ./runtime
import ./valueproviders

var NSFontNameAttribute* {.threadvar.}: NSString
var NSFontFamilyAttribute* {.threadvar.}: NSString
var NSFontSizeAttribute* {.threadvar.}: NSString
var NSFontMatrixAttribute* {.threadvar.}: NSString
var NSFontCharacterSetAttribute* {.threadvar.}: NSString
var NSFontTraitsAttribute* {.threadvar.}: NSString
var NSFontFaceAttribute* {.threadvar.}: NSString
var NSFontFixedAdvanceAttribute* {.threadvar.}: NSString
var NSFontVisibleNameAttribute* {.threadvar.}: NSString

var NSFontSymbolicTrait* {.threadvar.}: NSString
var NSFontWeightTrait* {.threadvar.}: NSString
var NSFontWidthTrait* {.threadvar.}: NSString
var NSFontSlantTrait* {.threadvar.}: NSString

var fontDescriptorConstantsReady {.threadvar.}: bool

proc ensureFontDescriptorConstants*() =
  if fontDescriptorConstantsReady:
    return
  NSFontNameAttribute = @ns"NSFontNameAttribute"
  NSFontFamilyAttribute = @ns"NSFontFamilyAttribute"
  NSFontSizeAttribute = @ns"NSFontSizeAttribute"
  NSFontMatrixAttribute = @ns"NSFontMatrixAttribute"
  NSFontCharacterSetAttribute = @ns"NSFontCharacterSetAttribute"
  NSFontTraitsAttribute = @ns"NSFontTraitsAttribute"
  NSFontFaceAttribute = @ns"NSFontFaceAttribute"
  NSFontFixedAdvanceAttribute = @ns"NSFontFixedAdvanceAttribute"
  NSFontVisibleNameAttribute = @ns"NSFontVisibleNameAttribute"
  NSFontSymbolicTrait = @ns"NSFontSymbolicTrait"
  NSFontWeightTrait = @ns"NSFontWeightTrait"
  NSFontWidthTrait = @ns"NSFontWidthTrait"
  NSFontSlantTrait = @ns"NSFontSlantTrait"
  fontDescriptorConstantsReady = true

proc cloneAttributes(
    attributes: NSDictionary[NSObject, NSObject]
): NSDictionary[NSObject, NSObject] =
  result = nsDictionary[NSObject, NSObject]()
  if attributes.isNil:
    return
  for key, value in attributes.pairs:
    result[key] = value

proc objectUIntValue(obj: NSObject): NSUInteger =
  if obj.isNil:
    return 0
  if obj.respondsToSelector("unsignedIntegerValue"):
    return cast[proc(self: IDPtr, op: SEL): NSUInteger {.cdecl, varargs.}](objc_msgSend)(
      obj.value, getSelector("unsignedIntegerValue")
    )
  if obj.respondsToSelector("unsignedIntValue"):
    return cast[proc(self: IDPtr, op: SEL): cuint {.cdecl, varargs.}](objc_msgSend)(
      obj.value, getSelector("unsignedIntValue")
    ).NSUInteger
  if obj.respondsToSelector("intValue"):
    let value = cast[proc(self: IDPtr, op: SEL): cint {.cdecl, varargs.}](objc_msgSend)(
      obj.value, getSelector("intValue")
    )
    if value < 0:
      return 0
    return value.NSUInteger
  0

proc fontDescriptorWithFontAttributes*(
  t: typedesc[NSFontDescriptor], attributes: NSDictionary[NSObject, NSObject]
): NSFontDescriptor

objcImpl:
  type NSFontDescriptor* {.impl: NSCopying.} = object of NSObject
    xAttributes {.set: setStorageAttributes, get: storageAttributes.}:
      NSDictionary[NSObject, NSObject]

  method initWithFontAttributes*(
      self: var NSFontDescriptor, attributes: NSDictionary[NSObject, NSObject]
  ): NSFontDescriptor =
    ensureFontDescriptorConstants()
    result = asTypeRaw[NSFontDescriptor](
      callSuperIdFrom(NSFontDescriptor, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xAttributes = cloneAttributes(attributes)

  method init*(self: var NSFontDescriptor): NSFontDescriptor =
    result = self.initWithFontAttributes(NSDictionary[NSObject, NSObject](value: nil))

  method fontAttributes*(self: NSFontDescriptor): NSDictionary[NSObject, NSObject] =
    cloneAttributes(self.xAttributes)

  method objectForKey*(self: NSFontDescriptor, attributeKey: NSString): NSObject =
    if self.isNil or attributeKey.isNil:
      return NSObject(value: nil)
    let attributes = self.xAttributes
    if attributes.isNil:
      return NSObject(value: nil)
    let key = NSObject(attributeKey)
    if not attributes.hasKey(key):
      return NSObject(value: nil)
    attributes[key]

  method pointSize*(self: NSFontDescriptor): float32 =
    objectFloatValue(self.objectForKey(NSFontSizeAttribute))

  method matrix*(self: NSFontDescriptor): NSObject =
    self.objectForKey(NSFontMatrixAttribute)

  method symbolicTraits*(self: NSFontDescriptor): NSUInteger =
    let traitsObj = self.objectForKey(NSFontTraitsAttribute)
    if traitsObj.isNil:
      return 0
    let traits = NSDictionary[NSObject, NSObject](traitsObj)
    if traits.isNil:
      return 0
    let symbolicKey = NSObject(NSFontSymbolicTrait)
    if not traits.hasKey(symbolicKey):
      return 0
    objectUIntValue(traits[symbolicKey])

  method fontDescriptorByAddingAttributes*(
      self: NSFontDescriptor, attributes: NSDictionary[NSObject, NSObject]
  ): NSFontDescriptor =
    var merged = cloneAttributes(self.xAttributes)
    if not attributes.isNil:
      for key, value in attributes.pairs:
        merged[key] = value
    NSFontDescriptor.fontDescriptorWithFontAttributes(merged)

  method fontDescriptorWithFace*(
      self: NSFontDescriptor, face: NSString
  ): NSFontDescriptor =
    var merged = cloneAttributes(self.xAttributes)
    merged[NSObject(NSFontFaceAttribute)] = NSObject(face)
    NSFontDescriptor.fontDescriptorWithFontAttributes(merged)

  method fontDescriptorWithFamily*(
      self: NSFontDescriptor, family: NSString
  ): NSFontDescriptor =
    var merged = cloneAttributes(self.xAttributes)
    merged[NSObject(NSFontFamilyAttribute)] = NSObject(family)
    NSFontDescriptor.fontDescriptorWithFontAttributes(merged)

  method fontDescriptorWithMatrix*(
      self: NSFontDescriptor, matrix: NSObject
  ): NSFontDescriptor =
    var merged = cloneAttributes(self.xAttributes)
    merged[NSObject(NSFontMatrixAttribute)] = matrix
    NSFontDescriptor.fontDescriptorWithFontAttributes(merged)

  method fontDescriptorWithSize*(
      self: NSFontDescriptor, pointSize: float32
  ): NSFontDescriptor =
    var merged = cloneAttributes(self.xAttributes)
    merged[NSObject(NSFontSizeAttribute)] = boxNSObject(pointSize)
    NSFontDescriptor.fontDescriptorWithFontAttributes(merged)

  method fontDescriptorWithSymbolicTraits*(
      self: NSFontDescriptor, traits: NSUInteger
  ): NSFontDescriptor =
    var merged = cloneAttributes(self.xAttributes)
    var traitsDict = nsDictionary[NSObject, NSObject]()
    let traitsObj = self.objectForKey(NSFontTraitsAttribute)
    if not traitsObj.isNil:
      let existingTraits = NSDictionary[NSObject, NSObject](traitsObj)
      for key, value in existingTraits.pairs:
        traitsDict[key] = value
    traitsDict[NSObject(NSFontSymbolicTrait)] = boxNSObject(traits)
    merged[NSObject(NSFontTraitsAttribute)] = NSObject(traitsDict)
    NSFontDescriptor.fontDescriptorWithFontAttributes(merged)

  method copyWithZone*(self: NSFontDescriptor, zone: pointer): NSFontDescriptor =
    retain(self)

  method dealloc(self: NSFontDescriptor) {.used.} =
    self.xAttributes = NSDictionary[NSObject, NSObject](value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSFontDescriptor, self, getSelector("dealloc"))

proc fontDescriptorWithFontAttributes*(
    t: typedesc[NSFontDescriptor], attributes: NSDictionary[NSObject, NSObject]
): NSFontDescriptor =
  var allocated = NSFontDescriptor.alloc()
  result = allocated.initWithFontAttributes(attributes)
  allocated.value = nil

proc fontDescriptorWithName*(
    t: typedesc[NSFontDescriptor], name: NSString, matrix {.kw("matrix").}: NSObject
): NSFontDescriptor =
  ensureFontDescriptorConstants()
  var attributes = nsDictionary[NSObject, NSObject]()
  attributes[NSObject(NSFontNameAttribute)] = NSObject(name)
  attributes[NSObject(NSFontMatrixAttribute)] = matrix
  t.fontDescriptorWithFontAttributes(attributes)

proc fontDescriptorWithName*(
    t: typedesc[NSFontDescriptor], name: NSString, pointSize {.kw("size").}: float32
): NSFontDescriptor =
  ensureFontDescriptorConstants()
  var attributes = nsDictionary[NSObject, NSObject]()
  attributes[NSObject(NSFontNameAttribute)] = NSObject(name)
  attributes[NSObject(NSFontSizeAttribute)] = boxNSObject(pointSize)
  t.fontDescriptorWithFontAttributes(attributes)

proc new*(t: typedesc[NSFontDescriptor]): NSFontDescriptor =
  var allocated = NSFontDescriptor.alloc()
  result = initOwned(move(allocated))

ensureFontDescriptorConstants()
