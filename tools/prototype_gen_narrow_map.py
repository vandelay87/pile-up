"""PROTOTYPE: generates data/maps/v2-narrow.json for The narrow map (#54)."""
import json, math, random, sys

W, H = 96, 64
BASE = (46, 46)  # origin of the 4x4 base
rng = random.Random(54)  # fixed seed: the same map every run
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
            disc(x, y, r0 + (r1 - r0) * f + rng.uniform(-0.3, 0.3))
        done += seg


# The first, even layout, nudged a cell or two and roughened so it looks
# less clear cut. Corridors are about 7 cells wide.
# A clearing around the base, a little uneven and slightly off-centre.
for y in range(39, 58):
    for x in range(38, 58):
        grid[y][x] = "."
for cx, cy, r in [(38, 39, 2.5), (57, 40, 3), (37, 52, 2), (58, 55, 2.5)]:
    disc(cx, cy, r)
# Flared mouths, easing into the corridors.
path([(0, 10), (10, 10)], 6.5, 3.5)
path([(95, 11), (85, 11)], 6.3, 3.5)
path([(47, 0), (48, 8)], 6.6, 3.5)
# West and east routes: S-bends down to a junction, then into the clearing.
path([(10, 10), (17, 10), (16, 26), (39, 27), (41, 39)], 3.5, 3.7)
path([(85, 11), (78, 11), (79, 25), (57, 26), (55, 39)], 3.4, 3.6)
# North route splits around a rock island and joins each side route.
path([(48, 8), (48, 12), (33, 12), (32, 27)], 3.6, 3.3)
path([(48, 12), (63, 13), (63, 25)], 3.4, 3.7)



def rock_neighbours(x, y):
    return sum(
        1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
        if not (0 <= x + dx < W and 0 <= y + dy < H) or grid[y + dy][x + dx] == "#"
    )


# Smooth away lone nubs and pockets the roughening leaves behind.
for _ in range(2):
    for y in range(H):
        for x in range(W):
            n = rock_neighbours(x, y)
            if grid[y][x] == "#" and n <= 1:
                grid[y][x] = "."
            elif grid[y][x] == "." and n >= 3 and 0 < x < W - 1 and 0 < y < H - 1:
                grid[y][x] = "#"

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
text = text.replace('"base": {\n\t\t"origin": [\n\t\t\t46,\n\t\t\t46\n\t\t],\n\t\t"size": [\n\t\t\t4,\n\t\t\t4\n\t\t]\n\t}', '"base": {"origin": [46, 46], "size": [4, 4]}')
text = text.replace('"spawn_edges": [\n\t\t"N",\n\t\t"E",\n\t\t"W"\n\t]', '"spawn_edges": ["N", "E", "W"]')
with open(sys.argv[1], "w") as f:
    f.write(text + "\n")
print("\n".join(rows))
