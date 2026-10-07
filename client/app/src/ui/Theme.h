// Shared colours, fonts and text helpers for the 2D interface.
#pragma once
#include <QColor>
#include <QFont>
#include <QRect>
#include <QSize>
#include <QString>

class QPainter;

namespace theme {

inline const QColor cyan(101, 220, 208), orange(241, 151, 75), paper(223, 222, 201), muted(124, 140, 132);

inline QColor team(int team) {
    return team == 0 ? cyan : orange;
}

QFont mono(int size, bool bold = false);

// Draws one line of monospace text with its baseline at (x, y).
void label(QPainter &p, int x, int y, const QString &text, int size, const QColor &color = paper,
           bool bold = false);

// Area of the deployment panel and of the connection status box that replaces it.
inline QRect panelRect(const QSize &window) {
    return {window.width() - 440, 110, 380, 490};
}

} // namespace theme
