import sigils/selectors

import ./types

export selectors

type
  EmptyArgs* = tuple[]

  MouseEventArgs* = object
    event*: MouseEvent

  KeyEventArgs* = object
    event*: KeyEvent

  ActionArgs* = object
    sender*: DynamicAgent

  CommandArgs* = object
    sender*: DynamicAgent

  ValidationArgs* = object
    item*: DynamicAgent

  MouseEventSelector* = Selector[MouseEventArgs, EmptyArgs]
  KeyEventSelector* = Selector[KeyEventArgs, EmptyArgs]
  ActionSelector* = Selector[ActionArgs, EmptyArgs]
  CommandSelector* = Selector[CommandArgs, EmptyArgs]
  ValidationSelector* = Selector[ValidationArgs, bool]

proc mouseDownSelector*(): MouseEventSelector =
  selector[MouseEventArgs, EmptyArgs]("mouseDown")

proc mouseUpSelector*(): MouseEventSelector =
  selector[MouseEventArgs, EmptyArgs]("mouseUp")

proc keyDownSelector*(): KeyEventSelector =
  selector[KeyEventArgs, EmptyArgs]("keyDown")

proc performClickSelector*(): ActionSelector =
  selector[ActionArgs, EmptyArgs]("performClick")

proc sendActionSelector*(): ActionSelector =
  selector[ActionArgs, EmptyArgs]("sendAction")

proc tryToPerformSelector*(): CommandSelector =
  selector[CommandArgs, EmptyArgs]("tryToPerform")

proc doCommandBySelectorSelector*(): CommandSelector =
  selector[CommandArgs, EmptyArgs]("doCommandBySelector")

proc noResponderForSelector*(): CommandSelector =
  selector[CommandArgs, EmptyArgs]("noResponderFor")

proc validateUserInterfaceItemSelector*(): ValidationSelector =
  selector[ValidationArgs, bool]("validateUserInterfaceItem")

proc actionSelector*(name: string): ActionSelector =
  selector[ActionArgs, EmptyArgs](name)
