// C ABI of the Rust client core (client/core/src/ffi.rs).
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Vertex layout shared by every mesh. Units are metres, Y is up, models face +X.
typedef struct BsVertex {
    float position[3];
    float normal[3];
    float uv[2];
    float material; // material index 0..15 of the 4x4 material sheet
} BsVertex;

// Rigid model identifiers (mesh::Model).
typedef enum BsModel {
    BS_MODEL_CUBE = 0,
    BS_MODEL_SOLDIER = 1,
    BS_MODEL_LEG = 2,
    BS_MODEL_DRONE = 3,
    BS_MODEL_TURRET_BASE = 4,
    BS_MODEL_TURRET_HEAD = 5,
    BS_MODEL_REACTOR = 6,
    BS_MODEL_CARBINE = 7,
    BS_MODEL_CRATE = 8,
    BS_MODEL_PIPE = 9,
    BS_MODEL_BARREL = 10,
    BS_MODEL_VENT = 11,
    BS_MODEL_CABINET = 12,
    BS_MODEL_PALLET = 13,
    BS_MODEL_CONSOLE = 14,
    BS_MODEL_GENERATOR = 15,
    BS_MODEL_TANK = 16,
    BS_MODEL_PUMP = 17,
    BS_MODEL_CABLE_SPOOL = 18,
    BS_MODEL_BOLLARD = 19,
    BS_MODEL_LAMP = 20,
    BS_MODEL_BARRICADE = 21,
    BS_MODEL_FAN = 22,
    BS_MODEL_SHOTGUN = 23,
    BS_MODEL_SMG = 24,
    BS_MODEL_WARDEN_GEAR = 25,
    BS_MODEL_RANGER_GEAR = 26,
    BS_MODEL_COUNT = 27
} BsModel;

enum { BS_MATERIAL_COUNT = 16 };

// Rigid models. Functions return 0 for unknown models or short buffers.
int32_t bs_mesh_vertex_count(int32_t model);
int32_t bs_mesh_vertices(int32_t model, BsVertex *out, int32_t capacity);

// Procedural 64x64 material tiles (ARGB); used for asset export.
uint32_t bs_atlas_pixel(int32_t material, int32_t x, int32_t y);

// Skinned soldier. `phase` is the walk cycle; `movement`, `air` and `recoil` are 0..1 blend weights.
int32_t bs_actor_vertex_count(void);
int32_t bs_actor_pose(float time, float phase, float movement, float air, float recoil, BsVertex *out,
                      int32_t capacity);

#ifdef __cplusplus
}
#endif
