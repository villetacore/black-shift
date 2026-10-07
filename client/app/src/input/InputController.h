#pragma once
#include "net/Protocol.h"
#include <QSet>

// Keyboard/mouse state and view angles. Turns raw events into protocol input messages.
class InputController {
  public:
    // Forgets held keys, the fire button and latched presses (when controls are released).
    void release();

    void keyPressed(int key);
    void keyReleased(int key);
    void setFiring(bool firing) {
        firing_ = firing;
    }
    // Mouse look in pixels from the window centre.
    void look(int dx, int dy);
    void setView(float yaw, float pitch) {
        yaw_ = yaw;
        pitch_ = pitch;
    }

    // Builds the next input message. Applies keyboard turning and consumes latched presses.
    // Without `captured` controls, the message is neutral apart from the view angles.
    protocol::Input take(bool captured);

    bool held(int key) const {
        return keys.contains(key);
    }
    bool firing() const {
        return firing_;
    }
    bool walking() const;
    // C or Ctrl held.
    bool crouching() const;
    float yaw() const {
        return yaw_;
    }
    float pitch() const {
        return pitch_;
    }

  private:
    QSet<int> keys;
    bool firing_ = false;
    // Presses latched until the next input message, so short taps are not lost.
    bool jumpPressed = false, abilityPressed = false, reloadPressed = false;
    float yaw_ = 0, pitch_ = 0;
};
