#include "app/GameWidget.h"
#include <QApplication>
#include <QCommandLineParser>
#include <QTimer>
#include <cstdio>

namespace {
// Exit codes for capture modes.
constexpr int kNoMatch = 2, kSaveFailed = 3;
} // namespace

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    app.setApplicationName("Black Shift");
    app.setApplicationVersion(BLACKSHIFT_VERSION);
    QCommandLineParser parser;
    parser.setApplicationDescription("BLACK SHIFT // arena prototype");
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addOption({"server", "Server host:port", "address", "127.0.0.1:7777"});
    parser.addOption({"name", "Operator name", "name", "Operator"});
    parser.addOption({"role", "ranger or warden", "role", "ranger"});
    parser.addOption({"practice", "Immediately join a practice match"});
    parser.addOption({"online", "Immediately join the online queue"});
    parser.addOption({"screenshot", "Save a screenshot after 3 seconds, then exit (requires match)", "path"});
    parser.addOption({"menu-screenshot", "Save the deployment menu, then exit", "path"});
    parser.process(app);

    GameWidget game;
    if (parser.isSet("screenshot"))
        game.setScreenshotMode();
    game.resize(1280, 800);
    game.setWindowTitle("BLACK SHIFT — Relay conflict");
    game.show();

    if (parser.isSet("menu-screenshot"))
        QTimer::singleShot(300, &game, [&] {
            app.exit(game.grab().save(parser.value("menu-screenshot")) ? 0 : kSaveFailed);
        });
    if (parser.isSet("practice") || parser.isSet("online"))
        QTimer::singleShot(100, &game, [&] {
            game.autoConnect(parser.value("server"), parser.value("name"), parser.value("role"),
                             parser.isSet("practice") ? "practice" : "online");
        });
    if (parser.isSet("screenshot"))
        QTimer::singleShot(3500, &game, [&] {
            if (!game.hasSnapshot() || !game.rendererReady()) {
                std::fprintf(stderr, "No match snapshot received\n");
                app.exit(kNoMatch);
                return;
            }
            app.exit(game.grabFramebuffer().save(parser.value("screenshot")) ? 0 : kSaveFailed);
        });
    return app.exec();
}
