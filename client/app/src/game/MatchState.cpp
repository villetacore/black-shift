#include "game/MatchState.h"

namespace {
constexpr int kSceneFormat = 2;
constexpr int kMinMapSize = 3, kMaxMapSize = 256;
} // namespace

void MatchState::reset() {
    snapshot_ = {};
    map_ = {};
}

void MatchState::clearSnapshot() {
    snapshot_ = {};
}

QString MatchState::start(const QJsonObject &message) {
    map_ = message["map"].toObject();
    const auto bounds = map_["bounds"].toArray();
    if (map_["format"].toInt() != kSceneFormat || bounds.size() != 3 || map_["objects"].toArray().isEmpty())
        return "Unsupported 3D scene format.";
    mapWidth_ = int(bounds[0].toDouble());
    mapHeight_ = int(bounds[1].toDouble());
    if (mapWidth_ < kMinMapSize || mapHeight_ < kMinMapSize || mapWidth_ > kMaxMapSize ||
        mapHeight_ > kMaxMapSize)
        return "Invalid arena bounds.";
    team_ = message["team"].toInt();
    playerId_ = message["id"].toString();
    return {};
}

QJsonObject MatchState::self() const {
    for (const auto value : snapshot_["players"].toArray()) {
        auto player = value.toObject();
        if (player["id"].toString() == playerId_)
            return player;
    }
    return {};
}

QString MatchState::zoneAt(float x, float y) const {
    for (const auto value : map_["zones"].toArray()) {
        const auto zone = value.toObject();
        const auto r = zone["rect"].toArray();
        if (r.size() == 4 && x >= r[0].toDouble() && y >= r[1].toDouble() && x < r[2].toDouble() &&
            y < r[3].toDouble())
            return zone["name"].toString();
    }
    return {};
}

bool MatchState::selfTargeted() const {
    for (const auto value : snapshot_["entities"].toArray()) {
        const auto entity = value.toObject();
        if (entity["warning"].toBool() && entity["target"].toString() == playerId_)
            return true;
    }
    return false;
}
