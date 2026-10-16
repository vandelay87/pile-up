#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {

// Enemies' merged separation and personal-space scan (Enemies._neighbour_pushes), for every
// moving enemy in one call. It reads Enemies' packed arrays and spatial hash, and mirrors the
// GDScript's arithmetic: Vector2 maths in single precision, scalars in double.
class NeighbourScan : public RefCounted {
	GDCLASS(NeighbourScan, RefCounted)

public:
	// Fills the separations and space pushes for enemies [0, count) that are alive and not
	// tumbling; the rest get zero. spaces is false when personal space is off this tick.
	void scan(int p_count, const PackedVector2Array &p_positions, const PackedFloat32Array &p_hp,
			const PackedByteArray &p_tumbling, const PackedByteArray &p_attacking,
			const PackedInt32Array &p_ids, const PackedInt32Array &p_bucket_starts,
			const PackedInt32Array &p_bucket_enemies, int p_width, int p_height,
			double p_radius, double p_push, int p_cap, bool p_spreads, double p_space_radius,
			double p_space_push);
	PackedVector2Array get_separations() const { return separations; }
	PackedVector2Array get_space_pushes() const { return space_pushes; }

protected:
	static void _bind_methods();

private:
	PackedVector2Array separations;
	PackedVector2Array space_pushes;
};

} // namespace godot
