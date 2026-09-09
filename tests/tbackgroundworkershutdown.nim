## Requires its own process and import graph: the shared component runners
## import merenda/nimkit, whose umbrella lifetime guard would hide regressions
## in the lifetime of directly imported worker modules.
import integrations/backgroundworkershutdown
