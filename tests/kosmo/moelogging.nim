import std/unittest

import merenda/kosmo/moelogging
import moepkg/message_log as moeMessages

suite "Kosmo Moe logging":
  test "new editor messages are forwarded once":
    discard forwardMoeMessages()
    moeMessages.addMessageLog("Moe test notice")
    check forwardMoeMessages() == 1
    check forwardMoeMessages() == 0
    moeMessages.addMessageLog("Moe second test notice")
    check forwardMoeMessages() == 1
