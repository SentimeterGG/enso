# Plan: Make `level_creator.tscn`, `mapping.gd`, and `metadata.gd` Flexible for Adding/Removing Inputs

## 1. What Is Still Not Flexible (Current State)

### `mapping.gd` — scripts/editor/level_creator/mapping.gd

| # | Problem | Location | Impact |
|---|---------|----------|--------|
| 1 | Hardcoded `@onready` node lookups via `%name` and `$path`. Renaming/removing/re-parenting a node in the `.tscn` makes the variable `null` and causes runtime crashes. | Lines 58–84 (`%MappingPreviewPlayer`, `%LineGenerator`, `%BeatBG`, `%ShapeOption`, `%DifficultyOption`, `$Border/VBoxContainer/beat_column/BeatYPosition`, etc.) | Every UI change requires coordinated edits in both `.tscn` and `.gd`. Missing nodes fail silently until first use. |
| 2 | `ShapeOption` (`OptionButton`) has hardcoded items baked into the `.tscn` (`L`, `U`, `Square`, `HLine`, `VLine`), while the logic drives options from `ShapeLibrary.NAMES` (14 entries). The two drift out of sync. | `level_creator.tscn` lines 893–903; `_fill_shape_options()` lines 908–917 | Adding a shape requires touching both files; `.tscn` defaults are misleading. |
| 3 | Fixed two-column layout assumption: exactly `beat_column` and `shape_column` under `Border/VBoxContainer`. | Lines 63–64, `_position_shape_node()`, `_refresh_marker_positions()` | Adding a third input column (e.g., hit-sound column, modifier column) requires new script paths and new positioning logic. |
| 4 | Signal connections hardcoded in the `.tscn` connection block. | `level_creator.tscn` lines 1378–1379 | A new input button requires a `.tscn` node, GDScript handler, and connection entry — three touchpoints. |
| 5 | No input registry. Beats (`_marker_nodes`, `_rebuild_markers`) and shapes (`_shape_nodes`, `_spawn_shape_node`) use separate duplicated code paths. Undo state (`_capture_state()`) only knows beats, shapes, and selection. | Lines 1539–1557, 792–810, 242–248 | Any new input type is invisible to undo/redo and difficulty save/load. |
| 6 | Beat/shape positioning tied to global `beat_y()` / `shape_y()` lookups of specific anchor nodes. | Lines 1395–1406 | Moving or adding input rows requires path/script changes. |

### `metadata.gd` — scripts/editor/level_creator/metadata.gd

| # | Problem | Location | Impact |
|---|---------|----------|--------|
| 1 | Hardcoded `@onready` lookups using `%name` / `$path` for every field. | Lines 2–24 (`%SongNameEdit`, `%PreviewSlider`, `$PreviewPlayer`, etc.) | Renaming/removing/re-parenting causes null references and crashes at `_ready` or first use. |
| 2 | `when_export()` returns a fixed dictionary with hardcoded keys: `name`, `source`, `mapper`, `video_bg`, `bg`, `song_src`, `preview_start`, `beat0`, `bpm`, `overall_difficulty`, `color_scheme`, `end_song_position`. | Lines 174–188 | Adding a metadata field requires editing export, import (`_apply_chart_fields`), and timing import (`_apply_chart_timing`). |
| 3 | `is_export_ready()` hardcodes required fields (`name`, `source`, `mapper`, `song`, `bg`, `bpm > 0`, color swatch). | Lines 142–151 | New required fields must be manually added to validation. |
| 4 | Individual signal handlers for each nudge button (`_on_preview_nudge_minus`, `_on_beat_nudge_minus`, etc.). | Lines 278–300 | Adding another time/slider field requires another handler and scene connection. |
| 5 | Audio players hardcoded (`_preview_player`, `_beat_player`, `_end_song_player`). `_bump_audition_id()` / `_audition_id` use `if/elif` chains. | Lines 20–22, 338–350 | Adding an audition player requires modifying player ID logic. |
| 6 | Signal connections hardcoded in `.tscn` connection block, many pointing to `metadata.gd` methods. | `level_creator.tscn` lines 1329–1362 | Adding a metadata button/field requires a node, handler, and scene connection. |
| 7 | Color scheme is partially dynamic via children of `_list`, but tied to one specific `%list_colorscheme` node. | Lines 9, 42–44, 132–140, 165–171, 470–476 | Works, but the pattern isn't generalized to other dynamic input lists. |

### `level_creator.tscn` — scenes/menus/level_creator.tscn

- Rigid node hierarchy under `MAPPING`: `Border → VBoxContainer → beat_column | shape_column`.
- `ShapeOption` items baked into the scene (lines 893–903).
- All signal connections declared statically at the bottom (lines 1329–1388).

---

## 2. How to Make It Flexible

### Design Goals

1. **Single Source of Truth:** An input is registered by name once; scripts discover it rather than hardcoding paths.
2. **Fail Loud, Fail Early:** `_ready()` validates every referenced input node and reports missing/miswired nodes with clear warnings instead of silent `null` crashes.
3. **Data-Driven Shapes:** Shape option lists and beat counts come exclusively from `ShapeLibrary`. The `.tscn` ships an empty `ShapeOption`.
4. **Extensible Undo/Redo:** `_capture_state()` / `_apply_state()` iterate over registered input types so new inputs automatically join history.
5. **Add/Remove Without Touching Both Files:** Adding a beat row, shape column, control button, or metadata field should be possible from the `.tscn` (or a registration call) without rewriting `_ready()` lookups.

### Phase 1 — Safe Node Access Layer (`mapping.gd` + `metadata.gd`)

Replace bare `@onready var X = %Y` / `$path` with a lazy helper that tries `%name` then `$path`, warns if missing, and returns `null`:

```gdscript
func _get_input_node(path_or_name: String, required: bool = true) -> Node:
    # Tries %name lookup, then $path.
    # Returns null with push_warning() if missing.
```

- Keep typed `@onready` for always-present core nodes (`mapping_player`, `timeline`, `_line_generator`, `_markers_root`, `_shapes_root` in mapping; `_preview_player`, `_beat_player`, `_end_song_player` in metadata).
- Resolve peripheral UI inputs through the helper, with null checks at first use.
- Add `_validate_inputs()` in `_ready()` asserting expected nodes exist; log a summary toast.

### Phase 2 — Input Registry (`mapping.gd`)

Define an `InputSlot` dictionary:

```gdscript
{
    "name": String,
    "type": String,
    "node": Node,
    "capture_state": Callable,   # optional -> Dictionary
    "apply_state": Callable,     # optional -> void(Dictionary)
    "on_add": Callable,          # optional
    "on_remove": Callable,       # optional
    "on_clear": Callable,        # optional
}
```

Registry: `Dictionary` keyed by input name.

Methods:

```gdscript
register_input(name, slot)
unregister_input(name)
get_input(name)
```

Built-in registrations in `_ready()`:
- `beats` → markers under `beat_column`
- `shapes` → shape nodes under `shape_column`
- `difficulties` → `DifficultyOption`

### Phase 3 — Data-Driven Shape List

- Remove hardcoded `item_count` / `popup/item_*` entries from `ShapeOption` in `level_creator.tscn`.
- Leave it empty; `_fill_shape_options()` populates it from `ShapeLibrary.NAMES` at runtime.
- Keep `_fill_shape_options()` filtering by `_shape_required_beats(shape_name) == selected.size()`.

Adding shapes to `ShapeLibrary.NAMES` automatically makes them available.

### Phase 4 — Extensible State Capture (Undo/Redo + Difficulty Save/Load)

- Extend `_capture_state()` to snapshot each registered input's state through an optional `capture_state()` callable on the slot.
- Extend `_apply_state()` to restore state through `apply_state(state)` on each slot.
- Difficulty entries gain an extensible `"inputs"` dictionary:

```gdscript
difficulties[diff_name]["beats"]
difficulties[diff_name]["shapes"]
difficulties[diff_name]["inputs"]  # new input types round-trip
```

### Phase 5 — Metadata Field Registry (`metadata.gd`)

Replace the fixed export dictionary with a registry:

```gdscript
{
    "key": "bpm",
    "node": bpm_input,
    "get_value": Callable,
    "set_value": Callable,
    "required": true,
}
```

Use the registry for:
- `when_export()` — iterate registry instead of hardcoded keys.
- `_apply_chart_fields()` / `_apply_chart_timing()` — iterate registry.
- `is_export_ready()` — validate fields marked `required: true` automatically.

Adding a new metadata field requires only registering it once.

### Phase 6 — Generic Signal Handlers (`metadata.gd`)

- Reuse existing `_do_nudge(slider, label, player, dir)`.
- Connect nudge buttons via `.bind()` instead of separate `_on_*_nudge_minus/plus` handlers.
- Preserve existing behavior.

### Phase 7 — Extensible Audition Players (`metadata.gd`)

- Replace `if/elif` player ID chains with a dictionary keyed by player instance.
- Registering another audition player becomes straightforward.
- Preserve audition cancellation and ID-checking behavior.

### Phase 8 — `.tscn` Structural Cleanup (`level_creator.tscn`)

- Wrap beat/shape columns in a named container (e.g., `InputsContainer`).
- Scripts query `get_node(".../InputsContainer").get_children()` instead of hardcoded paths.
- Keep static signal connections for statically placed buttons; connect dynamic inputs in code via `_safe_connect()`.
- Ensure all referenced nodes have `unique_name_in_owner = true`.
- Remove hardcoded `ShapeOption` items (Phase 3).

---

## 3. How to Test If It's Working

### 3.1 Validation During `_ready()`

A development toast should summarize registration:

```
Level Creator: N inputs registered, M missing
Metadata: N fields registered, M missing
```

- Renaming or deleting any node referenced by `mapping.gd` or `metadata.gd` in `level_creator.tscn` produces a clear warning during `_ready()`, **not** a null crash.
- Missing optional UI elements do not crash; required missing nodes emit warnings.

### 3.2 Manual Verification Checklist

**Mapping / beats / shapes / difficulties:**

- [ ] Add a beat (`M` key / Add Beat button); undo (`Ctrl+Z`) removes it; redo (`Ctrl+Y`) restores it.
- [ ] Add a shape; undo/redo preserves it.
- [ ] Remove a beat while shapes exist; shapes referencing that beat are stripped correctly.
- [ ] Switch difficulties; beats/shapes/inputs round-trip correctly.
- [ ] Add a new shape to `ShapeLibrary.NAMES`; it appears in `ShapeOption` without editing the `.tscn`.
- [ ] Add a dummy input node under `InputsContainer`; register it; undo/redo captures it; remove it; no crash.
- [ ] Custom shape editor open/close, undo, clear, confirm still work.

**Metadata:**

- [ ] Edit song name / mapper / source / paths; export produces correct dictionary keys.
- [ ] Import a chart; metadata fields populate from registry.
- [ ] Toggle required fields empty; `is_export_ready()` reflects registry-driven validation.
- [ ] Add a new metadata field registration; export/import/validation pick it up without separate edits.
- [ ] Nudge preview / beat / end-song sliders via buttons; behavior unchanged.
- [ ] Audition play/stop for preview, beat, and end-song players; no ID confusion.

**Regression (existing behavior must remain unchanged):**

- [ ] Beats add/remove/move.
- [ ] Shapes add/remove/select/highlight.
- [ ] Difficulties add/rename/save/switch.
- [ ] Metadata import/export.
- [ ] Color scheme selection.
- [ ] Custom shape editor.
- [ ] Audio preview and audition controls.
- [ ] Metadata nudging and timing adjustments.

### 3.3 Automated Regression Checks (where feasible)

- Load the level creator scene; `_ready()` completes with no `null instance` errors.
- `_validate_inputs()` reports zero missing required nodes.
- `when_export()` returns all expected keys and round-trips through import.
- `_capture_state()` / `_apply_state()` round-trip beats, shapes, and selection without data loss.

### 3.4 Test Scenario: Adding a New Input Type

1. Add a new node (e.g., a `Column` for hit-sounds) under `InputsContainer` in `level_creator.tscn`.
2. Register it in `mapping.gd` `_ready()` via `register_input("hitsounds", { ... })`.
3. Implement its `capture_state()` / `apply_state()` if it should participate in undo/redo.
4. Confirm: undo/redo captures the new input; difficulty switching preserves it; no null crashes.

---

## 4. File-by-File Change Summary

| File | Changes |
|------|---------|
| `scripts/editor/level_creator/mapping.gd` | Safe node access (`_get_input_node()` + `_validate_inputs()`); `InputSlot` registry; register beats/shapes/difficulties; extend `_capture_state()` / `_apply_state()`; null-guarded peripheral lookups; shape options driven by `ShapeLibrary`. |
| `scripts/editor/level_creator/metadata.gd` | Safe node access (`_get_input_node()` + `_validate_inputs()`); metadata field registry for generic export/import/validation; generic nudge handlers via `.bind()`; audition player ID dictionary instead of `if/elif`; `is_export_ready()` registry-driven. |
| `scenes/menus/level_creator.tscn` | Remove hardcoded `ShapeOption` items; wrap beat/shape columns in `InputsContainer`; ensure referenced nodes have `unique_name_in_owner = true`; retain static metadata signal connections while allowing dynamic registration. |
| `scripts/editor/level_creator/shape_library.gd` | No changes required. Already the single source of truth. |
| `scripts/editor/level_creator/level_creator.gd` | No structural changes required. Already treats `mapping_group` as an opaque control. |

---

## 5. Acceptance Criteria

- [ ] Renaming or deleting any node referenced by `mapping.gd` or `metadata.gd` produces a clear warning during `_ready()`, rather than a null reference crash.
- [ ] Adding a shape to `ShapeLibrary.NAMES` automatically adds it to `ShapeOption` without requiring a `.tscn` edit.
- [ ] Adding a metadata field only requires registering it once (`key`, `node`, accessors), without separately editing export, import, or validation logic.
- [ ] Undo/redo (`Ctrl+Z` / `Ctrl+Y` / hold shortcuts) and difficulty switching preserve every registered input type in `mapping.gd`.
- [ ] Existing behavior remains unchanged for: beats, shapes, difficulties, metadata import/export, color scheme, custom shape editor, audio preview/audition controls, metadata nudging/timing.
- [ ] A new input column added under `InputsContainer` can be registered and participates in undo/redo without hardcoded `$path` edits.

---

## 6. Implementation Scope and Order

This is the updated implementation plan. Recommended order:

1. **Safe node access layer:** Implement in `mapping.gd` and `metadata.gd` first.
2. **Mapping input registry:** Refactor beats, shapes, and difficulties.
3. **Metadata field registry:** Refactor metadata export, import, and validation.
4. **Generic signal handlers:** Replace repetitive nudge handlers with `.bind()`.
5. **Audition player registry:** Replace player ID conditionals with a dictionary.
6. **Scene cleanup:** Remove hardcoded shape options; prepare dynamic input containers.
7. **Regression testing:** Verify existing behavior, undo/redo, difficulty switching, and metadata round-tripping.

### Important Design Constraint

The refactoring must prioritize extensibility without unnecessarily complicating the existing architecture. Avoid introducing abstractions that provide no practical benefit. Existing functionality should remain stable, and new fields or input types should be easy to register without modifying multiple unrelated parts of the codebase.

---

## 7. Risks & Rollback

### Risks

| Risk | Mitigation |
|------|------------|
| Changing `@onready` lookups to lazy resolution could reorder initialization vs. `_ready()`. | Keep core nodes as `@onready`; only peripheral UI inputs become lazy. |
| `unique_name_in_owner` lookups break if two nodes share a name. | Audit names during scene cleanup. |
| Extending `_capture_state()` / `_apply_state()` could break difficulty round-tripping. | Test difficulty save/load after each registry addition. |

### Rollback

- No files have been modified yet, so the current commit is the rollback point.
- If implemented, keep old `$path` / `%` lines as fallbacks behind a feature flag for one release.
