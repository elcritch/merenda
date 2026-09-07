# Kosmo workspace updates

Each Kosmo window owns one `WorkspaceFiles` controller. The file browser and
quick open share its inventory and directory listings. Quick open includes Git's
tracked and non-ignored untracked files; the browser can additionally display
ignored files, empty folders, and Git's deleted paths. Ignored subtrees are listed
on demand rather than recursively indexed.

Scans run on NimKit's shared worker pool. Root changes and filesystem notifications
invalidate older generations, and overlapping requests coalesce into one follow-up
scan. A completed snapshot updates both views without resetting browser expansion
or quick-open selection when the selected file still exists.

## File and Git notifications

With the default `monitorsGitStatus = true`, dmon watches workspace roots and Git
metadata. Linked worktrees also watch their external Git directory and common
repository directory. Open buffers outside the browser roots get watch coverage
without adding their folders to the file inventory.

A 100 ms timer delivers queued notifications on the GUI thread; it does not scan
the filesystem itself. Notifications refresh the shared file inventory and Git
decorations and invalidate Moe's event-driven Git cache. As protection against
missed notifications, a quiet workspace requests the same full refresh two minutes
after its last successfully accepted inventory snapshot. The deadline includes
time spent asleep, so an overdue workspace refreshes promptly after waking. Idle
ticks collect Moe's asynchronous results and repaint changed Git status without
requiring keyboard input. Closing a window removes its subscriptions, while other
windows retain their shared worker and timer threads.

The current dmon 0.5.0 Linux recursive backend has an invalid path concatenation
when watching newly created directories and can assert in its monitor thread.
Kosmo therefore uses a logged three-second polling fallback on Linux until that
dependency is fixed. The same fallback applies if native watch coverage fails or
dmon's 64-watch limit is reached. FreeBSD uses dmon's own snapshot-based backend.

Embedding tools can disable monitoring and call `workspaceFiles.refresh()`
explicitly. `reloadProjectFiles` remains a synchronous compatibility API for
tests and tools; normal quick-open presentation reuses the shared asynchronous
inventory instead of launching another Git listing each time.

## Git process lifetime

File discovery, Git status, find-in-files discovery, and the Git diff panel use
one bounded Git command helper. It drains output while the child runs, limits
commands to ten seconds and output to 128 MiB, and terminates, reaps, and closes
children on cancellation or failure. Filesystem-monitor hooks are disabled for
these commands. Moe's own asynchronous children use the cleanup implementation
from its `fix/git-refresh-lifecycle` branch.
