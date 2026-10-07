#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>

// Client copy of the server-authoritative match: the map from `start` and the latest `snapshot`.
class MatchState {
  public:
    // Forgets the map and the snapshot (before joining a new match).
    void reset();
    // Forgets the snapshot only.
    void clearSnapshot();

    void setPlayerId(const QString &id) {
        playerId_ = id;
    }
    // Validates and stores a `start` message. Returns an error message, or an empty string.
    QString start(const QJsonObject &message);
    void update(const QJsonObject &snapshot) {
        snapshot_ = snapshot;
    }

    const QString &playerId() const {
        return playerId_;
    }
    int team() const {
        return team_;
    }
    const QJsonObject &map() const {
        return map_;
    }
    const QJsonObject &snapshot() const {
        return snapshot_;
    }
    bool hasMap() const {
        return !map_.isEmpty();
    }
    bool hasSnapshot() const {
        return !snapshot_.isEmpty();
    }
    int mapWidth() const {
        return mapWidth_;
    }
    int mapHeight() const {
        return mapHeight_;
    }

    // The local player's entry in the snapshot, or an empty object.
    QJsonObject self() const;
    // Name of the first map zone containing (x, y); zones are listed most specific first.
    QString zoneAt(float x, float y) const;
    // True while a tower or drone is acquiring the local player.
    bool selfTargeted() const;

  private:
    QString playerId_;
    QJsonObject map_, snapshot_;
    int team_ = 0, mapWidth_ = 0, mapHeight_ = 0;
};
