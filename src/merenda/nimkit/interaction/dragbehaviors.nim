## Geometry-only discrete D2 behavior. Preview and drop state remain separate.
import std/math
import ../foundation/types

type
  DragTarget* = object
    position*: Point
    eligible*: bool

  DragChoice* = object
    index*: int
    gap*: float32

  DragOptions* = object
    threshold*: float32
    stickiness*: float32
    snapRadius*: float32
    floating*: bool
    transitionSeconds*: float32

func initDragOptions*(): DragOptions =
  DragOptions(
    threshold: 4,
    stickiness: 6,
    snapRadius: Inf,
    floating: true,
    transitionSeconds: 0.16,
  )

func distance*(a, b: Point): float32 =
  hypot(a.x - b.x, a.y - b.y)

func finite*(point: Point): bool =
  classify(point.x) notin {fcNan, fcInf, fcNegInf} and
    classify(point.y) notin {fcNan, fcInf, fcNegInf}

func closest*(
    targets: openArray[DragTarget],
    pointer: Point,
    previous = -1,
    stickiness = 0.0'f32,
    snapRadius = Inf.float32,
): DragChoice =
  ## Stable input-order ties; retain the previous choice within `stickiness`
  ## logical pixels. A radius miss or invalid geometry returns index -1.
  result = DragChoice(index: -1, gap: Inf)
  if not pointer.finite:
    return
  var bestScore = Inf.float32
  for i, target in targets:
    if target.eligible and target.position.finite:
      let gap = distance(pointer, target.position)
      let score = gap - (if i == previous: max(0.0'f32, stickiness)
      else: 0.0'f32)
      if gap <= snapRadius and score < bestScore:
        result = DragChoice(index: i, gap: gap)
        bestScore = score
