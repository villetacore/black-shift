#include "input/InputController.h"
#include <Qt>
#include <algorithm>
#include <cmath>

namespace {
constexpr float kPi = 3.14159265358979323846f;
constexpr float kMouseYaw = 0.003f, kMousePitch = 0.0025f;
// Radians per input message when turning with the arrow keys.
constexpr float kKeyTurn = 0.065f;
// Matches the server's clamp.
constexpr float kMaxPitch = 1.15f;
} // namespace

void InputController::release() {
    firing_ = false;
    keys.clear();
    abilityPressed = false;
    jumpPressed = false;
    reloadPressed = false;
}

void InputController::keyPressed(int key) {
    keys.insert(key);
    if (key == Qt::Key_Space)
        jumpPressed = true;
    if (key == Qt::Key_Q)
        abilityPressed = true;
    if (key == Qt::Key_R)
        reloadPressed = true;
}

void InputController::keyReleased(int key) {
    keys.remove(key);
}

void InputController::look(int dx, int dy) {
    yaw_ = std::remainder(yaw_ + dx * kMouseYaw, 2 * kPi);
    pitch_ = std::clamp(pitch_ - dy * kMousePitch, -kMaxPitch, kMaxPitch);
}

bool InputController::crouching() const {
    return held(Qt::Key_C) || held(Qt::Key_Control);
}

bool InputController::walking() const {
    return held(Qt::Key_W) || held(Qt::Key_S) || held(Qt::Key_A) || held(Qt::Key_D);
}

protocol::Input InputController::take(bool captured) {
    protocol::Input in;
    if (captured) {
        in.forward = (held(Qt::Key_W) ? 1 : 0) - (held(Qt::Key_S) ? 1 : 0);
        in.strafe = (held(Qt::Key_D) ? 1 : 0) - (held(Qt::Key_A) ? 1 : 0);
        if (held(Qt::Key_Left))
            yaw_ -= kKeyTurn;
        if (held(Qt::Key_Right))
            yaw_ += kKeyTurn;
    }
    in.angle = double(yaw_);
    in.pitch = double(pitch_);
    in.jump = captured && jumpPressed;
    in.swim = captured && held(Qt::Key_Space);
    in.sprint = captured && held(Qt::Key_Shift);
    in.fire = captured && firing_;
    in.ability = captured && abilityPressed;
    in.crouch = captured && crouching();
    in.reload = captured && reloadPressed;
    abilityPressed = false;
    jumpPressed = false;
    reloadPressed = false;
    return in;
}
