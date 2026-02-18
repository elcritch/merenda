# nutella

`nutella` provides Nim bindings/helpers around the Objective-C runtime.

## `objcImpl` runtime DSL

`objcImpl` declares a runtime protocol and/or runtime class and wires Nim
method implementations as Objective-C instance methods.

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

- Can define protocol-only, class-only, or protocol+class in one block.
- Creates/registers protocol if missing (`allocateProtocol` + `registerProtocol`).
- Adds required instance method descriptions to the protocol.
- Creates/registers class if missing (using the superclass declared in the DSL).
- Attaches the class to listed protocols when both are present.
- Installs generated C-callable method wrappers on the runtime class.
- Emits Nim-callable helper procs for implemented methods, so `obj.ping()` and
  `obj.add(...)` call through Objective-C message send.

### Current constraints

- Protocol methods in the concept are treated as required instance methods.
- When protocol and class are declared together, implementations must exist for
  every required protocol method and signatures must match.
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
import nutella/objc

var deallocCount = 0

objcImpl:
  type SuperCallProtocol =
    concept self
      method retainCountFromSuper(self: SuperCallProtocol): cint

  type SuperCallClass {.impl: SuperCallProtocol.} = object of NSObject

  method retainCountFromSuper(self: SuperCallClass): cint =
    super(NSUInteger, self, retainCount).cint

  method dealloc(self: SuperCallClass) {.used.} =
    inc deallocCount
    superDealloc(self)

let o = SuperCallClass.new()
doAssert o.retainCountFromSuper() == retainCount(o).cint
```

### Ivar Properties

`objcImpl` class fields become Objective-C ivars with generated Nim property
accessors (`self.field` / `self.field = value`).

```nim
import nutella/objc
import nutella/objc/ivar

type CounterStateObj = object
  total: int
  multiplier: int
type CounterState = ref CounterStateObj

objcImpl:
  type CounterClass = object of NSObject
    counter: CounterState

  proc new*(t: typedesc[CounterClass]): CounterClass {.error.}
  proc init*(t: typedesc[CounterClass]): CounterClass {.error.}
  proc init*(v: var CounterClass): CounterClass {.error.}

  proc initWithMultiplier*(v: var CounterClass, m: cint): CounterClass =
    result = asType[CounterClass](super(v, init))
    v.value = nil
    result.counter = CounterState(total: 0, multiplier: m.int)

  method bump(self: CounterClass, amount: cint): cint =
    let st = self.counter
    st.total += amount.int
    result = (st.total * st.multiplier).cint

  method dealloc(self: CounterClass) {.used.} =
    clearIvarRefs(self)
    superDealloc(self)

var c = CounterClass.alloc()
c = c.initWithMultiplier(2.cint)
doAssert c.bump(3.cint) == 6.cint
```

Use `clearIvarRefs(self)` in `dealloc` to release ivar-backed Nim refs.
