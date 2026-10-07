#include "ui/HudPainter.h"
#include "game/Json.h"
#include "game/MatchState.h"
#include "ui/Theme.h"
#include <QPainter>
#include <algorithm>
#include <cmath>

namespace ui {
using namespace theme;
using json::number;

namespace {

constexpr int kMinimapScale = 4, kMinimapX = 22, kMinimapY = 25;
// Brushes taller than this, or starting above head height, are left off the minimap.
constexpr double kMinimapMinHeight = .01, kMinimapMaxBottom = 1.84;

// A riveted, opaque status console inspired by late-1990s FPS interfaces.
void paintConsole(QPainter &p, int w, int h) {
    p.fillRect(0, h - 103, w, 103, QColor(47, 39, 25));
    for (int y = h - 100; y < h; y += 3)
        p.fillRect(0, y, w, 1, QColor(61, 50, 31));
    p.fillRect(0, h - 105, w, 3, QColor(174, 142, 77));
    p.fillRect(0, h - 100, w, 3, QColor(21, 18, 13));
    for (int x : {12, 163, w / 2 + 30, w - 270, w - 12}) {
        p.fillRect(x, h - 92, 2, 81, QColor(20, 17, 11));
        for (int y : {h - 94, h - 12}) {
            p.fillRect(x - 2, y, 5, 5, QColor(153, 134, 91));
            p.fillRect(x - 1, y + 2, 4, 2, QColor(26, 22, 15));
        }
    }
}

void paintScore(QPainter &p, int w, const QJsonObject &state, int team, float height) {
    const auto score = state["score"].toArray();
    const int s0 = score.size() > 0 ? score[0].toInt() : 0, s1 = score.size() > 1 ? score[1].toInt() : 0;
    label(p, w / 2 - 170, 46, QString("CYAN  %1").arg(s0, 3, 10, QChar('0')), 19, cyan, true);
    label(p, w / 2 + 60, 46, QString("%1  AMBER").arg(s1, 3, 10, QChar('0')), 19, orange, true);
    const int secs = state["seconds"].toInt();
    label(p, w / 2 - 28, 43, QString("%1:%2").arg(secs / 60).arg(secs % 60, 2, 10, QChar('0')), 14, paper);
    label(p, w - 172, 30, "ESC  MENU", 9, QColor(204, 163, 73));

    const int relay = state["relay"].toInt(-1);
    const auto capture = state["capture"].toObject();
    const auto objective = state["objective"].toObject();
    const int captureTeam = capture["team"].toInt(-1);
    const int capturePercent = int(std::round(capture["progress"].toDouble() * 100));
    const bool contested = capture["contested"].toBool();
    const QString relayText = contested ? "RELAY / CONTESTED"
                              : capture["active"].toBool() && captureTeam >= 0 && relay != captureTeam
                                  ? QString("RELAY / %1 CAPTURING %2%")
                                        .arg(captureTeam == team ? "YOUR TEAM" : "ENEMY")
                                        .arg(capturePercent)
                              : relay < 0     ? "RELAY / NEUTRAL"
                              : relay == team ? "RELAY / YOUR TEAM CONTROLS"
                                              : "RELAY / ENEMY CONTROLS";
    p.setFont(mono(10, true));
    p.setPen(contested || captureTeam < 0 ? paper : theme::team(captureTeam));
    p.drawText(QRect(w / 2 - 170, 54, 340, 29), Qt::AlignCenter, relayText);
    if (captureTeam >= 0 && relay != captureTeam) {
        p.fillRect(w / 2 - 100, 102, 200, 4, QColor(30, 35, 28));
        p.fillRect(w / 2 - 100, 102, capturePercent * 2, 4, theme::team(captureTeam));
    }
    p.drawText(QRect(w / 2 - 220, 78, 440, 24), Qt::AlignCenter,
               objective["name"].toString() + " / " + QString::number(objective["remaining"].toInt()) + "s" +
                   (std::abs(number(objective, "z") - height) > .65
                        ? QString(" / %1%2m")
                              .arg(number(objective, "z") > height ? "+" : "")
                              .arg(number(objective, "z") - height, 0, 'f', 1)
                        : QString()));
    if (objective["remaining"].toInt() <= 15)
        label(p, w / 2 - 190, 122, "NEXT: " + objective["next_name"].toString(), 11, orange, true);
    const auto wave = state["wave"].toObject();
    label(p, w / 2 - 100, 143,
          QString("WAVE IN %1s / %2 ACTIVE")
              .arg(int(std::ceil(wave["remaining"].toDouble())))
              .arg(wave["active"].toInt()),
          9, muted);
}

// Authored geometry from above, the active objective, structures, teammates and the view direction.
void paintMinimap(QPainter &p, const HudView &view) {
    const auto &match = view.match;
    const auto &state = match.snapshot();
    const int scale = kMinimapScale, mx = kMinimapX, my = kMinimapY;
    label(p, mx, my + match.mapHeight() * scale + 24, match.zoneAt(view.x, view.y), 11, paper, true);
    p.fillRect(mx - 5, my - 5, match.mapWidth() * scale + 10, match.mapHeight() * scale + 10,
               QColor(23, 22, 14, 175));
    p.setPen(Qt::NoPen);
    p.setBrush(QColor(77, 86, 67));
    for (const auto entry : match.map()["objects"].toArray()) {
        const auto o = entry.toObject();
        const auto bounds = o["aabb"].toArray();
        if (bounds.size() != 3 || bounds[2].toArray()[1].toDouble() <= view.z + kMinimapMinHeight ||
            bounds[2].toArray()[0].toDouble() > view.z + kMinimapMaxBottom)
            continue;
        const auto points = o["vertices"].toArray();
        const auto faces = o["faces"].toArray();
        if (faces.isEmpty())
            continue;
        QPolygonF polygon;
        for (const auto index : faces[0].toArray()) {
            const auto point = points[index.toInt()].toArray();
            polygon << QPointF(mx + point[0].toDouble() * scale, my + point[1].toDouble() * scale);
        }
        p.drawPolygon(polygon);
    }
    const auto objective = state["objective"].toObject();
    p.setPen(cyan);
    p.drawEllipse(QPointF(mx + objective.value("x").toDouble(11.5) * scale,
                          my + objective.value("y").toDouble(12.5) * scale),
                  9, 9);
    if (objective["remaining"].toInt() <= 15) {
        p.setBrush(Qt::NoBrush);
        p.setPen(QPen(orange, 1, Qt::DashLine));
        p.drawEllipse(
            QPointF(mx + number(objective, "next_x") * scale, my + number(objective, "next_y") * scale), 9,
            9);
    }
    for (const auto v : state["entities"].toArray()) {
        const auto e = v.toObject();
        if (number(e, "hp") <= 0)
            continue;
        p.fillRect(int(mx + number(e, "x") * scale) - 2, int(my + number(e, "y") * scale) - 2, 4, 4,
                   theme::team(int(number(e, "team"))));
    }
    for (const auto v : state["players"].toArray()) {
        const auto q = v.toObject();
        if (number(q, "hp") <= 0 || int(number(q, "team")) != match.team())
            continue;
        p.setPen(Qt::NoPen);
        p.setBrush(theme::team(match.team()));
        p.drawEllipse(QPointF(mx + number(q, "x") * scale, my + number(q, "y") * scale), 3, 3);
    }
    p.setPen(paper);
    p.drawLine(QPointF(mx + view.x * scale, my + view.y * scale),
               QPointF(mx + (view.x + std::cos(view.yaw) * 1.8f) * scale,
                       my + (view.y + std::sin(view.yaw) * 1.8f) * scale));
}

void paintVitals(QPainter &p, int w, int h, const QJsonObject &me, int team) {
    label(p, 28, h - 77, "VITALS", 9, muted);
    label(p, 28, h - 31, QString::number(int(number(me, "hp"))).rightJustified(3, '0'), 32,
          number(me, "hp") < 35 ? orange : QColor(237, 184, 69), true);
    label(p, 116, h - 33, "HP", 11, muted);
    label(p, 184, h - 77,
          me["class"].toString().toUpper() + " / LEVEL " + QString::number(int(number(me, "level"))), 10,
          theme::team(team), true);
    const double cooldown = number(me, "cooldown");
    label(p, 184, h - 42,
          cooldown > 0 ? QString("Q / RECHARGING %1s").arg(cooldown, 0, 'f', 1) : "Q / ABILITY READY", 14,
          cooldown > 0 ? muted : cyan, true);
    label(p, 184, h - 17,
          me["class"].toString() == "warden" ? "Q HEAL / SHIFT+Q ATTACK"
          : number(me, "boost") > 0          ? "DASH / SPEED BOOST"
                                             : "Q DASH / +25% SPEED FOR 1s",
          9, cyan);
    label(p, w / 2 + 55, h - 76, "KILLS / DEATHS", 9, muted);
    label(p, w / 2 + 55, h - 40,
          QString("%1 / %2").arg(int(number(me, "kills"))).arg(int(number(me, "deaths"))), 22, paper, true);
    const bool warden = me["class"].toString() == "warden";
    label(p, w - 248, h - 76, warden ? "SG-12 / RIOT SHOTGUN" : "SM-9 / COMPACT SMG", 10, muted);
    const int ammo = int(number(me, "ammo")), mag = std::max(1, int(number(me, "mag")));
    const double reload = number(me, "reload");
    const QColor ammoColor = ammo == 0 ? orange : ammo * 4 <= mag ? QColor(237, 184, 69) : paper;
    label(p, w - 248, h - 36, QString::number(ammo).rightJustified(2, '0'), 30, ammoColor, true);
    label(p, w - 186, h - 38, QString("/ %1").arg(mag), 14, muted, true);
    // One pip per round, so the remaining magazine reads at a glance.
    const int pips = std::min(mag, 25), pipWidth = std::max(2, 112 / pips - 2);
    for (int i = 0; i < pips; ++i)
        p.fillRect(w - 128 + i * (pipWidth + 2), h - 52, pipWidth, 12,
                   i < ammo * pips / mag ? ammoColor : QColor(70, 60, 40));
    if (reload > 0)
        label(p, w - 128, h - 30, QString("RELOADING %1s").arg(reload, 0, 'f', 1), 9, orange, true);
    else if (ammo * 4 <= mag)
        label(p, w - 128, h - 30, "R / RELOAD", 9, orange, true);
    else
        label(p, w - 128, h - 30, warden ? "8 PELLETS / PUMP" : "AUTO / 300 RPM", 9, muted);
    if (number(me, "immersion") > .35)
        label(p, w - 248, h - 13, "WATER / SPACE TO RISE", 9, cyan, true);
    else if (me["crouching"].toBool())
        label(p, w - 248, h - 13, "CROUCHED / STEADY AIM", 9, cyan, true);
    else if (me["sprinting"].toBool())
        label(p, w - 248, h - 13, "SPRINT / ENGAGED", 9, cyan, true);
}

void paintFeed(QPainter &p, int w, const QJsonObject &state) {
    int y = 145;
    for (const auto line : state["feed"].toArray()) {
        p.setFont(mono(9));
        p.setPen(paper);
        p.drawText(QRect(w - 340, y, 312, 22), Qt::AlignRight, line.toString());
        y += 23;
    }
}

// The gap shows the current accuracy cone: it opens while moving, jumping and spraying.
void paintCrosshair(QPainter &p, int w, int h, float gap) {
    p.setPen(QPen(paper, 1));
    const int cx = w / 2, cy = h / 2;
    const int inner = std::clamp(int(std::lround(gap)), 3, 90), outer = inner + 7;
    p.drawLine(cx - outer, cy, cx - inner, cy);
    p.drawLine(cx + inner, cy, cx + outer, cy);
    p.drawLine(cx, cy - outer, cx, cy - inner);
    p.drawLine(cx, cy + inner, cx, cy + outer);
    p.drawPoint(cx, cy);
}

// Diagonal ticks confirm a hit; orange for a headshot, larger and red for a kill.
void paintHitMarker(QPainter &p, int w, int h, const HudView &view) {
    if (view.hitFade <= 0)
        return;
    QColor color = view.hitKill ? QColor(235, 64, 44) : view.hitHead ? orange : paper;
    color.setAlphaF(std::min(1.f, view.hitFade * 1.6f));
    p.setPen(QPen(color, view.hitKill ? 3 : 2));
    const int cx = w / 2, cy = h / 2, a = view.hitKill ? 7 : 5, b = view.hitKill ? 16 : 12;
    for (int sx : {-1, 1})
        for (int sy : {-1, 1})
            p.drawLine(cx + sx * a, cy + sy * a, cx + sx * b, cy + sy * b);
}

// A red arc on the side the last damage came from.
void paintDamageDirection(QPainter &p, int w, int h, const HudView &view) {
    if (view.hurtFade <= 0)
        return;
    QColor color(220, 52, 32);
    color.setAlphaF(std::min(1.f, view.hurtFade) * .85f);
    p.save();
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(QPen(color, 6, Qt::SolidLine, Qt::FlatCap));
    const int radius = std::min(w, h) / 6;
    const QRectF circle(w / 2.0 - radius, h / 2.0 - radius, radius * 2.0, radius * 2.0);
    // Qt angles run counter-clockwise from 3 o'clock in 1/16 degrees; ahead is 12 o'clock.
    const double centre = 90.0 - view.hurtAngle * 180.0 / 3.14159265358979323846;
    p.drawArc(circle, int((centre - 22) * 16), 44 * 16);
    p.restore();
}

void paintRespawn(QPainter &p, int w, int h, const QJsonObject &me) {
    p.fillRect(w / 2 - 230, h / 2 - 50, 460, 100, QColor(8, 14, 11, 220));
    p.setPen(orange);
    p.setFont(mono(24, true));
    p.drawText(QRect(w / 2 - 230, h / 2 - 50, 460, 55), Qt::AlignCenter, "SIGNAL LOST");
    p.setFont(mono(12));
    p.setPen(paper);
    p.drawText(QRect(w / 2 - 230, h / 2 + 8, 460, 35), Qt::AlignCenter,
               QString("REDEPLOY IN %1s").arg(number(me, "respawn"), 0, 'f', 1));
}

void paintScoreboard(QPainter &p, int w, int h, const MatchState &match, bool finished) {
    const QRect table(w / 2 - 340, h / 2 - 180, 680, 360);
    p.fillRect(table, QColor(8, 14, 11, 240));
    const int winner = match.snapshot()["winner"].toInt(-1);
    const QString title = !finished                ? "OPERATORS / LIVE ROSTER"
                          : winner < 0             ? "DRAW / RELAY OFFLINE"
                          : winner == match.team() ? "VICTORY / SECTOR SECURED"
                                                   : "DEFEAT / SECTOR LOST";
    label(p, table.x() + 26, table.y() + 42, title, 20, finished ? orange : paper, true);
    label(p, table.x() + 26, table.y() + 82, "OPERATOR                        ROLE       LVL   K / D", 11,
          muted);
    int y = table.y() + 122;
    for (const auto v : match.snapshot()["players"].toArray()) {
        const auto q = v.toObject();
        const QString line = QString("%1 %2 %3    %4 / %5")
                                 .arg(q["name"].toString().left(24), -29)
                                 .arg(q["class"].toString(), -10)
                                 .arg(int(number(q, "level")), 2)
                                 .arg(int(number(q, "kills")), 2)
                                 .arg(int(number(q, "deaths")), 2);
        label(p, table.x() + 26, y, line, 11, theme::team(int(number(q, "team"))));
        y += 32;
    }
    if (finished)
        label(p, table.x() + 26, table.bottom() - 24, "ENTER / RETURN TO TERMINAL", 12, paper);
}

void paintReleased(QPainter &p, int w, int h) {
    p.fillRect(w / 2 - 255, h / 2 - 65, 510, 130, QColor(8, 14, 11, 240));
    label(p, w / 2 - 216, h / 2 - 22, "CONTROLS RELEASED", 23, cyan, true);
    label(p, w / 2 - 216, h / 2 + 12, "CLICK / RESUME     ENTER / LEAVE MATCH", 11, paper);
    label(p, w / 2 - 216, h / 2 + 40, "THE ONLINE MATCH CONTINUES", 10, muted);
}

} // namespace

void paintHud(QPainter &p, const QSize &size, const HudView &view) {
    const int w = size.width(), h = size.height();
    const auto &match = view.match;
    const auto me = match.self();
    // Order matters: later layers draw over earlier ones and share painter state.
    paintConsole(p, w, h);
    paintScore(p, w, match.snapshot(), match.team(), view.z);
    paintMinimap(p, view);
    paintVitals(p, w, h, me, match.team());
    if (match.selfTargeted()) {
        p.setPen(orange);
        p.setFont(mono(12, true));
        p.drawText(QRect(w / 2 - 230, h / 2 + 40, 460, 28), Qt::AlignCenter, "TARGET LOCK // TAKE COVER");
    }
    paintFeed(p, w, match.snapshot());
    if (number(me, "hp") > 0) {
        paintCrosshair(p, w, h, view.crosshairGap);
        paintHitMarker(p, w, h, view);
        paintDamageDirection(p, w, h, view);
    } else
        paintRespawn(p, w, h, me);
    if (view.scoreboard)
        paintScoreboard(p, w, h, match, view.finished);
    else if (!view.captured)
        paintReleased(p, w, h);
}

} // namespace ui
