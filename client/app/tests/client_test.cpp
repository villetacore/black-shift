#include "app/GameWidget.h"
#include "render/SceneRenderer.h"
#include <QCoreApplication>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFunctions>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QScopeGuard>
#include <QTemporaryDir>
#include <QtTest>

class ClientTest : public QObject {
    Q_OBJECT
  private slots:
    void animationFollowsConfirmedShotsAndDeath() {
        ActorAnimator animator;
        QJsonObject p{{"id", "test"}, {"hp", 100}, {"grounded", true}, {"fire_at", 5}};
        QVERIFY(animator.update(p, {}, .05f).recoil > .9f);
        QVERIFY(animator.update(p, {}, .05f).recoil < .6f);
        p["fire_at"] = 10;
        QVERIFY(animator.update(p, {}, .05f).recoil > .9f);
        p["hp"] = 0;
        QVERIFY(animator.update(p, {}, .1f).death > 0.f);
        p["hp"] = 100;
        QCOMPARE(animator.update(p, {}, .1f).death, 0.f);
    }
    void inputReachesAuthoritativeServer() {
        const auto executable = qEnvironmentVariable("BLACKSHIFT_SERVER");
        QVERIFY2(!executable.isEmpty(), "Set BLACKSHIFT_SERVER to the server executable");
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        QProcess server;
        server.setProcessChannelMode(QProcess::MergedChannels);
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.insert("BS_BIND", "127.0.0.1");
        environment.insert("BS_PORT", "0");
        environment.insert("BS_DB_DIR", directory.filePath("mnesia"));
        environment.insert("RELEASE_NODE",
                           QString("bs_test_%1@localhost").arg(QCoreApplication::applicationPid()));
        auto command = [&](QProcess &process, const QString &operation) {
            process.setProcessEnvironment(environment);
#ifdef Q_OS_WIN
            process.setProgram(qEnvironmentVariable("COMSPEC", "cmd.exe"));
            process.setNativeArguments("/d /s /c \"\"" + executable + "\" " + operation + "\"");
#else
            process.setProgram(executable);
            process.setArguments({operation});
#endif
            process.start();
        };
        command(server, "start");
        auto cleanup = qScopeGuard([&] {
            QProcess stopper;
            command(stopper, "stop");
            stopper.waitForFinished(10000);
            if (!server.waitForFinished(5000)) {
                server.kill();
                server.waitForFinished();
            }
        });
        QVERIFY(server.waitForStarted());
        QByteArray logs;
        QRegularExpression endpoint("127\\.0\\.0\\.1:(\\d+)");
        QTRY_VERIFY_WITH_TIMEOUT(
            (logs += server.readAll(), endpoint.match(QString::fromUtf8(logs)).hasMatch()), 10000);

        GameWidget game;
        game.setScreenshotMode();
        game.resize(1280, 800);
        game.show();
        game.activateWindow();
        QTRY_VERIFY_WITH_TIMEOUT(game.isValid(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(game.rendererReady(), 5000);
        game.autoConnect(endpoint.match(QString::fromUtf8(logs)).captured(0), "QA", "ranger", "practice");
        QTRY_VERIFY_WITH_TIMEOUT(game.hasSnapshot(), 5000);
        if (!qEnvironmentVariable("BLACKSHIFT_TEST_SCREENSHOT").isEmpty()) {
            QTest::qWait(500);
            QVERIFY(game.grabFramebuffer().save(qEnvironmentVariable("BLACKSHIFT_TEST_SCREENSHOT")));
        }
        const double initialX = game.localPlayer()["x"].toDouble();

        QTest::keyClick(&game, Qt::Key_Space);
        QTRY_VERIFY(game.localPlayer()["z"].toDouble() > 0.2);
        QTRY_VERIFY(game.localPlayer()["grounded"].toBool());

        QTest::keyPress(&game, Qt::Key_W);
        QTest::qWait(300);
        QTest::keyRelease(&game, Qt::Key_W);
        QTRY_VERIFY(game.localPlayer()["x"].toDouble() > initialX + 0.4);

        const double beforeDash = game.localPlayer()["x"].toDouble();
        QTest::keyClick(&game, Qt::Key_Q);
        QTRY_VERIFY(game.localPlayer()["cooldown"].toDouble() > 0);
        // The dash is a burst of velocity over the following ticks, not a teleport.
        QTRY_VERIFY(game.localPlayer()["x"].toDouble() > beforeDash + 1.5);

        // Releasing focus sends neutral input; after a short slide the simulation must not keep walking.
        QTest::keyPress(&game, Qt::Key_W);
        QTest::qWait(100);
        QTest::keyClick(&game, Qt::Key_Escape);
        QTest::qWait(450);
        const double stoppedX = game.localPlayer()["x"].toDouble();
        QTest::qWait(200);
        QVERIFY(std::abs(game.localPlayer()["x"].toDouble() - stoppedX) < 0.02);

        // Capture expensive static previews after the live input assertions.
        if (!qEnvironmentVariable("BLACKSHIFT_MAP_PREVIEW").isEmpty()) {
            game.makeCurrent();
            {
                // Static views of the layered districts, rendered without a snapshot.
                SceneRenderer preview;
                QVERIFY(preview.initialize());
                QOpenGLFramebufferObject target(QSize(1280, 800),
                                                QOpenGLFramebufferObject::CombinedDepthStencil);
                QVERIFY(target.isValid());
                const auto path = qEnvironmentVariable("BLACKSHIFT_MAP_PREVIEW");
                const struct {
                    FrameView view;
                    QString suffix;
                } shots[] = {{{32.5f, 29.5f, .4f, -.65f, .05f}, ""},
                             {{38.5f, 6.5f, 1.2f, .3f, 0.f}, ".pump.png"},
                             {{28.5f, 37.5f, 0.f, 0.f, 0.f}, ".service.png"},
                             {{30.5f, 22.f, 3.f, 0.f, -.08f}, ".gallery.png"},
                             {{49.f, 36.f, 0.f, .3f, 0.f}, ".loading.png"},
                             {{37.f, 2.f, 1.6f, 3.14f, -.40f}, ".water.png"},
                             {{32.f, 2.f, .1f, 0.f, .1f}, ".underwater.png"},
                             {{57.f, 17.5f, 0.f, -1.57f, 0.f}, ".generator.png"}};
                for (const auto &shot : shots) {
                    preview.render(game.matchState().map(), QJsonObject{}, QString{}, shot.view,
                                   QSize(1280, 800), target.handle());
                    QCOMPARE(QOpenGLContext::currentContext()->functions()->glGetError(),
                             GLenum(GL_NO_ERROR));
                    QVERIFY(target.toImage().save(path + shot.suffix));
                }
            }
            game.doneCurrent();
        }
        QTest::keyClick(&game, Qt::Key_Return);
        QVERIFY(!game.hasSnapshot());
    }
};
QTEST_MAIN(ClientTest)
#include "client_test.moc"
