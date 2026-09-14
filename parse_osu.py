#!/usr/bin/env python3

# Parse osu file and generate enso chart

with open('/home/sentimers/Games/enso-1.1/dev/references/kessoku band - Doppelganger (TasseDeThe) [Aruy\'s hard].osu', 'r') as f:
    content = f.read()

hit_objects = []
in_hit_objects = False
for line in content.split('\n'):
    if line.strip() == '[HitObjects]':
        in_hit_objects = True
        continue
    if in_hit_objects and line.strip() and not line.strip().startswith('//'):
        parts = line.strip().split(',')
        x = int(parts[0])
        y = int(parts[1])
        time = int(parts[2])
        obj_type = int(parts[3])
        hit_objects.append((time, x, y, obj_type))

hit_objects.sort(key=lambda x: x[0])
print(f"Total hit objects: {len(hit_objects)}")
print(f"Time range: {hit_objects[0][0]} - {hit_objects[-1][0]}ms")

# Group notes into shapes based on time proximity
# Notes within 150ms of each other are in the same shape
groups = []
current_group = [hit_objects[0]]

for i in range(1, len(hit_objects)):
    time_diff = hit_objects[i][0] - current_group[-1][0]
    if time_diff <= 150:
        current_group.append(hit_objects[i])
    else:
        groups.append(current_group)
        current_group = [hit_objects[i]]

groups.append(current_group)
print(f"Number of shape groups: {len(groups)}")

# Analyze group sizes
size_counts = {}
for g in groups:
    s = len(g)
    size_counts[s] = size_counts.get(s, 0) + 1
print("Group size distribution:", dict(sorted(size_counts.items())))

# Generate enso chart
lines = []
lines.append("""#
# SECTIONS
#   [metadata]  level-wide settings (name, scroll speed, song file)
#   [notes]     the actual chart data
#
# SHAPES
#   [(name)]   closed shape   -> the end point joins back to the start point
#                                (a loop, like a square or circle)
#   [[name]]   open shape     -> does NOT close itself; can be straight lines
#                                such as an L or U. Mark the final point with "!"
#   The text inside the brackets is the object id (must be unique).
#
# POINT TYPES
#   @  note point     -> "@ <time> <x> <y>"     has a timestamp (ms) and trigger
#                                                when that moment in the song hits
#   !  geometry point -> "! <x> <y>"           no timestamp; only used to shape the
#                                                outline of an open shape correctly
#
# COORDINATES
#   x, y may be integers or fractions; the engine converts them to floats either way
#   (0, 0) = top-left of the playfield
#   (1, 1) = bottom-right of the playfield
# ============================================================

[metadata]
name = "Doppleganger"          # level title shown to the player
song = ./doppleganger.mp3       # audio file, relative to this chart
color_scheme = ["#EEB8C4", "#E6D47B", "#D0574E", "#4061A0"]
preview_start = 121451
bpm = 189
beat0 = 417
[notes]

# ms     x  y
""")

shape_idx = 0

for group in groups:
    if len(group) == 1:
        # Single note -> closed shape (dot)
        time, x, y, _ = group[0]
        x_norm = x / 512.0
        y_norm = y / 384.0
        lines.append(f"[(s_{shape_idx})]")
        lines.append(f"@ {time} {x_norm:.3f} {y_norm:.3f}")
        lines.append("")
        shape_idx += 1
    elif len(group) == 2:
        # Two notes -> open shape (line)
        t1, x1, y1, _ = group[0]
        t2, x2, y2, _ = group[1]
        x1_norm = x1 / 512.0
        y1_norm = y1 / 384.0
        x2_norm = x2 / 512.0
        y2_norm = y2 / 384.0
        lines.append(f"[[\ng_{shape_idx}]]")
        lines.append(f"@ {t1} {x1_norm:.3f} {y1_norm:.3f}")
        lines.append(f"@ {t2} {x2_norm:.3f} {y2_norm:.3f}")
        lines.append("! 1 1")
        lines.append("")
        shape_idx += 1
    elif len(group) == 3:
        # Three notes -> closed shape (triangle-like)
        lines.append(f"[(g_{shape_idx})]")
        for time, x, y, _ in group:
            x_norm = x / 512.0
            y_norm = y / 384.0
            lines.append(f"@ {time} {x_norm:.3f} {y_norm:.3f}")
        lines.append("")
        shape_idx += 1
    else:
        # Four or more notes -> closed shape, use up to 6 points
        lines.append(f"[(g_{shape_idx})]")
        for time, x, y, _ in group[:6]:
            x_norm = x / 512.0
            y_norm = y / 384.0
            lines.append(f"@ {time} {x_norm:.3f} {y_norm:.3f}")
        lines.append("")
        shape_idx += 1

with open('/home/sentimers/Games/enso-1.1/levels/doppleganger/chart.enso', 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"Written chart with {shape_idx} shapes to chart.enso")