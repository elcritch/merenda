## Forward Moe's public editor message log through Merenda's Chronicles output.

import pkg/chronicles
import moepkg/message_log as moeMessages

var nextMoeMessage {.threadvar.}: int
var moeMessageForwardingStarted {.threadvar.}: bool

proc startMoeMessageForwarding*() =
  ## Start with messages produced after Kosmo first creates a Moe editor.
  if not moeMessageForwardingStarted:
    nextMoeMessage = moeMessages.messageLogLen()
    moeMessageForwardingStarted = true

proc forwardMoeMessages*(): int {.discardable.} =
  ## Print new Moe editor messages through the configured Chronicles sinks.
  if not moeMessageForwardingStarted:
    startMoeMessageForwarding()
  let count = moeMessages.messageLogLen()
  if count < nextMoeMessage:
    nextMoeMessage = 0
  if count == nextMoeMessage:
    return
  let messages = moeMessages.getMessageLog()
  for index in nextMoeMessage ..< messages.len:
    info "Moe message", detail = messages[index]
    inc result
  nextMoeMessage = messages.len

proc logMoeFailure*(operation, path, message: string) =
  ## Report a Moe operation error that was returned directly to Kosmo.
  error "Moe operation failed", operation = operation, path = path, detail = message
