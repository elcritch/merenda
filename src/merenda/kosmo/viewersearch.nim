## Kosmo document adapters for NimKit's reusable search controller.

import ../nimkit as nimkit
import ../nimkit/text/searchcontrollers
export searchcontrollers

type
  KosmoViewerMatch* = TextSearchLocation
  KosmoViewerSearch* = TextSearchController

proc newKosmoViewerSearch*(
    host: nimkit.View,
    subject: string,
    sources: proc(): seq[string] {.closure.},
    reveal: proc(match: TextSearchLocation) {.closure.},
    clear: proc() {.closure.},
): TextSearchController =
  newTextSearchController(
    host, subject, TextSearchAdapter(sources: sources, reveal: reveal, clear: clear)
  )
