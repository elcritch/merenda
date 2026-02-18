type
  NSPoint* = object
    x*: float32
    y*: float32

  NSSize* = object
    width*: float32
    height*: float32

  NSRect* = object
    origin*: NSPoint
    size*: NSSize

  NSColor* = object
    r*: float32
    g*: float32
    b*: float32
    a*: float32

proc nsPoint*(x, y: float32): NSPoint =
  NSPoint(x: x, y: y)

proc nsSize*(width, height: float32): NSSize =
  NSSize(width: width, height: height)

proc nsRect*(x, y, width, height: float32): NSRect =
  NSRect(origin: nsPoint(x, y), size: nsSize(width, height))

proc nsColor*(r, g, b: float32, a: float32 = 1.0'f32): NSColor =
  NSColor(r: r, g: g, b: b, a: a)

proc contains*(r: NSRect, x, y: float32): bool =
  x >= r.origin.x and y >= r.origin.y and x < (r.origin.x + r.size.width) and
    y < (r.origin.y + r.size.height)
