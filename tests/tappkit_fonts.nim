import std/[math, unittest]

import merenda/appkit

proc objectString(obj: NSObject): NSString =
  if obj.isNil:
    return @ns""
  if obj.isKindOfClass(NSString):
    return NSString(obj)
  if obj.respondsToSelector("stringValue"):
    let value = cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(
      obj.value, getSelector("stringValue")
    )
    if not value.isNil:
      return ownFromId[NSString](value)
  @ns""

suite "appkit nsfont and nsfontdescriptor":
  test "NSFontDescriptor constants and construction":
    check($NSFontNameAttribute == "NSFontNameAttribute")
    check($NSFontSizeAttribute == "NSFontSizeAttribute")
    check($NSFontTraitsAttribute == "NSFontTraitsAttribute")
    check($NSFontSymbolicTrait == "NSFontSymbolicTrait")

    let descriptor = NSFontDescriptor.fontDescriptorWithName(@ns"Ubuntu.ttf", 15.0)
    check(not descriptor.isNil)
    check(abs(descriptor.pointSize() - 15.0) < 0.01)
    check($objectString(descriptor.objectForKey(NSFontNameAttribute)) == "Ubuntu.ttf")

  test "NSFontDescriptor mutation helpers keep and override attributes":
    var attrs = nsDictionary[NSObject, NSObject]()
    attrs[NSObject(NSFontNameAttribute)] = NSObject(@ns"HackNerdFont-Regular.ttf")
    attrs[NSObject(NSFontSizeAttribute)] = boxNSObject(13.0'f32)

    let base = NSFontDescriptor.fontDescriptorWithFontAttributes(attrs)
    let resized = base.fontDescriptorWithSize(22.0)
    let withFamily = resized.fontDescriptorWithFamily(@ns"Hack Nerd Font")

    check(abs(base.pointSize() - 13.0) < 0.01)
    check(abs(resized.pointSize() - 22.0) < 0.01)
    check(
      $objectString(withFamily.objectForKey(NSFontFamilyAttribute)) == "Hack Nerd Font"
    )

  test "NSFont loads figdraw-backed typeface metrics":
    let font = NSFont.systemFontOfSize(16.0)
    check(not font.isNil)
    check(font.pointSize() == 16.0)
    check(font.fontName().len > 0)
    check(font.familyName().len > 0)
    check(font.defaultLineHeightForFont() > 0.0)
    check(font.ascender() > 0.0)
    check(font.descender() <= 0.0)
    check(font.capHeight() >= 0.0)
    check(font.xHeight() >= 0.0)

  test "NSFont descriptor round-trip preserves requested point size":
    let sourceDescriptor =
      NSFontDescriptor.fontDescriptorWithName(@ns"Ubuntu.ttf", 19.0)
    let font = NSFont.fontWithDescriptor(sourceDescriptor, 0.0)
    check(not font.isNil)
    check(abs(font.pointSize() - 19.0) < 0.01)

    let roundTrip = font.fontDescriptor()
    check(not roundTrip.isNil)
    check(abs(roundTrip.pointSize() - 19.0) < 0.01)
