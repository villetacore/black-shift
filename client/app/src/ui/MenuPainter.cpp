#include "ui/MenuPainter.h"
#include "ui/Theme.h"
#include <QPainter>

namespace ui {
using namespace theme;

namespace {

void paintBackground(QPainter &p, int w, int h) {
    p.fillRect(QRect(0, 0, w, h), QColor(10, 16, 13));
    p.setPen(QColor(23, 35, 27));
    for (int x = 0; x < w; x += 40)
        p.drawLine(x, 0, x, h);
    for (int y = 0; y < h; y += 40)
        p.drawLine(0, y, w, y);
    // Schematic arena, rendered as a subdued technical background.
    p.save();
    p.translate(70, h - 330);
    p.rotate(-12);
    p.setPen(QPen(QColor(50, 66, 48), 1));
    for (int i = 0; i < 7; i++)
        p.drawRect(i * 26, i * 14, 340 - i * 26, 160 - i * 10);
    p.setPen(QPen(QColor(99, 127, 70), 2));
    p.drawLine(0, 95, 390, 95);
    p.drawEllipse(QPoint(190, 95), 27, 27);
    p.restore();
}

void paintTitle(QPainter &p, int w, int h) {
    label(p, 60, 62, "BS / NETWORK COMBAT SYSTEM", 11, muted);
    label(p, w - 290, 62, "BUILD 0.3  /  FULL 3D", 10, muted);
    label(p, 60, 175, "BLACK", 68, paper, true);
    label(p, 60, 260, "SHIFT", 68, QColor(178, 200, 139), true);
    p.fillRect(64, 294, 44, 4, orange);
    label(p, 124, 303, "RELAY CONFLICT", 17, orange, true);
    label(p, 64, 352, "OLD-SCHOOL AIM. TEAM-DRIVEN WAR.", 11, paper);
    label(p, 64, 386, "CONTROL THE RELAY. BREAK THE SENTINEL.", 10, muted);
    label(p, 64, 408, "ESCORT YOUR DRONES. DESTROY THE CORE.", 10, muted);
    label(p, 64, h - 93, "RUST  /  C++ + QT  /  ELIXIR + OTP  /  MNESIA", 10, muted);
    p.setPen(QColor(49, 65, 52));
    p.drawLine(60, h - 66, w - 60, h - 66);
    label(p, 60, h - 36, "WASD MOVE   SHIFT SPRINT   SPACE JUMP   LMB FIRE   Q ABILITY   TAB SCORE", 10,
          paper);
}

void paintUplink(QPainter &p, int w, const QSize &size, const QString &status, qint64 elapsedMs) {
    p.fillRect(panelRect(size), QColor(18, 27, 24));
    label(p, w - 414, 165, "UPLINK / ACTIVE", 17, cyan, true);
    p.setFont(mono(12));
    p.setPen(paper);
    p.drawText(QRect(w - 414, 200, 325, 120), Qt::TextWordWrap, status);
    label(p, w - 414, 410, "ONLINE MATCH: TWO OPERATORS", 10, muted);
    label(p, w - 414, 443, "ESC / CANCEL", 11, orange);
    const int dots = int(elapsedMs / 350) % 4;
    label(p, w - 414, 530, QString(dots + 1, QChar('.')), 28, cyan);
}

} // namespace

void paintMenu(QPainter &p, const QSize &size, bool connecting, const QString &status, qint64 elapsedMs) {
    const int w = size.width(), h = size.height();
    paintBackground(p, w, h);
    paintTitle(p, w, h);
    if (connecting)
        paintUplink(p, w, size, status, elapsedMs);
}

} // namespace ui
