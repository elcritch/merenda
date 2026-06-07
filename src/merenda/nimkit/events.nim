import ./types

type
  MouseButton* = enum
    mbPrimary
    mbSecondary
    mbOther

  KeyModifier* = enum
    kmShift
    kmControl
    kmOption
    kmCommand

  Key* = enum
    keyUnknown = 0
    keyA
    keyB
    keyC
    keyD
    keyE
    keyF
    keyG
    keyH
    keyI
    keyJ
    keyK
    keyL
    keyM
    keyN
    keyO
    keyP
    keyQ
    keyR
    keyS
    keyT
    keyU
    keyV
    keyW
    keyX
    keyY
    keyZ
    keyTilde
    key1
    key2
    key3
    key4
    key5
    key6
    key7
    key8
    key9
    key0
    keyMinus
    keyEqual
    keyF1
    keyF2
    keyF3
    keyF4
    keyF5
    keyF6
    keyF7
    keyF8
    keyF9
    keyF10
    keyF11
    keyF12
    keyF13
    keyF14
    keyF15
    keyLeftControl
    keyRightControl
    keyLeftShift
    keyRightShift
    keyLeftOption
    keyRightOption
    keyLeftCommand
    keyRightCommand
    keyLeftBracket
    keyRightBracket
    keySpace
    keyEscape
    keyEnter
    keyTab
    keyBackspace
    keyMenu
    keySlash
    keyDot
    keyComma
    keySemicolon
    keyQuote
    keyBackslash
    keyPageUp
    keyPageDown
    keyHome
    keyEnd
    keyInsert
    keyDelete
    keyArrowLeft
    keyArrowRight
    keyArrowUp
    keyArrowDown
    keyNumpad0
    keyNumpad1
    keyNumpad2
    keyNumpad3
    keyNumpad4
    keyNumpad5
    keyNumpad6
    keyNumpad7
    keyNumpad8
    keyNumpad9
    keyNumpadDot
    keyAdd
    keySubtract
    keyMultiply
    keyDivide
    keyCapsLock
    keyNumLock
    keyScrollLock
    keyPrintScreen
    keyPause
    keyLevel3Shift
    keyLevel5Shift

  MouseEvent* = object
    location*: Point
    button*: MouseButton
    clickCount*: int
    modifiers*: set[KeyModifier]
    timestamp*: float

  ScrollEventPhase* = enum
    sepNone
    sepBegan
    sepChanged
    sepEnded
    sepCancelled

  ScrollEvent* = object
    location*: Point
    deltaX*: float32
    deltaY*: float32
    phase*: ScrollEventPhase
    momentumPhase*: ScrollEventPhase
    modifiers*: set[KeyModifier]
    timestamp*: float

  KeyEvent* = object
    text*: string
    key*: Key
    keyCode*: int
    modifiers*: set[KeyModifier]
