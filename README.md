# nutella

`nutella` provides Nim bindings/helpers around the Objective-C runtime.

## `objcImpl` runtime DSL

`objcImpl` declares a runtime protocol + runtime class and wires Nim method
implementations as Objective-C instance methods.

```nim
import nutella/objc

var pingCount = 0
var total = 0.cint

objcImpl:
  type PingProtocol =
    concept self
      method ping(self: PingProtocol)
      method add(self: PingProtocol, amount: cint): cint

  type PingClass {.impl: PingProtocol.} = object of NSObject

  method ping(self: PingClass) =
    inc pingCount

  method add(self: PingClass, amount: cint): cint =
    total += amount
    result = total

let cls = getClass("PingClass")
let obj = asType[NSObject](new(cls))

let sendPing = cast[proc(self: ID, op: SEL) {.cdecl.}](objc_msgSend)
let sendAdd =
  cast[proc(self: ID, op: SEL, amount: cint): cint {.cdecl.}](objc_msgSend)

sendPing(obj, selector("ping"))
doAssert pingCount == 1
doAssert sendAdd(obj, selector("add:"), 2.cint) == 2.cint
doAssert sendAdd(obj, selector("add:"), 3.cint) == 5.cint
```

### Behavior

- Creates/registers protocol if missing (`allocateProtocol` + `registerProtocol`).
- Adds required instance method descriptions to the protocol.
- Creates/registers class if missing (using the superclass declared in the DSL).
- Attaches the class to the protocol.
- Installs generated C-callable method wrappers via `class_addMethod`.

### Current constraints

- Protocol methods in the concept are treated as required instance methods.
- Implementations must exist for every required protocol method.
- Implementation signatures must match protocol signatures.
- Generated wrappers treat `self` as borrowed runtime object (`ID`) to avoid ARC
  ownership side effects in the wrapper boundary.
- `objcImpl` emits Nim marker types:
  - `<ProtocolName> = object of ProtocolPrototype`
  - `<ClassName> = object of <DeclaredSuperclass>`
  This enables typedesc lookup with `getProtocol(MyProtocolType)` and
  `getClass(MyClassType)` with compile-time type constraints.
- Protocol conformance syntax:
  - single protocol: `type MyClass {.impl: MyProtocol.} = object of NSObject`
  - multiple protocols:
    `type MyClass {.impl: (Proto1, Proto2).} = object of NSObject`
  - repeated pragma form is also supported:
    `type MyClass {.impl: Proto1, impl: Proto2.} = object of NSObject`
- Constructor policy procs are passed through as normal Nim declarations.
  This is useful for disabling convenience constructors with `.error`:

```nim
objcImpl:
  type MyProtocol =
    concept self
      method ping(self: MyProtocol)

  type MyClass {.impl: MyProtocol.} = object of NSObject

  proc new*(t: typedesc[MyClass]): MyClass {.error.}
  proc init*(t: typedesc[MyClass]): MyClass {.error.}
  proc init*(v: var MyClass): MyClass {.error.}

  method ping(self: MyClass) = discard
```
