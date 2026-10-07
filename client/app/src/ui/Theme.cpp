#include "ui/Theme.h"
#include <QPainter>

namespace theme {

QFont mono(int size, bool bold) {
    QFont font("Consolas", size);
    font.setStyleHint(QFont::Monospace);
    font.setBold(bold);
    return font;
}

void label(QPainter &p, int x, int y, const QString &text, int size, const QColor &color, bool bold) {
    p.setFont(mono(size, bold));
    p.setPen(color);
    p.drawText(x, y, text);
}

} // namespace theme
