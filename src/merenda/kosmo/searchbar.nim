## Kosmo aliases for NimKit's reusable search controls.

import ../nimkit/controls/searchbars
export searchbars

type
  KosmoSearchBar* = SearchBar
  KosmoSearchQueryAction* = SearchQueryAction
  KosmoSearchAction* = SearchAction

const
  KosmoSearchBarWidth* = SearchBarWidth
  KosmoSearchBarHeight* = SearchBarHeight
  KosmoSearchBarInset* = SearchBarInset

proc newKosmoSearchBar*(
    accessibilitySubject: string,
    onQueryChanged: SearchQueryAction,
    onPrevious, onNext, onClose: SearchAction,
): SearchBar =
  newSearchBar(accessibilitySubject, onQueryChanged, onPrevious, onNext, onClose)
