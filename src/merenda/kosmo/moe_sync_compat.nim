## Results operators required by Moe when Celina's synchronous backend is used.
##
## Moe currently receives these transitively from Celina's Chronos backend.
## Import only the operators its synchronous modules need, avoiding the
## conflicting `Option` helpers exported by the complete Results package.

import pkg/results as pkgResults

export pkgResults.isOk, pkgResults.get
