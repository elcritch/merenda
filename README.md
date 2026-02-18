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

let obj = PingClass.new()
obj.ping()
doAssert pingCount == 1
doAssert obj.add(2.cint) == 2.cint
doAssert obj.add(3.cint) == 5.cint
```

### Behavior

- Creates/registers protocol if missing (`allocateProtocol` + `registerProtocol`).
- Adds required instance method descriptions to the protocol.
- Creates/registers class if missing (using the superclass declared in the DSL).
- Attaches the class to the protocol.
- Installs generated C-callable method wrappers via `class_addMethod`.
- Emits Nim-callable helper procs for implemented methods, so `obj.ping()` and
  `obj.add(...)` call through Objective-C message send.

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

### Super-call helpers

`nutella/objc` also exports convenience helpers for calling superclass
implementations from custom runtime methods:

```nim
method dealloc(self: MyClass) =
  # custom cleanup...
  superDealloc(self)

method retainCountFromSuper(self: MyClass): cint =
  callSuperAs[NSUInteger](self, selector("retainCount")).cint
```

### Associated Nim `ref` storage

Attach typed Nim `ref` state to Objective-C objects using associated objects:

```nim
type MyStateObj = object
  count: int
type MyState = ref MyStateObj

var o = NSObject.new()
setAssociatedRef(o, MyState(count: 1))

let st = o.getAssociatedRef(MyState)
doAssert st != nil
doAssert st.count == 1

clearAssociatedRef[MyState](o)
doAssert o.getAssociatedRef(MyState) == nil
```

### Ivar-backed Nim `ref` storage (pure runtime classes)

For classes you create at runtime, you can store Nim `ref` values in class ivars:

```nim
import nutella/objc
import nutella/ivar

type MyStateObj = object
  count: int
type MyState = ref MyStateObj

proc myDealloc(self: ID, cmd: SEL) {.cdecl, raises: [].} =
  discard cmd
  clearIvarRefs(self) # release all registered Nim ivar refs
  var superCall = ObjcSuper(receiver: self, superClass: getSuperclass(getClass(self)))
  discard cast[proc(superObj: var ObjcSuper, op: SEL): ID {.cdecl, varargs.}](
    objc_msgSendSuper
  )(superCall, selector("dealloc"))

var cls: ObjcClass
addClass("MyRuntimeClass", "NSObject", cls):
  discard addRefIvar[MyState](cls) # must be done before registerClassPair
  discard addMethod(cls, selector("dealloc"), cast[IMP](myDealloc), "v@:")
```

Then use `setIvarRef`, `getIvarRef`, and `clearIvarRef` on instances.
