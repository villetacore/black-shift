#pragma once
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QVector3D>

// Client-side animation state of remote players, derived from consecutive snapshots:
// smoothed position, walk phase, airborne blend, confirmed recoil and death time.
class ActorAnimator {
  public:
    struct State {
        // Last snapshot position on the ground plane, and the smoothed render position.
        QVector3D position, rendered;
        float phase = 0, phaseTarget = 0, movement = 0, air = 0, recoil = 0;
        bool seen = false;
        int fireAt = 0;
        float death = 0;
    };

    // Drops state for players that are no longer in the snapshot.
    void retain(const QJsonArray &players);
    // Advances one player's animation by `dt` seconds. `beams` are this snapshot's tracers.
    const State &update(const QJsonObject &player, const QJsonArray &beams, float dt);

  private:
    QHash<QString, State> states;
};
