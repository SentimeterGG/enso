# Main Thread Performance Analysis

## 📋 Summary Table

| File                                           | Function                                        | Severity         | Main Thread? | Notes                                                               |
| ---------------------------------------------- | ----------------------------------------------- | ---------------- | ------------ | ------------------------------------------------------------------- |
| `scripts/chart/ensz_archive.gd`                | ZIP extract/pack                                | 🔴 Heavy         | ✅ Yes        | Large archives can take several seconds.                            |
| `scripts/chart/chart_parser.gd`                | `load()`                                        | 🟡–🔴 Mid-Heavy  | ✅ Yes        | Big charts take 1–2 seconds; called on hover in the level selector. |
| `scripts/gameplay/notes/note_manager.gd`       | `bake()`                                        | 🟡–🔴 Mid-Heavy  | ✅ Yes        | Creates one node per note; freezes on song start.                   |
| `scripts/gameplay/notes/beat/beat_receptor.gd` | `_sweep_misses()` / `try_hit()`                 | 🟡 Mid           | ✅ Yes        | O(n) iteration over all beat children every frame.                  |
| `scripts/editor/level_creator/mapping.gd`      | `_rebuild_markers()` / `_rebuild_shape_nodes()` | 🟡 Mid           | ✅ Yes        | Stutters during large chart edits.                                  |
| `scripts/editor/drawing/recognizer.gd`         | `compare()` / `guess()`                         | 🔴 Heavy compute | ❌ No         | Runs on `WorkerThreadPool` — thread-safe.                           |
| `scripts/core/global.gd`                       | `load_safely()` (sync)                          | 🟡 Mid           | ✅ Yes        | Image/audio decoding blocks the main thread.                        |

## 🚀 Recommendations

If you want to reduce main-thread stutters, consider the following optimizations:

### 1. Move `chart_parser.gd` loading to a worker thread

- Currently called synchronously in multiple places, including game start and level hover.
- Parsing large charts during hover can cause noticeable frame hitches.
- Consider using `WorkerThreadPool` for CPU-intensive parsing.

### 2. Move `ensz_archive.gd` extraction to a background thread

- Importing large level packs currently freezes the game.
- Move ZIP extraction and packing operations to a background thread where possible.
- Keep UI updates and scene interactions on the main thread.

### 3. Optimize `beat_receptor.gd`

- Instead of iterating over all children every frame, maintain a sorted list or timer heap of upcoming notes.
- This can reduce unnecessary iterations.
- Aim for O(1) amortized miss detection where possible.

### 4. Batch node creation in `note_manager.gd`

- Consider instantiating notes in chunks over multiple frames instead of creating all nodes at once in `bake()`.
- This helps distribute the workload and reduce startup freezes.

### 5. Prefer `load_safely_async()` over `load_safely()`

- Use asynchronous loading wherever possible to avoid blocking the main thread during image/audio decoding.
- Reserve synchronous loading for cases where immediate resource availability is required.

## 🎯 Priority Order

| Priority | Optimization              | Reason                                   |
| -------- | ------------------------- | ---------------------------------------- |
| 1        | Async chart parsing       | Prevents level selector hover hitches.   |
| 2        | Background ZIP extraction | Prevents freezes during level imports.   |
| 3        | Batch note creation       | Reduces gameplay startup freezes.        |
| 4        | Optimize beat receptor    | Reduces per-frame CPU overhead.          |
| 5        | Async resource loading    | Improves general loading responsiveness. |

Goal: Keep expensive CPU operations off the main thread while ensuring all scene-tree and UI operations remain on the main thread.
