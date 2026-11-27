## Classify local branches against the repository's default branch.

import std/[strutils, tables]
import ./processes

const
  LocalBranchPrefix = "refs/heads/"
  OriginBranchPrefix = "refs/remotes/origin/"

type
  GitBranchInfo* = object
    name*, head*: string
    merged*, protected*: bool

  GitBranchMergeCache* = object
    baseHeads: seq[string]
    mergedHeads: Table[string, bool]

  GitBranchBase = tuple[head, tree: string]

proc gitOutput(root: string, arguments: openArray[string]): string =
  let response = runGitCommand(root, arguments)
  if response.exitCode == 0:
    result = response.output.strip()

proc cleanupBases(root: string): tuple[name: string, bases: seq[GitBranchBase]] =
  let originHead =
    gitOutput(root, ["symbolic-ref", "--quiet", OriginBranchPrefix & "HEAD"])
  let names =
    if originHead.startsWith(OriginBranchPrefix):
      @[originHead[OriginBranchPrefix.len .. ^1]]
    else:
      @["main", "master", "trunk"]
  for name in names:
    for prefix in [LocalBranchPrefix, OriginBranchPrefix]:
      let info = gitOutput(
          root,
          ["show", "-s", "--no-show-signature", "--format=%H%n%T", prefix & name, "--"],
        )
        .splitLines()
      if info.len == 2:
        result.name = name
        let base = (info[0], info[1])
        if base notin result.bases:
          result.bases.add base
    if result.bases.len > 0:
      break

proc branchMerged(root, head, baseHead, baseTree: string): bool =
  if runGitCommand(root, ["merge-base", "--is-ancestor", head, baseHead]).exitCode == 0:
    return true
  # A squash changes commit IDs. A clean virtual merge that leaves the base
  # tree byte-for-byte identical proves the branch adds no content changes.
  gitOutput(root, ["merge-tree", "--write-tree", baseHead, head]) == baseTree

proc mergedIntoBase(root, head: string, bases: openArray[GitBranchBase]): bool =
  for base in bases:
    if branchMerged(root, head, base.head, base.tree):
      return true

proc readGitBranches*(
    root: string, cache: var GitBranchMergeCache
): tuple[base: string, branches: seq[GitBranchInfo]] =
  let (baseName, bases) = cleanupBases(root)
  result.base = baseName
  var baseHeads: seq[string]
  for base in bases:
    baseHeads.add base.head
  if cache.baseHeads != baseHeads:
    cache = GitBranchMergeCache(baseHeads: baseHeads)
  let refs = gitOutput(
    root,
    [
      "for-each-ref", "--format=%(refname:lstrip=2)%00%(objectname)%00%(worktreepath)",
      LocalBranchPrefix,
    ],
  )
  if refs.len == 0:
    # Older Git builds can list branches even if they lack worktreepath.
    for name in gitOutput(
      root, ["for-each-ref", "--format=%(refname:lstrip=2)", LocalBranchPrefix]
    )
        .splitLines():
      if name.len > 0:
        result.branches.add GitBranchInfo(name: name, protected: true)
    return
  for line in refs.splitLines():
    let fields = line.split('\0')
    if fields.len == 3:
      var branch = GitBranchInfo(
        name: fields[0],
        head: fields[1],
        protected: fields[0] == baseName or fields[2].len > 0,
      )
      if not branch.protected and bases.len > 0:
        if branch.head notin cache.mergedHeads:
          cache.mergedHeads[branch.head] = mergedIntoBase(root, branch.head, bases)
        branch.merged = cache.mergedHeads[branch.head]
      result.branches.add branch

proc removeGitBranches*(
    root: string,
    selected: openArray[GitBranchInfo],
    mergedOnly: bool,
    cache: var GitBranchMergeCache,
): GitCommandResult =
  let snapshot = readGitBranches(root, cache)
  var branches: Table[string, GitBranchInfo]
  for branch in snapshot.branches:
    branches[branch.name] = branch
  for requested in selected:
    let current = branches.getOrDefault(requested.name)
    let reference = LocalBranchPrefix & requested.name
    var failure: string
    if current.head.len == 0 or current.head != requested.head or
        gitOutput(root, ["rev-parse", "--verify", reference]) != requested.head:
      failure = "The branch changed or no longer exists."
    elif current.protected:
      failure = "The branch is the default branch or is checked out in a worktree."
    elif mergedOnly and not current.merged:
      failure = "The merge into the default branch could not be verified."
    else:
      # Git's branch command checks every linked worktree and removes the branch's
      # upstream configuration along with the ref.
      let removal = runGitCommand(root, ["branch", "-D", "--", requested.name])
      if removal.exitCode != 0:
        failure = removal.output.strip()
        if failure.len == 0:
          failure = "Git could not delete the branch."
    if failure.len > 0:
      result.exitCode = 1
      result.output.add requested.name & " — " & failure & "\n"
