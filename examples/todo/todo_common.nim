## Sample tasks and progress text shared by the todo demos.

const SampleTodos* = ["Write release notes", "Tag v0.4.0", "Try the demo"]

func todoProgress*(completed, total: int): string =
  $completed & " of " & $total & " done"
