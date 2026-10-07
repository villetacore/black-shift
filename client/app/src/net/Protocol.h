// Client side of wire protocol v1 (docs/protocol.md): JSON Lines over TCP.
#pragma once
#include <QJsonObject>
#include <QString>

namespace protocol {

constexpr int kVersion = 1;
constexpr quint16 kDefaultPort = 7777;
// Server lines may exceed the 4 KB client limit; anything this large is treated as a broken stream.
constexpr qsizetype kMaxIncomingBytes = 1024 * 1024;

inline QJsonObject join(const QString &name, const QString &role, const QString &mode) {
    return {{"type", "join"}, {"version", kVersion}, {"name", name}, {"class", role}, {"mode", mode}};
}

inline QJsonObject ping() {
    return {{"type", "ping"}};
}

struct Input {
    double forward = 0, strafe = 0, angle = 0, pitch = 0;
    bool swim = false, jump = false, sprint = false, fire = false, ability = false;
    bool crouch = false, reload = false;
    // Snapshot tick on screen when the input was sampled; the server rewinds hits to it.
    int viewTick = -1;
};

inline QJsonObject input(const Input &in) {
    QJsonObject message{{"type", "input"},   {"forward", in.forward}, {"strafe", in.strafe},
                        {"angle", in.angle}, {"pitch", in.pitch},     {"jump", in.jump},
                        {"swim", in.swim},   {"sprint", in.sprint},   {"fire", in.fire},
                        {"crouch", in.crouch}, {"reload", in.reload}, {"ability", in.ability}};
    if (in.viewTick >= 0)
        message["view_tick"] = in.viewTick;
    return message;
}

} // namespace protocol
