## Optional built-in categories for intrinsic measurement diagnostics.
## Subclasses are grouped under the first matching category; applications can
## install their own classifier to distinguish additional widget types.
import ./controls/buttons
import ./containers/[collectionviews, formviews, scrollviews, stackviews]
import ./directviews/runtime
import ./text/[textfields, textviews]
import ./view/viewgeometry

proc defaultIntrinsicProfileCategory*(view: View): string {.nimcall, raises: [].} =
  if view of Label:
    "Label"
  elif view of TextField:
    "TextField"
  elif view of Button:
    "Button"
  elif view of DirectView:
    "DirectView"
  elif view of StackView:
    "StackView"
  elif view of FormView:
    "FormView"
  elif view of CollectionView:
    "CollectionView"
  elif view of ScrollView:
    "ScrollView"
  elif view of TextView:
    "TextView"
  else:
    "OtherView"

proc useDefaultIntrinsicProfileCategories*() =
  ## Installs the built-in classifier for the current thread.
  setIntrinsicProfileClassifier(defaultIntrinsicProfileCategory)
