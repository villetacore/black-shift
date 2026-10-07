#pragma once
#include <QSize>
#include <QString>

class QPainter;

namespace ui {

// Title screen behind the deployment panel. While connecting or queued, `status` is shown
// in place of the panel; `elapsedMs` animates the progress dots.
void paintMenu(QPainter &p, const QSize &size, bool connecting, const QString &status, qint64 elapsedMs);

} // namespace ui
