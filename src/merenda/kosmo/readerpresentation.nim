## Presentation contract shared by Kosmo rich-text readers.
import std/options
import ../nimkit as nimkit
import ./themetargets

protocol KosmoReaderPresentationProtocol:
  method readerThemeTarget*(): Option[KosmoThemeTarget]
  method applyReaderStyle*(style: nimkit.MarkdownStyle)

proc readerTarget*(view: nimkit.View): Option[KosmoThemeTarget] =
  ## Ordinary views do not participate in reader presentation.
  if not view.isNil and view.respondsTo(readerThemeTarget()):
    result = view.readerThemeTarget()
