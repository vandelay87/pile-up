# PROTOTYPE (throwaway, branch prototype/flared-map): generates the flared v3 map variants
# from v2-narrow: scale it up, then widen every route the closer it gets to a spawn edge.
# Run: python3 tools/prototype_flared_maps.py  -> writes data/maps/proto-flare-*.json
# ':' is a prototype cell: clear ground you can't build on (the no-build margin).
import json

src = json.load(open("data/maps/v2-narrow.json"))
SW, SH = src["width"], src["height"]
W, H = 112, 76
EDGES = src["spawn_edges"]


def scaled():
    g = [[src["rows"][y * SH // H][x * SW // W] for x in range(W)] for y in range(H)]
    return g


def edge_distance(x, y):
    return min({"N": y, "S": H - 1 - y, "W": x, "E": W - 1 - x}[e] for e in EDGES)


def flare(g, mouth, length):
    """Dilate clear ground by a radius that is `mouth` at a spawn edge and 0 at `length` in."""
    out = [row[:] for row in g]
    for y in range(H):
        for x in range(W):
            if g[y][x] != ".":
                continue
            d = edge_distance(x, y)
            if d >= length:
                continue
            r = mouth * (1 - d / length) ** 2
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


def variant(mouth, length, margin_depth=0, with_bays=False):
    g = flare(scaled(), mouth, length)
    if with_bays:
        bays(g, BAYS)
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
