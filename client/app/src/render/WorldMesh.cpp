#include "render/WorldMesh.h"
#include "render/Models.h"
#include <QHash>
#include <QJsonArray>
#include <QMatrix4x4>
#include <QVector3D>
#include <QVector4D>
#include <algorithm>
#include <cmath>

namespace {

// Faces are split until every edge is shorter than this, so vertex lighting has enough samples.
constexpr float kMaxEdge = 1.8f;
constexpr int kMaxSubdivision = 5;
constexpr float kMinLight = .16f, kMaxLight = 1.2f;

// Map (x, y, height) to render space (x, height, y).
QVector3D renderVector(const QJsonValue &value) {
    const auto a = value.toArray();
    return {float(a[0].toDouble()), float(a[2].toDouble()), float(a[1].toDouble())};
}

struct Collider {
    QVector3D lo, hi;
    // Inside when dot(xyz, p) < w for every plane.
    std::vector<QVector4D> planes;
};

struct Light {
    QVector3D position;
    float intensity, radius;
};

std::vector<Collider> collidersOf(const QJsonArray &objects) {
    std::vector<Collider> colliders;
    for (const auto entry : objects) {
        const auto o = entry.toObject();
        // A prop collision hull contains empty space around its detailed mesh.
        // Using it for visual culling deletes recessed panels and the floor between its feet.
        // Keep brush occlusion; prop collision remains authoritative on the server.
        if (!o["collision"].toBool() || !o["model"].toString().isEmpty())
            continue;
        const auto bounds = o["aabb"].toArray();
        Collider c;
        c.lo = {float(bounds[0].toArray()[0].toDouble()), float(bounds[2].toArray()[0].toDouble()),
                float(bounds[1].toArray()[0].toDouble())};
        c.hi = {float(bounds[0].toArray()[1].toDouble()), float(bounds[2].toArray()[1].toDouble()),
                float(bounds[1].toArray()[1].toDouble())};
        for (const auto plane : o["planes"].toArray()) {
            const auto p = plane.toArray();
            c.planes.push_back({float(p[0].toDouble()), float(p[2].toDouble()), float(p[1].toDouble()),
                                float(p[3].toDouble())});
        }
        colliders.push_back(c);
    }
    return colliders;
}

bool inside(const std::vector<Collider> &colliders, const QVector3D &p) {
    for (const auto &c : colliders) {
        if (p.x() < c.lo.x() || p.y() < c.lo.y() || p.z() < c.lo.z() || p.x() > c.hi.x() ||
            p.y() > c.hi.y() || p.z() > c.hi.z())
            continue;
        bool hit = true;
        for (const auto &plane : c.planes)
            if (QVector3D::dotProduct(plane.toVector3D(), p) >= plane.w() - .0001f) {
                hit = false;
                break;
            }
        if (hit)
            return true;
    }
    return false;
}

// True when a ray from `origin` towards `direction` hits any collider within 30 m.
bool shadowed(const std::vector<Collider> &colliders, const QVector3D &origin, const QVector3D &direction) {
    for (const auto &collider : colliders) {
        float near = 0.f, far = 30.f;
        for (const auto &plane : collider.planes) {
            const float den = QVector3D::dotProduct(plane.toVector3D(), direction);
            const float distance = plane.w() - QVector3D::dotProduct(plane.toVector3D(), origin);
            if (std::abs(den) < .00001f) {
                if (distance < 0) {
                    far = -1;
                    break;
                }
            } else if (den < 0)
                near = std::max(near, distance / den);
            else
                far = std::min(far, distance / den);
            if (near > far)
                break;
        }
        if (near <= far)
            return true;
    }
    return false;
}

class Builder {
  public:
    explicit Builder(const std::vector<Collider> &colliders) : colliders(colliders) {}

    std::vector<BsVertex> vertices;

    // Adds a triangle with UVs projected on its own plane (uniform texel density).
    void triangle(QVector3D a, QVector3D b, QVector3D c, int material, float density, int depth = 0) {
        if (depth < kMaxSubdivision &&
            std::max({(a - b).length(), (b - c).length(), (c - a).length()}) > kMaxEdge) {
            const auto ab = (a + b) * .5f, bc = (b + c) * .5f, ca = (c + a) * .5f;
            triangle(a, ab, ca, material, density, depth + 1);
            triangle(ab, b, bc, material, density, depth + 1);
            triangle(ca, bc, c, material, density, depth + 1);
            triangle(ab, bc, ca, material, density, depth + 1);
            return;
        }
        const QVector3D n = QVector3D::crossProduct(b - a, c - a).normalized();
        if (n.lengthSquared() < .5f)
            return;
        // Fully buried faces are never visible.
        if (inside(colliders, a + n * .003f) && inside(colliders, b + n * .003f) &&
            inside(colliders, c + n * .003f))
            return;
        const QVector3D tangent =
            std::abs(n.y()) > .95f ? QVector3D(1, 0, 0) : QVector3D::crossProduct({0, 1, 0}, n).normalized();
        const QVector3D bitangent = QVector3D::crossProduct(n, tangent).normalized();
        for (const auto &position : {a, b, c}) {
            BsVertex v{};
            for (int i = 0; i < 3; i++) {
                v.position[i] = position[i];
                v.normal[i] = n[i];
            }
            v.uv[0] = QVector3D::dotProduct(position, tangent) * density;
            v.uv[1] = QVector3D::dotProduct(position, bitangent) * density;
            v.material = float(material);
            vertices.push_back(v);
        }
    }

  private:
    const std::vector<Collider> &colliders;
};

void bakeLighting(std::vector<BsVertex> &vertices, const std::vector<Collider> &colliders,
                  const std::vector<Light> &lights) {
    // Directional daylight, clipped against the same convex brushes.
    const QVector3D sun = QVector3D(-.35f, 1.f, -.25f).normalized();
    for (auto &v : vertices) {
        const QVector3D p(v.position[0], v.position[1], v.position[2]),
            n(v.normal[0], v.normal[1], v.normal[2]);
        const auto origin = p + n * .015f;
        float illumination = kMinLight;
        if (!shadowed(colliders, origin, sun))
            illumination += .14f + .58f * std::max(0.f, QVector3D::dotProduct(n, sun));
        for (const auto &light : lights) {
            const auto delta = light.position - p;
            const float distance = delta.length();
            if (distance < .01f || distance > light.radius)
                continue;
            const float incidence = std::max(0.f, QVector3D::dotProduct(n, delta / distance));
            if (incidence < .01f)
                continue;
            // Shadow test by sampling the segment to the light every 15 cm.
            bool blocked = false;
            const int steps = std::max(1, int(distance / .15f));
            for (int i = 1; i < steps; i++)
                if (inside(colliders, origin + (light.position - origin) * (float(i) / steps))) {
                    blocked = true;
                    break;
                }
            if (!blocked)
                illumination += incidence * light.intensity / (1.f + .28f * distance * distance);
        }
        illumination = std::clamp(illumination, kMinLight, kMaxLight);
        for (float &component : v.normal)
            component *= illumination;
    }
}

} // namespace

std::vector<BsVertex> buildWorldMesh(const QJsonObject &map) {
    const auto objects = map["objects"].toArray();
    const auto colliders = collidersOf(objects);
    const QHash<QString, std::vector<BsVertex>> props = {{"pallet", modelVertices(BS_MODEL_PALLET)},
                                                         {"console", modelVertices(BS_MODEL_CONSOLE)},
                                                         {"generator", modelVertices(BS_MODEL_GENERATOR)},
                                                         {"tank", modelVertices(BS_MODEL_TANK)},
                                                         {"pump", modelVertices(BS_MODEL_PUMP)},
                                                         {"cable-spool", modelVertices(BS_MODEL_CABLE_SPOOL)},
                                                         {"bollard", modelVertices(BS_MODEL_BOLLARD)},
                                                         {"lamp", modelVertices(BS_MODEL_LAMP)},
                                                         {"barricade", modelVertices(BS_MODEL_BARRICADE)},
                                                         {"fan", modelVertices(BS_MODEL_FAN)},
                                                         {"crate", modelVertices(BS_MODEL_CRATE)},
                                                         {"barrel", modelVertices(BS_MODEL_BARREL)},
                                                         {"vent", modelVertices(BS_MODEL_VENT)},
                                                         {"cabinet", modelVertices(BS_MODEL_CABINET)}};
    Builder builder(colliders);
    for (const auto entry : objects) {
        const auto o = entry.toObject();
        const float density = float(o["uv_scale"].toDouble(.5));
        const auto prop = props.constFind(o["model"].toString());
        if (prop != props.cend()) {
            const auto &crate = prop.value();
            // Props replace the brush's appearance; collision still uses the authored volume.
            QMatrix4x4 transform;
            transform.translate(renderVector(o["position"]));
            transform.rotate(-float(o["yaw"].toDouble()), 0, 1, 0);
            transform.scale(renderVector(o["size"]));
            auto point = [&](size_t index) {
                const auto &v = crate[index];
                return transform.map(QVector3D(v.position[0], v.position[1], v.position[2]));
            };
            for (size_t i = 0; i + 2 < crate.size(); i += 3)
                builder.triangle(point(i), point(i + 1), point(i + 2), int(crate[i].material), density);
            continue;
        }
        const auto points = o["vertices"].toArray();
        for (const auto face : o["faces"].toArray()) {
            const auto indices = face.toArray();
            // Map faces wind counter-clockwise in (x, y, z); swapping two corners keeps them
            // front-facing after the (x, z, y) axis swap.
            for (int i = 1; i + 1 < indices.size(); i++)
                builder.triangle(renderVector(points[indices[0].toInt()]),
                                 renderVector(points[indices[i + 1].toInt()]),
                                 renderVector(points[indices[i].toInt()]), o["material"].toInt(), density);
        }
    }
    std::vector<Light> lights;
    for (const auto entry : map["lights"].toArray()) {
        const auto l = entry.toObject();
        lights.push_back({renderVector(l["position"]), float(l["intensity"].toDouble(2.6)),
                          float(l["radius"].toDouble(8))});
    }
    bakeLighting(builder.vertices, colliders, lights);
    return std::move(builder.vertices);
}
