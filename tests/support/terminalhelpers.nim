## Observable command completion for tests of the asynchronous terminal API.
import std/[monotimes, os, times, unittest]
import sigils/threads
import merenda/nimkit/terminal/terminalviews

proc waitForCommands*(session: TerminalViewSession) =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while session.pendingCommands() > 0 and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    discard session.poll()
    sleep(1)
  require session.pendingCommands() == 0

proc pollSettled*(view: TerminalView): TerminexPollResult =
  view.session().waitForCommands()
  view.poll()

proc closeAndWait*(session: TerminalViewSession) =
  session.close()
  session.waitForCommands()
