import std/[monotimes, os, times, unittest]
import sigils/[core, reactive]
import merenda/nimkit
import merenda/foundation/mainthreadwork
import ../../examples/direct_lifetimes_demo

suite "explicit controller visibility policy":
  test "appearance resumes the retained label at the current value":
    let controller = newLifetimeController()
    let label = Label(controller.content.viewWithIdentifier("observed-count"))
    controller.showContent(false)
    controller.count <- 1
    controller.count <- 2
    discard drainMainThreadWork()
    check label.stringValue == "Latest count: 0"
    controller.showContent(true)
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while label.stringValue != "Latest count: 2" and getMonoTime() < deadline:
      discard drainMainThreadWork()
      if label.stringValue != "Latest count: 2":
        sleep(1)
    check label.stringValue == "Latest count: 2"
    check controller.content.viewWithIdentifier("observed-count") == label
    controller.teardown()
