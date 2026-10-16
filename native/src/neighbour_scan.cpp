#include "neighbour_scan.h"

#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace {

Vector2 separation_total(const Vector2 &p_from_peers, int p_peers, const Vector2 &p_from_attackers) {
	return p_from_peers / real_t(p_peers > 1 ? p_peers : 1) + p_from_attackers;
}

} // namespace

void NeighbourScan::scan(int p_count, const PackedVector2Array &p_positions,
		const PackedFloat32Array &p_hp, const PackedByteArray &p_tumbling,
		const PackedByteArray &p_attacking, const PackedInt32Array &p_ids,
		const PackedInt32Array &p_bucket_starts, const PackedInt32Array &p_bucket_enemies,
		int p_width, int p_height, double p_radius, double p_push, int p_cap, bool p_spreads,
		double p_space_radius, double p_space_push) {
	separations.resize(p_count);
	space_pushes.resize(p_count);
	Vector2 *out_separations = separations.ptrw();
	Vector2 *out_space = space_pushes.ptrw();
	const Vector2 *positions = p_positions.ptr();
	const float *hp = p_hp.ptr();
	const uint8_t *tumbling = p_tumbling.ptr();
	const uint8_t *attacking_flags = p_attacking.ptr();
	const int32_t *ids = p_ids.ptr();
	const int32_t *bucket_starts = p_bucket_starts.ptr();
	const int32_t *bucket_enemies = p_bucket_enemies.ptr();

	const double spacing = 2.0 * p_radius;
	const double spacing_squared = spacing * spacing;
	const double space_squared = p_space_radius * p_space_radius;

	for (int i = 0; i < p_count; i++) {
		out_separations[i] = Vector2();
		out_space[i] = Vector2();
		if (hp[i] <= 0.0f || tumbling[i] == 1) {
			continue;
		}
		const bool attacking = attacking_flags[i] == 1;
		const bool spaces = p_spreads && !attacking;
		const int reach = spaces ? int(std::ceil(p_space_radius)) : 1;
		const Vector2 pos = positions[i];
		const Vector2i cell = Vector2i(pos.floor());
		bool separating = true;
		bool capped_out = false;
		int checked = 0;
		Vector2 from_peers;
		int peers = 0;
		Vector2 from_attackers;
		Vector2 from_space;
		const int y_end = cell.y + reach + 1 < p_height ? cell.y + reach + 1 : p_height;
		const int x_end = cell.x + reach + 1 < p_width ? cell.x + reach + 1 : p_width;
		for (int y = cell.y - reach > 0 ? cell.y - reach : 0; y < y_end && !capped_out; y++) {
			const bool near_row = std::abs(y - cell.y) <= 1;
			for (int x = cell.x - reach > 0 ? cell.x - reach : 0; x < x_end && !capped_out; x++) {
				const bool near = near_row && std::abs(x - cell.x) <= 1;
				const int bucket = y * p_width + x;
				for (int slot = bucket_starts[bucket]; slot < bucket_starts[bucket + 1]; slot++) {
					const int j = bucket_enemies[slot];
					if (j == i || tumbling[j] == 1) {
						continue;
					}
					const Vector2 away = pos - positions[j];
					const double distance_squared = away.length_squared();
					const bool other_attacking = attacking_flags[j] == 1;
					bool separates = false;
					if (near && separating) {
						if (p_cap > 0 && checked == p_cap) {
							separating = false;
							if (!spaces) {
								capped_out = true;
								break;
							}
						} else {
							checked += 1;
							separates = distance_squared < spacing_squared &&
									(other_attacking || !attacking);
						}
					}
					const bool keeps_space =
							spaces && !other_attacking && distance_squared < space_squared;
					if (!separates && !keeps_space) {
						continue;
					}
					const double distance = away.length();
					Vector2 direction;
					if (distance > 1e-6) {
						direction = away / real_t(distance);
					} else {
						direction = ids[i] > ids[j] ? Vector2(1, 0) : Vector2(-1, 0);
					}
					if (separates) {
						const Vector2 shove = direction * real_t(spacing - distance) * real_t(p_push);
						if (other_attacking && !attacking) {
							from_attackers += shove * real_t(2.0);
						} else {
							from_peers += shove;
							peers += 1;
						}
					}
					if (keeps_space) {
						from_space += direction * real_t(1.0 - distance / p_space_radius) *
								real_t(p_space_push);
					}
				}
			}
		}
		out_separations[i] = separation_total(from_peers, peers, from_attackers);
		// A capped-out scan without personal space returns before it records any.
		out_space[i] = capped_out ? Vector2() : from_space;
	}
}

void NeighbourScan::_bind_methods() {
	ClassDB::bind_method(D_METHOD("scan", "count", "positions", "hp", "tumbling", "attacking", "ids",
								 "bucket_starts", "bucket_enemies", "width", "height", "radius",
								 "push", "cap", "spreads", "space_radius", "space_push"),
			&NeighbourScan::scan);
	ClassDB::bind_method(D_METHOD("get_separations"), &NeighbourScan::get_separations);
	ClassDB::bind_method(D_METHOD("get_space_pushes"), &NeighbourScan::get_space_pushes);
}
