#include "app/GameWidget.h"
#include "game/Json.h"
#include "net/Protocol.h"
#include "render/SceneRenderer.h"
#include "ui/DeploymentPanel.h"
#include "ui/HudPainter.h"
#include "ui/MenuPainter.h"
#include "ui/Theme.h"
#include <QCursor>
#include <QDebug>
#include <QFocusEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <algorithm>
#include <cmath>

using json::number;

namespace {
constexpr int kFrameMs = 16;
// Input is sent at ~30 Hz; the server simulates at 20 Hz.
constexpr int kInputMs = 33;
constexpr int kDamageFlashMs = 180;
constexpr int kMuzzleFlashMs = 55;
constexpr int kHitMarkerMs = 180, kDamageDirectionMs = 900;
// Camera extrapolation along the server velocity stops after this long without a snapshot.
constexpr float kMaxExtrapolation = .1f;
constexpr float kStandingEye = 1.48f, kCrouchedEye = .98f;
constexpr float kPi = 3.14159265358979323846f;
} // namespace

GameWidget::GameWidget(QWidget *parent) : QOpenGLWidget(parent) {
    QSurfaceFormat format;
    format.setVersion(2, 1);
    format.setProfile(QSurfaceFormat::CompatibilityProfile);
    format.setDepthBufferSize(24);
    format.setStencilBufferSize(8);
    format.setSamples(0);
    format.setSwapInterval(1);
    setFormat(format);
    setMinimumSize(960, 640);
    setFocusPolicy(Qt::StrongFocus);
    setMouseTracking(true);
    clock.start();

    panel = new DeploymentPanel(this);
    connect(panel, &DeploymentPanel::joinRequested, this, &GameWidget::join);

    connect(&connection, &ServerConnection::connected, this,
            [this] { connection.send(protocol::join(panel->callsign(), panel->role(), mode)); });
    connect(&connection, &ServerConnection::message, this, &GameWidget::handleMessage);
    connect(&connection, &ServerConnection::failed, this, [this](const QString &reason) { lobby(reason); });
    connect(&connection, &ServerConnection::closedByServer, this, [this] {
        if (screen != Screen::Menu && screen != Screen::Finished)
            lobby("Connection closed. Start the server and reconnect.");
    });

    connect(&frameTimer, &QTimer::timeout, this, [this] {
        if (captured && !isActiveWindow())
            capture(false);
        update();
    });
    frameTimer.start(kFrameMs);
    connect(&inputTimer, &QTimer::timeout, this, &GameWidget::sendInput);
    inputTimer.start(kInputMs);
}

GameWidget::~GameWidget() {
    // No connection callbacks into members that are being destroyed.
    connection.disconnect(this);
    connection.close();
    // GL resources must be released with the context current.
    makeCurrent();
    renderer.reset();
    doneCurrent();
}

bool GameWidget::rendererReady() const {
    return renderer && renderer->ready();
}

void GameWidget::autoConnect(const QString &address, const QString &name, const QString &role,
                             const QString &selectedMode) {
    panel->setValues(address, name, role);
    join(selectedMode);
}

void GameWidget::join(const QString &requestedMode) {
    QString error;
    const auto endpoint = parseEndpoint(panel->address(), &error);
    if (!endpoint) {
        panel->showMessage(error);
        return;
    }
    match.reset();
    haveView = false;
    input.release();
    mode = requestedMode;
    screen = Screen::Connecting;
    status = "CONNECTING TO " + panel->address();
    panel->hide();
    setFocus();
    connection.open(*endpoint);
    update();
}

void GameWidget::lobby(const QString &error) {
    capture(false);
    connection.close();
    screen = Screen::Menu;
    match.clearSnapshot();
    panel->show();
    panel->showMessage(error);
    update();
}

void GameWidget::handleMessage(const QJsonObject &message) {
    const QString type = message["type"].toString();
    if (type == "hello") {
        match.setPlayerId(message["id"].toString());
        if (message["version"].toInt() != protocol::kVersion)
            lobby("Incompatible protocol.");
    } else if (type == "error") {
        lobby(message["message"].toString());
    } else if (type == "queue") {
        screen = Screen::Queued;
        status = QString("MATCHMAKING / %1 OF %2 OPERATORS")
                     .arg(message["waiting"].toInt())
                     .arg(message["needed"].toInt());
    } else if (type == "start") {
        const QString error = match.start(message);
        if (!error.isEmpty()) {
            lobby(error);
            return;
        }
        screen = Screen::Playing;
        capture(true);
    } else if (type == "snapshot") {
        handleSnapshot(message);
    } else if (type == "result") {
        screen = Screen::Finished;
        capture(false);
    }
}

void GameWidget::handleSnapshot(const QJsonObject &snapshot) {
    const auto previous = match.self();
    match.update(snapshot);
    const auto me = match.self();
    if (me.isEmpty())
        return;
    // Snap the camera on the first snapshot and on respawn; otherwise it is smoothed per frame.
    const bool first = !haveView;
    if (!haveView || (number(previous, "hp") <= 0 && number(me, "hp") > 0)) {
        viewX = float(number(me, "x"));
        viewY = float(number(me, "y"));
        viewZ = float(number(me, "z"));
        input.setView(float(number(me, "angle")), float(number(me, "pitch")));
        haveView = true;
    }
    snapshotAt = clock.elapsed();
    const int hits = int(number(me, "hits")), hurt = int(number(me, "hurt_at"));
    if (!first && hits > lastHits) {
        hitAt = clock.elapsed();
        hitHead = me["hit_head"].toBool();
        hitKill = me["hit_kill"].toBool();
    }
    if (!first && hurt > lastHurtAt && me["hurt_dir"].isDouble()) {
        hurtAt = clock.elapsed();
        hurtDir = float(me["hurt_dir"].toDouble());
    }
    lastHits = hits;
    lastHurtAt = hurt;
    if (number(me, "hp") < lastHp)
        damageUntil = clock.elapsed() + kDamageFlashMs;
    lastHp = int(number(me, "hp"));
    if (snapshot["over"].toBool()) {
        screen = Screen::Finished;
        capture(false);
    }
}

void GameWidget::capture(bool enabled) {
    captured = enabled;
    input.release();
    if (enabled) {
        setCursor(Qt::BlankCursor);
        setFocus();
        QCursor::setPos(mapToGlobal(rect().center()));
    } else {
        unsetCursor();
    }
}

void GameWidget::sendInput() {
    if (screen != Screen::Playing)
        return;
    auto in = input.take(captured);
    // Remote players are drawn smoothed, about one tick behind the newest snapshot.
    if (match.hasSnapshot())
        in.viewTick = std::max(0, match.snapshot()["tick"].toInt() - 1);
    connection.send(protocol::input(in));
    if (captured && input.firing() && number(match.self(), "hp") > 0)
        shotUntil = clock.elapsed() + kMuzzleFlashMs;
}

void GameWidget::resizeEvent(QResizeEvent *event) {
    QOpenGLWidget::resizeEvent(event);
    panel->setGeometry(theme::panelRect(size()));
}

void GameWidget::keyPressEvent(QKeyEvent *e) {
    if (e->isAutoRepeat())
        return;
    if (e->key() == Qt::Key_Escape) {
        if (screen == Screen::Playing)
            capture(!captured);
        else
            lobby();
        return;
    }
    if (e->key() == Qt::Key_F11) {
        isFullScreen() ? showNormal() : showFullScreen();
        return;
    }
    if ((screen == Screen::Finished || (screen == Screen::Playing && !captured)) &&
        e->key() == Qt::Key_Return) {
        lobby();
        return;
    }
    input.keyPressed(e->key());
}

void GameWidget::keyReleaseEvent(QKeyEvent *e) {
    if (!e->isAutoRepeat())
        input.keyReleased(e->key());
}

void GameWidget::mouseMoveEvent(QMouseEvent *e) {
    if (!captured || screenshotMode)
        return;
    const int dx = int(e->position().x()) - rect().center().x();
    const int dy = int(e->position().y()) - rect().center().y();
    if (dx || dy) {
        input.look(dx, dy);
        QCursor::setPos(mapToGlobal(rect().center()));
    }
}

void GameWidget::mousePressEvent(QMouseEvent *e) {
    if (screen != Screen::Playing)
        return;
    if (!captured) {
        capture(true);
        return;
    }
    if (e->button() == Qt::LeftButton)
        input.setFiring(true);
}

void GameWidget::mouseReleaseEvent(QMouseEvent *e) {
    if (e->button() == Qt::LeftButton)
        input.setFiring(false);
}

void GameWidget::focusOutEvent(QFocusEvent *e) {
    capture(false);
    QOpenGLWidget::focusOutEvent(e);
}

void GameWidget::initializeGL() {
    renderer = std::make_unique<SceneRenderer>();
    if (!renderer->initialize())
        qWarning() << "3D renderer:" << renderer->error();
}

void GameWidget::renderWorld() {
    const auto me = match.self();
    const qint64 now = clock.elapsed();
    const float dt = std::min(0.08f, float(now - lastFrame) / 1000);
    lastFrame = now;
    const float blend = 1 - std::exp(-18 * dt);
    // Dead reckoning: continue along the server velocity between snapshots.
    const float ahead = std::min(kMaxExtrapolation, float(now - snapshotAt) / 1000);
    viewX += (float(number(me, "x") + number(me, "vx") * ahead) - viewX) * blend;
    viewY += (float(number(me, "y") + number(me, "vy") * ahead) - viewY) * blend;
    viewZ += (float(number(me, "z")) - viewZ) * blend;
    // Crouching responds to the key at once; the server keeps it while there is no headroom.
    const bool crouched = (captured && input.crouching()) || me["crouching"].toBool();
    eyeView += ((crouched ? kCrouchedEye : kStandingEye) - eyeView) * (1 - std::exp(-14 * dt));
    // The camera shows the authoritative recoil, so the crosshair is where shots go.
    const float recoilBlend = 1 - std::exp(-30 * dt);
    recoilView += (float(number(me, "recoil")) - recoilView) * recoilBlend;
    recoilYawView += (float(number(me, "recoil_yaw")) - recoilYawView) * recoilBlend;
    FrameView view;
    view.x = viewX;
    view.y = viewY;
    view.z = viewZ;
    view.eye = eyeView;
    view.yaw = input.yaw() + recoilYawView;
    view.pitch = std::clamp(input.pitch() + recoilView, -1.4f, 1.4f);
    view.seconds = float(now) / 1000;
    view.firing = now < shotUntil;
    view.moving = captured && input.walking();
    renderer->render(match.map(), match.snapshot(), match.playerId(), view,
                     QSize(int(width() * devicePixelRatioF()), int(height() * devicePixelRatioF())),
                     defaultFramebufferObject());
}

void GameWidget::paintGL() {
    const bool inMatch =
        (screen == Screen::Playing || screen == Screen::Finished) && haveView && match.hasMap();
    QPainter painter(this);
    if (inMatch && rendererReady()) {
        painter.beginNativePainting();
        renderWorld();
        painter.endNativePainting();
    }
    if (screen == Screen::Menu || screen == Screen::Connecting || screen == Screen::Queued) {
        ui::paintMenu(painter, size(), screen != Screen::Menu, status, clock.elapsed());
    } else if (!rendererReady()) {
        painter.fillRect(rect(), QColor(12, 18, 15));
        painter.setPen(theme::orange);
        painter.setFont(theme::mono(14));
        painter.drawText(rect().adjusted(60, 60, -60, -60), Qt::TextWordWrap,
                         "OPENGL INITIALIZATION FAILED\n" +
                             (renderer ? renderer->error() : QString("No OpenGL context")));
    } else if (inMatch) {
        if (clock.elapsed() < damageUntil)
            painter.fillRect(rect(), QColor(150, 30, 12, 60));
        ui::HudView hud{match,
                        viewX,
                        viewY,
                        viewZ,
                        input.yaw(),
                        captured,
                        input.held(Qt::Key_Tab) || screen == Screen::Finished,
                        screen == Screen::Finished};
        const qint64 now = clock.elapsed();
        const float halfFov = kVerticalFieldOfView * kPi / 360;
        hud.crosshairGap = std::tan(float(number(match.self(), "spread"))) / std::tan(halfFov) * height() / 2;
        hud.hitFade = std::max(0.f, 1 - float(now - hitAt) / kHitMarkerMs);
        hud.hitHead = hitHead;
        hud.hitKill = hitKill;
        hud.hurtFade = std::max(0.f, 1 - float(now - hurtAt) / kDamageDirectionMs);
        hud.hurtAngle = std::remainder(hurtDir - input.yaw(), 2 * kPi);
        ui::paintHud(painter, size(), hud);
    } else {
        painter.fillRect(rect(), Qt::black);
    }
}
