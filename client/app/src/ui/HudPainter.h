#pragma once
#include <QSize>

class MatchState;
class QPainter;

namespace ui {

struct HudView {
    const MatchState &match;
    // Smoothed camera position and yaw.
    float x, y, z, yaw;
    // Controls are captured by the game (otherwise the "released" notice is shown).
    bool captured;
    // Tab held, or the match is over.
    bool scoreboard;
    bool finished;
    // Pixels from the screen centre to the crosshair lines; follows the weapon's accuracy cone.
    float crosshairGap = 4;
    // Hit confirmation: 1 right after a hit, fading to 0.
    float hitFade = 0;
    bool hitHead = false, hitKill = false;
    // Incoming damage: 1 right after a hit, fading to 0; direction relative to the view
    // (0 = ahead, positive = to the right).
    float hurtFade = 0, hurtAngle = 0;
};

// In-match 2D overlay: status console, scores, objective, minimap, kill feed, crosshair
// and the scoreboard / result table.
void paintHud(QPainter &p, const QSize &size, const HudView &view);

} // namespace ui
