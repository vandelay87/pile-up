# PROTOTYPE (throwaway, branch prototype/flared-map): generates the flared v3 map variants
# from v2-narrow: scale it up, then widen every route the closer it gets to a spawn edge.
# Run: python3 tools/prototype_flared_maps.py  -> writes data/maps/proto-flare-*.json
# ':' is a prototype cell: clear ground you can't build on (the no-build margin).
import json, math

src = json.load(open("data/maps/v2-narrow.json"))
SW, SH = src["width"], src["height"]
W, H = 112, 76
EDGES = src["spawn_edges"]


def scaled():
    g = [[src["rows"][y * SH // H][x * SW // W] for x in range(W)] for y in range(H)]
    return g


def edge_distance(x, y):
    return min({"N": y, "S": H - 1 - y, "W": x, "E": W - 1 - x}[e] for e in EDGES)


def ragged(x, y):
    # Smooth, deterministic wobble in [-1, 1] so flared edges aren't clean curves.
    return (math.sin(x * 0.31 + y * 0.17) + math.sin(x * 0.11 - y * 0.37 + 1.3)) / 2


def route_distance(g, edge):
    """Walking distance from `edge` through clear ground, so a flare follows its own route
    instead of swelling everything near the edge."""
    edge_cells = {"N": [(x, 0) for x in range(W)], "S": [(x, H - 1) for x in range(W)],
                  "W": [(0, y) for y in range(H)], "E": [(W - 1, y) for y in range(H)]}[edge]
    dist = {c: 0 for c in edge_cells if g[c[1]][c[0]] == "."}
    queue = list(dist)
    for x, y in queue:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in dist and g[ny][nx] == ".":
                dist[(nx, ny)] = dist[(x, y)] + 1
                queue.append((nx, ny))
    return dist


def flare(g, mouth, length, per_edge=None, rag=0.0, along_route=False):
    """Dilate clear ground by a radius that is `mouth` at a spawn edge and 0 at `length` in.
    `per_edge` overrides (mouth, length) for single edges; `rag` roughens the radius."""
    shapes = {e: (per_edge or {}).get(e, (mouth, length)) for e in EDGES}
    out = [row[:] for row in g]
    dists = {e: route_distance(g, e) for e in EDGES} if along_route else None
    for y in range(H):
        for x in range(W):
            if g[y][x] != ".":
                continue
            r = 0.0
            for e, (m, ln) in shapes.items():
                if along_route:
                    d = dists[e].get((x, y), 999)
                else:
                    d = {"N": y, "S": H - 1 - y, "W": x, "E": W - 1 - x}[e]
                if d < ln:
                    r = max(r, m * (1 - d / ln) ** 2)
            if r <= 0:
                continue
            r *= 1 + rag * ragged(x, y)
            ri = int(r) + 1
            for yy in range(y - ri, y + ri + 1):
                for xx in range(x - ri, x + ri + 1):
                    if 0 <= xx < W and 0 <= yy < H and (xx - x) ** 2 + (yy - y) ** 2 <= r * r:
                        out[yy][xx] = "."
    return out


def bays(g, spots):
    # Spill room: pockets beside the chokepoints for an overflow to pour into.
    for cx, cy, rx, ry in spots:
        for y in range(H):
            for x in range(W):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                    g[y][x] = "."


def straight(g, fill, start, end, mouth, throat):
    """Replace a winding route with one straight funnel: rock over the `fill` rect
    (x0, y0, x1, y1), then carve from `start` on the edge to `end`, `mouth` to `throat`."""
    x0, y0, x1, y1 = fill
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = "#"
    (sx, sy), (ex, ey) = start, end
    length = math.hypot(ex - sx, ey - sy)
    for i in range(int(length * 2) + 1):
        t = i / (length * 2)
        cx, cy = sx + (ex - sx) * t, sy + (ey - sy) * t
        hw = throat + (mouth - throat) * (1 - t) ** 1.6
        hw *= 1 + 0.15 * ragged(cx, cy)
        for y in range(int(cy - hw) - 1, int(cy + hw) + 2):
            for x in range(int(cx - hw) - 1, int(cx + hw) + 2):
                if 0 <= x < W and 0 <= y < H and (x - cx) ** 2 + (y - cy) ** 2 <= hw * hw:
                    g[y][x] = "."


def prune(g):
    # Clear ground no route reaches (cut off by a straightening) goes back to rock.
    bx, by = base()
    seen, stack = {(bx, by)}, [(bx, by)]
    while stack:
        x, y = stack.pop()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and g[ny][nx] != "#":
                seen.add((nx, ny))
                stack.append((nx, ny))
    for y in range(H):
        for x in range(W):
            if g[y][x] != "#" and (x, y) not in seen:
                g[y][x] = "#"


def margin(g, depth):
    for y in range(H):
        for x in range(W):
            if g[y][x] == "." and edge_distance(x, y) < depth:
                g[y][x] = ":"


def base():
    bx, by = src["base"]["origin"]
    return [bx * W // SW, by * H // SH]


# Chokepoints of the scaled v2 layout, found by eye from the preview.
BAYS = [(42, 44, 4, 3), (70, 44, 4, 3), (36, 18, 3, 3), (78, 18, 3, 3)]


# The straight funnels: rock over the old winding route, then a funnel to the junction.
STRAIGHT_E = ((89, 0, W - 1, 36), (W - 1, 22), (86, 31), 17, 4.5)
STRAIGHT_W = ((0, 0, 24, 36), (0, 31), (27, 31), 15, 4.5)


def cut(g, start, end, half_width):
    # A narrow channel through rock; cutting across a spine leaves the rest as an island.
    (sx, sy), (ex, ey) = start, end
    length = math.hypot(ex - sx, ey - sy)
    for i in range(int(length * 2) + 1):
        t = i / (length * 2)
        cx, cy = sx + (ex - sx) * t, sy + (ey - sy) * t
        for y in range(int(cy - half_width) - 1, int(cy + half_width) + 2):
            for x in range(int(cx - half_width) - 1, int(cx + half_width) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= half_width ** 2:
                    g[y][x] = "."


# Across the rock spine between the north and east routes, about 4 cells wide.
NE_CUT = ((70, 11), (92, 16), 2.2)


def variant(mouth, length, margin_depth=0, with_bays=False, per_edge=None, rag=0.0,
            straights=(), cuts=()):
    g = scaled()
    per_edge = dict(per_edge or {})
    for fill, start, end, m, t in straights:
        straight(g, fill, start, end, m, t)
        per_edge["E" if start[0] > 0 else "W"] = (0, 1)
    # A-C flare by distance from the edge; D-G (any rag) follow each route instead.
    g = flare(g, mouth, length, per_edge, rag, along_route=rag > 0)
    if with_bays:
        bays(g, BAYS)
    for start, end, half_width in cuts:
        cut(g, start, end, half_width)
    prune(g)
    if margin_depth:
        margin(g, margin_depth)
    return g


VARIANTS = {
    # A: v2 a sixth bigger, mouths roughly doubled, tapering back to v2's widths 18 cells in.
    "a-flare": variant(mouth=7, length=18),
    # B: A plus a no-build margin 6 deep along every spawn edge.
    "b-flare-margin": variant(mouth=7, length=18, margin_depth=6),
    # C: a stronger, longer flare, the same margin, and spill bays beside the chokepoints.
    "c-wide-bays": variant(mouth=9, length=22, margin_depth=6, with_bays=True),
    # D-G build on C: a wider, longer, ragged flare, each with its own twist.
    # D: the east route is one straight, slightly diagonal funnel; no turn.
    "d-straight-east": variant(mouth=12, length=30, margin_depth=6, with_bays=True, rag=0.3,
                               straights=[STRAIGHT_E]),
    # E: the west route is the straight one instead.
    "e-straight-west": variant(mouth=12, length=30, margin_depth=6, with_bays=True, rag=0.3,
                               straights=[STRAIGHT_W]),
    # H: E plus a channel cut between the north and east routes, leaving a rock island.
    "h-west-island": variant(mouth=12, length=30, margin_depth=6, with_bays=True, rag=0.3,
                             straights=[STRAIGHT_W], cuts=[NE_CUT]),
    # F: both side routes straight: a trident, north the only one that winds into the loop.
    "f-trident": variant(mouth=12, length=30, margin_depth=6, with_bays=True, rag=0.3,
                         straights=[STRAIGHT_E, STRAIGHT_W]),
    # G: no straightening, but every edge flares differently: north huge, west tight, east ragged.
    "g-lopsided": variant(mouth=12, length=30, margin_depth=6, with_bays=True, rag=0.25,
                          per_edge={"N": (16, 36), "W": (6, 16), "E": (12, 28)}),
}

for name, g in VARIANTS.items():
    rows = ["".join(r) for r in g]
    data = {"version": 1, "width": W, "height": H,
            "base": {"origin": base(), "size": [4, 4]},
            "spawn_edges": EDGES, "rows": rows}
    path = "data/maps/proto-flare-%s.json" % name
    with open(path, "w") as f:
        json.dump(data, f, indent="\t")
        f.write("\n")
    clear = sum(r.count(".") + r.count(":") for r in rows)
    print("%s: %d clear cells, %d no-build, base %s" % (path, clear, sum(r.count(":") for r in rows), base()))
