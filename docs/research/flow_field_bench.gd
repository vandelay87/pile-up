## Headless micro-benchmark for issue #3.
## Run: Godot --headless --script docs/research/flow_field_bench.gd
extends SceneTree

const INF := 0x3FFFFFFF
const IMPASSABLE := 0  # cost 0 marks a blocked cell (border padding, tower)
const KEY_SHIFT := 24
const KEY_MASK := (1 << KEY_SHIFT) - 1
const RUNS := 7

var w: int  # padded width
var h: int
var offs: PackedInt32Array
var step: PackedInt32Array  # 10 orthogonal, 14 diagonal
var cost: PackedInt32Array
var dist: PackedInt32Array
var dir: PackedByteArray
var goal: int


func _init() -> void:
	for size in [100, 200, 300]:
		_bench(size)
	quit()


func _setup(size: int, seed_value: int) -> void:
	w = size + 2
	h = size + 2
	# order: E, W, S, N, SE, SW, NE, NW
	offs = PackedInt32Array([1, -1, w, -w, w + 1, w - 1, -w + 1, -w - 1])
	step = PackedInt32Array([10, 10, 10, 10, 14, 14, 14, 14])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sensible_costs := PackedInt32Array([1, 12, 14, 18, 25])  # x10 units: clear, L1..L4
	cost = PackedInt32Array()
	cost.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				cost[i] = IMPASSABLE
				continue
			var r := rng.randf()
			if r < 0.02:
				cost[i] = IMPASSABLE  # tower cell
			elif r < 0.04:
				cost[i] = 46  # wall: ~30 s to break at 1.5 cells/s, x10 units / 10
			elif r < 0.14:
				cost[i] = sensible_costs[rng.randi_range(1, 4)]
			else:
				cost[i] = 1
	goal = (h / 2) * w + w / 2
	cost[goal] = 1


## Baseline: 4-neighbour BFS on uniform costs (lower bound for any field).
func bfs_uniform() -> void:
	var c := cost
	var n := w * h
	var d := PackedInt32Array()
	d.resize(n)
	d.fill(INF)
	var q := PackedInt32Array()
	q.resize(n)
	var head := 0
	var tail := 0
	d[goal] = 0
	q[tail] = goal
	tail += 1
	while head < tail:
		var u := q[head]
		head += 1
		var nd := d[u] + 1
		for k in 4:
			var v := u + offs[k]
			if c[v] != IMPASSABLE and d[v] == INF:
				d[v] = nd
				q[tail] = v
				tail += 1
	dist = d


## Integration field: 8-neighbour Dijkstra with a binary heap of packed (dist, index) keys.
func dijkstra_full() -> void:
	var c := cost
	var o := offs
	var s := step
	var n := w * h
	var d := PackedInt32Array()
	d.resize(n)
	d.fill(INF)
	var heap := PackedInt64Array()
	heap.resize(n * 8 + 1)
	var hs := 0
	d[goal] = 0
	heap[0] = goal
	hs = 1
	while hs > 0:
		# pop min
		var top := heap[0]
		hs -= 1
		var last := heap[hs]
		var i := 0
		while true:
			var l := 2 * i + 1
			if l >= hs:
				break
			var r := l + 1
			if r < hs and heap[r] < heap[l]:
				l = r
			if heap[l] >= last:
				break
			heap[i] = heap[l]
			i = l
		heap[i] = last
		var du := top >> KEY_SHIFT
		var u := top & KEY_MASK
		if du > d[u]:
			continue
		for k in 8:
			var v := u + o[k]
			var cv := c[v]
			if cv == IMPASSABLE:
				continue
			if k >= 4:
				var dx := 1 if (k == 4 or k == 6) else -1
				if c[u + dx] == IMPASSABLE or c[v - dx] == IMPASSABLE:
					continue
			var nd := du + cv * s[k]
			if nd < d[v]:
				d[v] = nd
				# push
				var key := (nd << KEY_SHIFT) | v
				var j := hs
				hs += 1
				while j > 0:
					var p := (j - 1) >> 1
					if heap[p] <= key:
						break
					heap[j] = heap[p]
					j = p
				heap[j] = key
	dist = d


## Direction field: index (0..7) of the shortest-path predecessor (min d[v] + step cost), 255 = none.
func direction_full() -> void:
	var c := cost
	var d := dist
	var o := offs
	var s := step
	var n := w * h
	var out := PackedByteArray()
	out.resize(n)
	out.fill(255)
	for y in range(1, h - 1):
		var row := y * w
		for x in range(1, w - 1):
			var u := row + x
			if c[u] == IMPASSABLE or u == goal:
				continue
			var best := INF
			var bk := 255
			for k in 8:
				var v := u + o[k]
				if c[v] == IMPASSABLE:
					continue
				if k >= 4:
					var dx := 1 if (k == 4 or k == 6) else -1
					if c[u + dx] == IMPASSABLE or c[v - dx] == IMPASSABLE:
						continue
				if d[v] + c[u] * s[k] < best:
					best = d[v] + c[u] * s[k]
					bk = k
			out[u] = bk
	dir = out


## Exact incremental repair after one cell's cost changes (Ramalingam-Reps style):
## invalidate the subtree of the shortest-path tree that routes through `cell`,
## re-seed it from its valid boundary, rerun Dijkstra over it only.
## Returns the number of cells touched.
func incremental_update(cell: int, new_cost: int) -> int:
	var c := cost
	var d := dist
	var dr := dir
	var o := offs
	var s := step
	var old_cost := c[cell]
	c[cell] = new_cost
	var affected := PackedInt32Array()
	var mark: Dictionary[int, bool] = {}
	if new_cost > old_cost or new_cost == IMPASSABLE:
		# 1. collect subtree: cells whose direction points into an affected cell
		affected.append(cell)
		mark[cell] = true
		var head := 0
		while head < affected.size():
			var u := affected[head]
			head += 1
			for k in 8:
				var v := u + o[k]
				if mark.has(v) or c[v] == IMPASSABLE or dr[v] == 255:
					continue
				if v + o[dr[v]] == u:
					mark[v] = true
					affected.append(v)
		for u in affected:
			d[u] = INF
	else:
		affected.append(cell)
		mark[cell] = true
	# 2. seed affected cells from their non-affected neighbours
	var heap := PackedInt64Array()
	heap.resize(maxi(64, affected.size() * 8 + 8))
	var hs := 0
	for u in affected:
		if c[u] == IMPASSABLE:
			continue
		var best := d[u]
		for k in 8:
			var v := u + o[k]
			if c[v] == IMPASSABLE or d[v] == INF:
				continue
			if k >= 4:
				var dx := 1 if (k == 4 or k == 6) else -1
				if c[u + dx] == IMPASSABLE or c[v - dx] == IMPASSABLE:
					continue
			var nd := d[v] + c[u] * s[k]
			if nd < best:
				best = nd
		if best < d[u]:
			d[u] = best
			var key := (best << KEY_SHIFT) | u
			var j := hs
			hs += 1
			while j > 0:
				var p := (j - 1) >> 1
				if heap[p] <= key:
					break
				heap[j] = heap[p]
				j = p
			heap[j] = key
	# 3. Dijkstra restricted by improvement (it only ever lowers values)
	var changed := affected.duplicate()
	while hs > 0:
		var top := heap[0]
		hs -= 1
		var last := heap[hs]
		var i := 0
		while true:
			var l := 2 * i + 1
			if l >= hs:
				break
			var r := l + 1
			if r < hs and heap[r] < heap[l]:
				l = r
			if heap[l] >= last:
				break
			heap[i] = heap[l]
			i = l
		heap[i] = last
		var du := top >> KEY_SHIFT
		var u := top & KEY_MASK
		if du > d[u]:
			continue
		for k in 8:
			var v := u + o[k]
			var cv := c[v]
			if cv == IMPASSABLE:
				continue
			if k >= 4:
				var dx := 1 if (k == 4 or k == 6) else -1
				if c[u + dx] == IMPASSABLE or c[v - dx] == IMPASSABLE:
					continue
			var nd := du + cv * s[k]
			if nd < d[v]:
				d[v] = nd
				changed.append(v)
				if hs >= heap.size():
					heap.resize(heap.size() * 2)
				var key := (nd << KEY_SHIFT) | v
				var j := hs
				hs += 1
				while j > 0:
					var p := (j - 1) >> 1
					if heap[p] <= key:
						break
					heap[j] = heap[p]
					j = p
				heap[j] = key
	# 4. refresh directions of changed cells and their neighbours
	var redo: Dictionary[int, bool] = {}
	for u in changed:
		redo[u] = true
		for k in 8:
			redo[u + o[k]] = true
	for u: int in redo:
		if c[u] == IMPASSABLE or u == goal:
			continue
		var best := INF
		var bk := 255
		for k in 8:
			var v := u + o[k]
			if c[v] == IMPASSABLE:
				continue
			if k >= 4:
				var dx := 1 if (k == 4 or k == 6) else -1
				if c[u + dx] == IMPASSABLE or c[v - dx] == IMPASSABLE:
					continue
			if d[v] + c[u] * s[k] < best:
				best = d[v] + c[u] * s[k]
				bk = k
		dr[u] = bk
	cost = c
	dist = d
	dir = dr
	return redo.size()


func _median(xs: Array) -> float:
	xs.sort()
	return xs[xs.size() / 2]


func _time_ms(fn: Callable) -> float:
	var t := []
	for i in RUNS:
		var t0 := Time.get_ticks_usec()
		fn.call()
		t.append((Time.get_ticks_usec() - t0) / 1000.0)
	return _median(t)


func _bench(size: int) -> void:
	_setup(size, 42)
	var bfs_ms := _time_ms(bfs_uniform)
	var dij_ms := _time_ms(dijkstra_full)
	var dir_ms := _time_ms(direction_full)
	print("%dx%d  bfs4 %.1f ms | dijkstra8 %.1f ms | direction %.1f ms | full field %.1f ms" % [
		size, size, bfs_ms, dij_ms, dir_ms, dij_ms + dir_ms])

	# two fields in parallel on WorkerThreadPool vs sequential on main thread
	var seq := []
	var par := []
	for r in RUNS:
		var t0 := Time.get_ticks_usec()
		var a := FieldJob.new(cost, w, h, goal)
		var b := FieldJob.new(cost, w, h, goal)
		a.run()
		b.run()
		seq.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		a = FieldJob.new(cost, w, h, goal)
		b = FieldJob.new(cost, w, h, goal)
		var ta := WorkerThreadPool.add_task(a.run)
		var tb := WorkerThreadPool.add_task(b.run)
		WorkerThreadPool.wait_for_task_completion(ta)
		WorkerThreadPool.wait_for_task_completion(tb)
		par.append((Time.get_ticks_usec() - t0) / 1000.0)
	print("        two fields: sequential %.1f ms | 2 WorkerThreadPool tasks %.1f ms (wall clock)" % [
		_median(seq), _median(par)])

	# incremental repair: 200 random pile changes applied in sequence, then checked
	# against a full recompute. Raise = a body lands (pile goes up a level),
	# lower = end-of-wave decay or a wall broken.
	var up := {1: 12, 12: 14, 14: 18, 18: 25, 25: 46}
	var down := {12: 1, 14: 12, 18: 14, 25: 18, 46: 25}
	dijkstra_full()
	direction_full()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for phase in ["raise", "lower"]:
		var table: Dictionary = up if phase == "raise" else down
		var times := []
		var max_cells := 0
		var done := 0
		while done < 200:
			var cell := rng.randi_range(1, h - 2) * w + rng.randi_range(1, w - 2)
			if cell == goal or not table.has(cost[cell]):
				continue
			var t0 := Time.get_ticks_usec()
			var touched := incremental_update(cell, table[cost[cell]])
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			max_cells = maxi(max_cells, touched)
			done += 1
		var inc_d := dist.duplicate()
		var inc_dir := dir.duplicate()
		dijkstra_full()
		direction_full()
		times.sort()
		var total := 0.0
		for t: float in times:
			total += t
		print("        incremental %s x200: median %.2f ms | p95 %.2f ms | max %.2f ms (%d cells) | mean %.2f ms | exact=%s" % [
			phase, times[100], times[190], times[199], max_cells, total / 200.0,
			inc_d == dist and inc_dir == dir])


class FieldJob:
	var cost: PackedInt32Array
	var w: int
	var h: int
	var goal: int
	var dist: PackedInt32Array

	func _init(c: PackedInt32Array, width: int, height: int, g: int) -> void:
		cost = c
		w = width
		h = height
		goal = g

	func run() -> void:
		var c := cost
		var o := PackedInt32Array([1, -1, w, -w, w + 1, w - 1, -w + 1, -w - 1])
		var s := PackedInt32Array([10, 10, 10, 10, 14, 14, 14, 14])
		var n := w * h
		var d := PackedInt32Array()
		d.resize(n)
		d.fill(INF)
		var heap := PackedInt64Array()
		heap.resize(n * 8 + 1)
		var hs := 1
		d[goal] = 0
		heap[0] = goal
		while hs > 0:
			var top := heap[0]
			hs -= 1
			var last := heap[hs]
			var i := 0
			while true:
				var l := 2 * i + 1
				if l >= hs:
					break
				var r := l + 1
				if r < hs and heap[r] < heap[l]:
					l = r
				if heap[l] >= last:
					break
				heap[i] = heap[l]
				i = l
			heap[i] = last
			var du := top >> KEY_SHIFT
			var u := top & KEY_MASK
			if du > d[u]:
				continue
			for k in 8:
				var v := u + o[k]
				var cv := c[v]
				if cv == IMPASSABLE:
					continue
				if k >= 4:
					var dx := 1 if (k == 4 or k == 6) else -1
					if c[u + dx] == IMPASSABLE or c[v - dx] == IMPASSABLE:
						continue
				var nd := du + cv * s[k]
				if nd < d[v]:
					d[v] = nd
					var key := (nd << KEY_SHIFT) | v
					var j := hs
					hs += 1
					while j > 0:
						var p := (j - 1) >> 1
						if heap[p] <= key:
							break
						heap[j] = heap[p]
						j = p
					heap[j] = key
		dist = d
