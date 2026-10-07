#pragma once
#include "game/MatchState.h"
#include "input/InputController.h"
#include "net/ServerConnection.h"
#include <QElapsedTimer>
#include <QOpenGLWidget>
#include <QTimer>
#include <memory>

class DeploymentPanel;
class SceneRenderer;

// The game window: menu → connecting/queued → playing → finished.
// Owns the server connection, the client copy of the match, input handling and rendering.
class GameWidget final : public QOpenGLWidget {
    Q_OBJECT

  public:
    explicit GameWidget(QWidget *parent = nullptr);
    ~GameWidget() override;

    // Fills in the deployment form and joins immediately.
    void autoConnect(const QString &address, const QString &name, const QString &role, const QString &mode);
    // Keeps the mouse from moving the camera, for reproducible captures.
    void setScreenshotMode() {
        screenshotMode = true;
    }

    bool rendererReady() const;
    bool hasSnapshot() const {
        return match.hasSnapshot();
    }
    QJsonObject localPlayer() const {
        return match.self();
    }
    const MatchState &matchState() const {
        return match;
    }

  protected:
    void initializeGL() override;
    void paintGL() override;
    void resizeEvent(QResizeEvent *) override;
    void keyPressEvent(QKeyEvent *) override;
    void keyReleaseEvent(QKeyEvent *) override;
    void mouseMoveEvent(QMouseEvent *) override;
    void mousePressEvent(QMouseEvent *) override;
    void mouseReleaseEvent(QMouseEvent *) override;
    void focusOutEvent(QFocusEvent *) override;

  private:
    enum class Screen { Menu, Connecting, Queued, Playing, Finished };

    Screen screen = Screen::Menu;
    ServerConnection connection;
    MatchState match;
    InputController input;
    DeploymentPanel *panel = nullptr;
    std::unique_ptr<SceneRenderer> renderer;
    QTimer frameTimer, inputTimer;
    QElapsedTimer clock;
    QString mode, status;
    bool screenshotMode = false;
    // The game owns the mouse and keyboard (cursor hidden and centred).
    bool captured = false;
    // Camera position, smoothed towards the server position.
    bool haveView = false;
    float viewX = 3.5f, viewY = 11.5f, viewZ = 0;
    int lastHp = 100;
    qint64 lastFrame = 0, shotUntil = 0, damageUntil = 0;
    // When the latest snapshot arrived; the camera extrapolates along the reported velocity.
    qint64 snapshotAt = 0;
    // Server recoil and eye height, smoothed for the camera.
    float recoilView = 0, recoilYawView = 0, eyeView = 1.48f;
    // Hit confirmation and incoming damage, detected from snapshot counters.
    int lastHits = 0, lastHurtAt = 0;
    bool hitHead = false, hitKill = false;
    qint64 hitAt = -10'000, hurtAt = -10'000;
    float hurtDir = 0;

    void join(const QString &requestedMode);
    // Returns to the main menu, optionally showing an error.
    void lobby(const QString &error = QString());
    void handleMessage(const QJsonObject &message);
    void handleSnapshot(const QJsonObject &snapshot);
    void sendInput();
    void capture(bool enabled);
    void renderWorld();
};
