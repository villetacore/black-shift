#include "ui/RoomPanel.h"
#include <QApplication>
#include <QClipboard>
#include <QComboBox>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QLabel>
#include <QPushButton>
#include <QSignalBlocker>
#include <QVBoxLayout>
RoomPanel::RoomPanel(QWidget *parent) : QWidget(parent) {
    setObjectName("roomPanel");
    setAttribute(Qt::WA_StyledBackground, true);
    setStyleSheet(
        "QWidget#roomPanel{background:#111e22;border:1px solid #36535b;} QLabel{color:#dbe6e2;font:13px "
        "'Consolas';border:0;} "
        "QPushButton,QComboBox{background:#263b40;color:#dbe6e2;padding:12px;border:1px solid "
        "#48616a;font:13px 'Consolas';} QPushButton:hover{background:#355159;} "
        "QPushButton:disabled{color:#6c7d80;} QPushButton#ready{background:#65dcd0;color:#102326;}");
    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(28, 24, 28, 24);
    layout->setSpacing(18);
    codeLabel = new QLabel(this);
    codeLabel->setStyleSheet("font:bold 22px 'Consolas';color:#65dcd0;");
    codeLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
    layout->addWidget(codeLabel);
    layout->addWidget(new QLabel("Share the code and server address. Empty slots become bots.", this));
    auto *teams = new QHBoxLayout;
    cyan = new QLabel(this);
    amber = new QLabel(this);
    cyan->setMinimumHeight(170);
    amber->setMinimumHeight(170);
    cyan->setAlignment(Qt::AlignTop);
    amber->setAlignment(Qt::AlignTop);
    teams->addWidget(cyan);
    teams->addWidget(amber);
    layout->addLayout(teams);
    auto *choices = new QHBoxLayout;
    teamBox = new QComboBox(this);
    teamBox->addItems({"CYAN", "AMBER"});
    classBox = new QComboBox(this);
    classBox->addItems({"RANGER / SM-9", "WARDEN / SG-12"});
    choices->addWidget(teamBox);
    choices->addWidget(classBox);
    layout->addLayout(choices);
    connect(teamBox, &QComboBox::currentIndexChanged, this,
            [this](int team) { emit action({{"type", "room_action"}, {"action", "team"}, {"team", team}}); });
    connect(classBox, &QComboBox::currentIndexChanged, this, [this](int index) {
        emit action(
            {{"type", "room_action"}, {"action", "class"}, {"class", index == 0 ? "ranger" : "warden"}});
    });
    auto *buttons = new QHBoxLayout;
    readyButton = new QPushButton("READY", this);
    readyButton->setObjectName("ready");
    startButton = new QPushButton("START WITH BOTS", this);
    startButton->setObjectName("startMatch");
    auto *leave = new QPushButton("LEAVE", this);
    buttons->addWidget(readyButton);
    buttons->addWidget(startButton);
    buttons->addWidget(leave);
    layout->addLayout(buttons);
    connect(readyButton, &QPushButton::clicked, this,
            [this] { emit action({{"type", "room_action"}, {"action", "ready"}, {"ready", !ready}}); });
    connect(startButton, &QPushButton::clicked, this,
            [this] { emit action({{"type", "room_action"}, {"action", "start"}}); });
    connect(leave, &QPushButton::clicked, this, &RoomPanel::leaveRequested);
    message = new QLabel(this);
    message->setWordWrap(true);
    message->setMinimumHeight(50);
    layout->addWidget(message);
}
void RoomPanel::showError(const QString &text) {
    message->setText(text);
}
void RoomPanel::updateRoom(const QJsonObject &room, const QString &selfId, const QString &result) {
    codeLabel->setText(QString("ROOM %1 / ROUND %2").arg(room["code"].toString()).arg(room["round"].toInt()));
    QString lists[2] = {"<b style='color:#65dcd0'>CYAN</b><br><br>",
                        "<b style='color:#f1974b'>AMBER</b><br><br>"};
    int counts[2] = {0, 0};
    bool allReady = true;
    for (const auto v : room["players"].toArray()) {
        const auto p = v.toObject();
        const int team = p["team"].toInt();
        if (team < 0 || team > 1)
            continue;
        counts[team]++;
        const bool isReady = p["ready"].toBool();
        allReady &= isReady;
        lists[team] += QString("%1 %2%3<br><small>%4</small><br><br>")
                           .arg(isReady ? "&#10003;" : "&#9675;", p["name"].toString().toHtmlEscaped(),
                                p["id"] == room["host"] ? " [HOST]" : "", p["class"].toString().toUpper());
        if (p["id"].toString() == selfId) {
            ready = isReady;
            QSignalBlocker a(teamBox), b(classBox);
            teamBox->setCurrentIndex(team);
            classBox->setCurrentIndex(p["class"].toString() == "warden" ? 1 : 0);
        }
    }
    for (int team = 0; team < 2; team++)
        for (int i = counts[team]; i < 3; i++)
            lists[team] += "<span style='color:#819699'>+ BOT SLOT</span><br><br>";
    cyan->setText(lists[0]);
    amber->setText(lists[1]);
    readyButton->setText(ready ? "NOT READY" : "READY");
    const bool host = room["host"].toString() == selfId;
    startButton->setEnabled(host && allReady);
    startButton->setText(room["round"].toInt() > 1 ? "START REMATCH" : "START WITH BOTS");
    message->setText(!result.isEmpty()
                         ? result
                         : (host ? "All human players must be ready. You can start with any number of humans."
                                 : "The host starts the match once everyone is ready."));
}
