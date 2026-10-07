#pragma once
#include "blackshift_core.h"
#include <QJsonObject>
#include <vector>

// Builds the static world from a scene-format-2 map (docs/scene-format.md).
//
// Brush faces are triangulated, subdivided for smoother baked lighting and given
// world-space UVs with uniform texel density; faces buried inside other brushes are
// dropped. Lighting (sun + point lights, with shadow rays against the brushes) is
// baked per vertex and stored as the length of each vertex normal.
//
// Map coordinates are (x, y, height); the result is in render space (x, height, y).
std::vector<BsVertex> buildWorldMesh(const QJsonObject &map);
