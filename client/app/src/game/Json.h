#pragma once
#include <QJsonObject>
#include <QLatin1String>

namespace json {

inline double number(const QJsonObject &o, const char *key) {
    return o.value(QLatin1String(key)).toDouble();
}

inline float real(const QJsonObject &o, const char *key) {
    return float(number(o, key));
}

} // namespace json
