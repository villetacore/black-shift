#include "ui/DeploymentPanel.h"
#include <QComboBox>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QVBoxLayout>

namespace {
const char *kDefaultMessage = "SERVER-AUTHORITATIVE // PROTOCOL 01";
constexpr int kMaxCallsign = 20;

const char *kStyle =
    "QWidget#panel{background:#121b18;border:1px solid #34453c;} QLabel{color:#91a297;font:11px "
    "'Consolas';border:0;} QLineEdit,QComboBox{background:#0b110f;border:1px solid "
    "#3a4d42;color:#dedfce;padding:11px;font:14px 'Consolas';} "
    "QLineEdit:focus,QComboBox:focus{border-color:#78d8c5;} "
    "QPushButton{background:#c1d5a0;color:#111910;border:0;padding:15px;font:bold 14px "
    "'Consolas';text-align:left;} QPushButton:hover{background:#d8efb2;} "
    "QPushButton#secondary{background:#23322b;color:#bccbc0;border:1px solid #425b49;} "
    "QPushButton#secondary:hover{background:#314739;}";
} // namespace

DeploymentPanel::DeploymentPanel(QWidget *parent) : QWidget(parent) {
    setObjectName("panel");
    // QWidget subclasses only paint style-sheet backgrounds with this attribute.
    setAttribute(Qt::WA_StyledBackground, true);
    setStyleSheet(kStyle);
    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(24, 24, 24, 24);
    layout->setSpacing(10);
    auto *title = new QLabel("01 / DEPLOYMENT TERMINAL", this);
    title->setStyleSheet("color:#a7d194;font:bold 13px 'Consolas';");
    layout->addWidget(title);
    layout->addSpacing(10);
    layout->addWidget(new QLabel("CALLSIGN", this));
    callsignEdit = new QLineEdit("Operator", this);
    callsignEdit->setMaxLength(kMaxCallsign);
    layout->addWidget(callsignEdit);
    layout->addWidget(new QLabel("SERVER / TCP", this));
    addressEdit = new QLineEdit("127.0.0.1:7777", this);
    layout->addWidget(addressEdit);
    layout->addWidget(new QLabel("LOADOUT", this));
    roleBox = new QComboBox(this);
    roleBox->addItem("RANGER / SM-9 + PHASE DASH", "ranger");
    roleBox->addItem("WARDEN / SG-12 + FIELD PULSE", "warden");
    roleBox->setToolTip(
        "Ranger: Q dash, then +25% speed for 1s.\nWarden: Q heal / Shift+Q attack. Shared 8s cooldown.");
    layout->addWidget(roleBox);
    layout->addSpacing(10);
    auto *online = new QPushButton("FIND MATCH                         >", this);
    layout->addWidget(online);
    auto *practice = new QPushButton("TRAINING / 3 BOTS                   >", this);
    practice->setObjectName("secondary");
    layout->addWidget(practice);
    messageLabel = new QLabel(kDefaultMessage, this);
    messageLabel->setWordWrap(true);
    messageLabel->setMinimumHeight(40);
    layout->addWidget(messageLabel);
    connect(online, &QPushButton::clicked, this, [this] { emit joinRequested("online"); });
    connect(practice, &QPushButton::clicked, this, [this] { emit joinRequested("practice"); });
}

QString DeploymentPanel::callsign() const {
    return callsignEdit->text();
}

QString DeploymentPanel::address() const {
    return addressEdit->text();
}

QString DeploymentPanel::role() const {
    return roleBox->currentData().toString();
}

void DeploymentPanel::setValues(const QString &address, const QString &callsign, const QString &role) {
    addressEdit->setText(address);
    callsignEdit->setText(callsign);
    roleBox->setCurrentIndex(role == "warden" ? 1 : 0);
}

void DeploymentPanel::showMessage(const QString &message) {
    messageLabel->setText(message.isEmpty() ? kDefaultMessage : message);
}
