# Plan: Make `level_creator.tscn` + `mapping.gd` Flexible for Adding/Removing Inputs

## 1. Current Inflexibilities (The "Why")

### `mapping.gd`

**File:** `scripts/editor/level_creator/mapping.gd`

| #   | Problem                                                                                                                                                                                                                       | Location                                                                                                         | Impact                                                                                                                     |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| 1   | Hardcoded `@onready` node lookups via `%name` and `$path`. If a node is renamed, removed, or re-parented in the `.tscn`, the variable becomes `null` and the script errors at runtime.                                        | Lines 58–84 (`%MappingPreviewPlayer`, `%LineGenerator`, `$Border/VBoxContainer/beat_column/BeatYPosition`, etc.) | Every UI addition/deletion requires coordinated edits in both `.tscn` and `.gd`.                                           |
| 2   | `ShapeOption` (`OptionButton`) has hardcoded items in the `.tscn` (`L`, `U`, `Square`, `HLine`, `VLine`), while the logic drives options from `ShapeLibrary.NAMES` (14 entries). The two can drift out of sync.               | `level_creator.tscn` lines 893–903; `_fill_shape_options()` in `mapping.gd` lines 908–917                        | Adding a shape requires touching both files; the `.tscn` defaults are misleading.                                          |
| 3   | Fixed two-column layout assumption: exactly `beat_column` and `shape_column` under `Border/VBoxContainer`.                                                                                                                    | Lines 63–64, `_position_shape_node()`, `_refresh_marker_positions()`                                             | Adding a third input column (e.g., hit-sound column, modifier column) requires new script paths and new positioning logic. |
| 4   | Signal connections are hardcoded in the `.tscn` connection block (e.g., `AddBeatButton.pressed` → `_on_add_beat_button_pressed`).                                                                                             | `level_creator.tscn` lines 1378–1379                                                                             | A new input button requires a `.tscn` node, GDScript handler, and connection entry — three touchpoints.                    |
| 5   | No input registry. Beats (`_marker_nodes`, `_rebuild_markers`) and shapes (`_shape_nodes`, `_spawn_shape_node`) use separate, duplicated code paths. Undo state (`_capture_state()`) only knows beats, shapes, and selection. | Lines 1539–1557, 792–810, 242–248                                                                                | Any new input type is invisible to undo/redo and difficulty save/load.                                                     |
| 6   | Beat/shape positioning is tied to global `beat_y()` / `shape_y()` lookups of specific anchor nodes.                                                                                                                           | Lines 1395–1406                                                                                                  | Moving or adding input rows requires path/script changes.                                                                  |

### `level_creator.tscn`

**File:** `scenes/menus/level_creator.tscn`

- Rigid node hierarchy under `MAPPING`:
  - `Border`
    - `VBoxContainer`
      - `beat_column`
      - `shape_column`
      - Standalone controls (`Controls`, `BeatButtons`, `LineGenerator`, `MappingPreviewCurrentPos`).
- ShapeOption items are baked into the scene (lines 893–903).
- All signal connections are declared statically at the bottom (lines 1329–1388).

---

## 2. Design Goals

1. **Single Source of Truth:** An input is registered by name once; the script discovers it, not the other way around.
2. **Fail Loud, Fail Early:** `_ready()` validates every referenced input node and reports missing/miswired nodes with clear toasts/errors instead of silent `null` crashes.
3. **Data-Driven Shapes:** Shape option lists and beat counts come exclusively from `ShapeLibrary`. The `.tscn` ships with an empty `ShapeOption`.
4. **Extensible Undo/Redo:** `_capture_state()` / `_apply_state()` iterate over registered input types so new inputs automatically join history.
5. **Add/Remove Without Touching Both Files:** Adding a beat row, shape column, or control button should be possible from the `.tscn` (or a registration call) without rewriting `_ready()` lookups.

---

## 3. Proposed Architecture (Phases)

### Phase 0 — Read-Only Safety Check (No Code Changes Yet)

Confirm there are no other callers of `mapping.gd`'s node path lookups or hardcoded shape names outside `ShapeLibrary` and `mapping.gd`.

**Already verified:** `chart_exporter.gd` uses only `ShapeLibrary.points`.

### Phase 1 — Safe Node Access Layer (`mapping.gd`)

- Replace bare `@onready var X = %Y` / `$path` lookups with a small helper:

```gdscript
func _get_input_node(path_or_name: String, required: bool = true) -> Node:
    # Tries %name lookup, then $path.
    # Returns null with push_warning() if missing.
```

- Keep typed `@onready` variables for the handful of always-present core nodes:
  - `mapping_player`
  - `timeline`
  - `_line_generator`
  - `_markers_root` (created in code)
  - `_shapes_root`
- Resolve the remaining UI inputs through the helper, with null checks at first use.
- Add `_validate_inputs()` in `_ready()` to assert that every expected input node exists and log a summary toast.

### Phase 2 — Input Registry

Define an `InputSlot` dictionary/class:

```gdscript
{
    "name": String,
    "type": String,
    "node": Node,
    "on_add": Callable,
    "on_remove": Callable,
    "on_clear": Callable,
    "state_key": String
}
```

**Registry:**

- A `Dictionary` keyed by input name.

**Methods:**

```gdscript
register_input(name, slot)
unregister_input(name)
get_input(name)
```

**Built-in registrations in `_ready()`:**

- `beats` → markers under `beat_column`
- `shapes` → shape nodes under `shape_column`
- `difficulties` → `DifficultyOption`

Any child of a new `inputs_container` in the `.tscn` can optionally self-register through a small `EditorInput.gd` script.

### Phase 3 — Data-Driven Shape List

- Remove hardcoded `item_count` / `popup/item_*` entries from `ShapeOption` in `level_creator.tscn`.
- Leave it empty; `_fill_shape_options()` populates it from `ShapeLibrary.NAMES` at runtime (already implemented, just remove stale defaults).
- Keep `_fill_shape_options()` filtering by:

```gdscript
_shape_required_beats(shape_name) == selected.size()
```

Adding shapes to `ShapeLibrary.NAMES` should automatically make them available in the dropdown.

### Phase 4 — Extensible State Capture (Undo/Redo + Difficulty Save/Load)

- Extend `_capture_state()` to snapshot each registered input's state through an optional `capture_state()` callable on the slot.
- Extend `_apply_state()` to restore state through `apply_state(state)` on each slot.
- Difficulty entries:

```gdscript
difficulties[diff_name]["beats"]
difficulties[diff_name]["shapes"]
```

Gain an extensible `"inputs"` dictionary so new input types can round-trip through import/export and difficulty switching.

### Phase 5 — `.tscn` Structural Cleanup (`level_creator.tscn`)

- Wrap the beat/shape columns in a named container (e.g., `InputsContainer`).
- Scripts should query:

```gdscript
get_node(".../InputsContainer").get_children()
```

Instead of hardcoded `beat_column` / `shape_column` paths.

- Keep static signal connections for statically placed buttons.
- For dynamically added inputs, connect in code through `_safe_connect()` (already exists at line 1560).
- Ensure all referenced nodes have `unique_name_in_owner = true` so `%` lookups remain stable.

### Phase 6 — Verification Helpers

- Add a `_ready()` validation toast:

```text
Level Creator: N inputs registered, M missing
```

During development (can be gated behind a debug build flag).

**Manual verification checklist:**

- [ ] Add a dummy beat column node in the `.tscn`.
- [ ] Register it.
- [ ] Confirm undo/redo captures it.
- [ ] Remove it.
- [ ] Confirm there are no crashes.

---

## 4. File-by-File Change Summary

| File                                            | Changes                                                                                                                                                                                                                                                           |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/editor/level_creator/mapping.gd`       | Add `_get_input_node()` + validation; implement `InputSlot` registry; register beats/shapes/difficulties; extend `_capture_state()` / `_apply_state()`; guard peripheral `@onready` uses with null checks; keep `_fill_shape_options()` driven by `ShapeLibrary`. |
| `scenes/menus/level_creator.tscn`               | Remove hardcoded `ShapeOption` items; introduce `InputsContainer` wrapping beat/shape columns (optional but recommended); ensure `unique_name_in_owner = true` on all referenced nodes.                                                                           |
| `scripts/editor/level_creator/shape_library.gd` | No changes required. It is already the single source of truth for names, points, and beat counts.                                                                                                                                                                 |
| `scripts/editor/level_creator/level_creator.gd` | No structural changes. It already treats `mapping_group` as an opaque control.                                                                                                                                                                                    |

---

## 5. Acceptance Criteria

- [ ] Renaming or deleting any node referenced by `mapping.gd` in `level_creator.tscn` produces a clear warning in `_ready()`, not a `null` crash.
- [ ] Adding a new shape to `ShapeLibrary.NAMES` automatically makes it appear in `ShapeOption` without editing the `.tscn`.
- [ ] Adding a new input column/node to the mapping UI requires only registering it (or placing it under `InputsContainer`), not editing hardcoded `$paths`.
- [ ] Undo/redo (`Ctrl+Z` / `Ctrl+Y` / hold shortcuts) and difficulty switching preserve any newly registered input type.
- [ ] Existing behavior for beats, shapes, difficulties, import, export, and the custom shape editor remains unchanged.

---

## 6. Risks & Rollback

### Risks

| Risk                                                                                        | Mitigation                                                                                                                                               |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Changing `@onready` lookups to lazy resolution could reorder initialization vs. `_ready()`. | Keep core nodes (`mapping_player`, `timeline`, `_line_generator`, `_markers_root`, `_shapes_root`) as `@onready`; only peripheral UI inputs become lazy. |
| `unique_name_in_owner` lookups break if two nodes share a name.                             | Audit names during Phase 5.                                                                                                                              |

### Rollback

- No files have been modified yet, so the current commit is the rollback point.
- If implemented, keep the old `$path` / `%` lines as fallbacks behind a feature flag for one release.

---

## Next Step

If this plan looks good, switch out of Plan mode (e.g., say **"implement"**) and start with Phase 1: safe node access + validation in `mapping.gd`.

Would you like to prioritize any phase first, or adjust the scope (e.g., include custom shape editor inputs in the registry)?
