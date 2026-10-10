"""PROTOTYPE: generates data/maps/v2-narrow.json for The narrow map (#54)."""
import json, math, sys

W, H = 96, 60
BASE = (55, 47)  # origin of the 4x4 base
grid = [["#"] * W for _ in range(H)]


def disc(cx, cy, r):
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            if 0 <= x < W and 0 <= y < H and (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                grid[y][x] = "."


def path(points, r0, r1=None):
    """Carve a thick polyline, radius easing from r0 to r1 along it."""
    r1 = r0 if r1 is None else r1
    total = sum(math.dist(a, b) for a, b in zip(points, points[1:]))
    done = 0.0
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        steps = max(1, int(seg * 2))
        for i in range(steps + 1):
            t = i / steps
            x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            f = (done + seg * t) / total
            disc(x, y, r0 + (r1 - r0) * f)
        done += seg


R = 3.5  # 7-cell corridors
# A small clearing around the base; the defence belongs in the chokepoints.
for y in range(42, 56):
    for x in range(50, 64):
        grid[y][x] = "."
# Flared mouths, easing into the corridors.
path([(0, 8), (10, 8)], 6.5, R)
path([(40, 0), (40, 7)], 6.5, R)
path([(95, 18), (85, 18)], 6.5, R)
# West: the long way round, then along the bottom into the clearing.
path([(10, 8), (18, 8), (18, 22), (10, 30), (10, 44), (50, 44)], R)
# East: short and direct, down into the clearing from above.
path([(85, 18), (72, 22), (60, 22), (60, 42)], R)
# North splits unevenly: a long branch to the west junction, a short one east.
path([(40, 7), (40, 10), (30, 14), (30, 44)], R)
path([(40, 10), (52, 10), (60, 22)], R)

rows = ["".join(r) for r in grid]
for y in range(BASE[1], BASE[1] + 4):
    assert rows[y][BASE[0]:BASE[0] + 4] == "....", "base on rock"
out = {
    "version": 1,
    "width": W,
    "height": H,
    "base": {"origin": list(BASE), "size": [4, 4]},
    "spawn_edges": ["N", "E", "W"],
    "rows": rows,
}
text = json.dumps(out, indent="\t")
# One row per line, matching v1.json's layout.
text = text.replace('"base": {\n\t\t"origin": [\n\t\t\t55,\n\t\t\t47\n\t\t],\n\t\t"size": [\n\t\t\t4,\n\t\t\t4\n\t\t]\n\t}', '"base": {"origin": [55, 47], "size": [4, 4]}')
text = text.replace('"spawn_edges": [\n\t\t"N",\n\t\t"E",\n\t\t"W"\n\t]', '"spawn_edges": ["N", "E", "W"]')
with open(sys.argv[1], "w") as f:
    f.write(text + "\n")
print("\n".join(rows))
