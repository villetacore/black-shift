#include "render/ActorAnimator.h"
#include "game/Json.h"
#include <algorithm>
#include <cmath>

using json::real;

namespace {
// Larger jumps are respawns or teleports, not walking.
constexpr float kMaxStride = 0.8f, kSnapDistance = 2.f;
// Metres travelled per walk cycle.
constexpr float kStrideLength = 1.45f;

} // namespace

void ActorAnimator::retain(const QJsonArray &players) {
    for (auto it = states.begin(); it != states.end();) {
        bool present = false;
        for (const auto entry : players)
            if (entry.toObject()["id"].toString() == it.key())
                present = true;
        if (!present)
            it = states.erase(it);
        else
            ++it;
    }
}

const ActorAnimator::State &ActorAnimator::update(const QJsonObject &p, const QJsonArray &beams, float dt) {
    const float px = real(p, "x"), py = real(p, "y"), pz = real(p, "z");
    auto &s = states[p["id"].toString()];
    const QVector3D position(px, 0, py);
    float distance = s.seen ? (position - s.position).length() : 0;
    if (distance > kMaxStride)
        distance = 0;
    const QVector3D target(px, pz, py);
    if (!s.seen || (target - s.rendered).length() > kSnapDistance)
        s.rendered = target;
    else
        s.rendered += (target - s.rendered) * (1.f - std::exp(-dt * 18.f));
    s.position = position;
    s.seen = true;
    s.phaseTarget += distance / kStrideLength;
    s.phase += (s.phaseTarget - s.phase) * (1.f - std::exp(-dt * 18.f));
    s.movement = std::max(s.movement * std::exp(-dt * 9.f), distance > 0.005f ? 1.f : 0.f);
    const float air = p["grounded"].toBool(true) ? 0.f : 1.f;
    s.air += (air - s.air) * std::min(1.f, dt * 12.f);
    s.recoil *= std::exp(-dt * 15.f);
    Q_UNUSED(beams);
    const int fireAt = p["fire_at"].toInt();
    if (fireAt > s.fireAt)
        s.recoil = 1.f;
    s.fireAt = fireAt;
    s.death = real(p, "hp") <= 0 ? s.death + dt : 0.f;
    return s;
}
