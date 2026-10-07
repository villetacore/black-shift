#pragma once
#include <QWidget>

class QComboBox;
class QLabel;
class QLineEdit;

// Main-menu form: callsign, server address, loadout and the two join buttons.
class DeploymentPanel final : public QWidget {
    Q_OBJECT

  public:
    explicit DeploymentPanel(QWidget *parent = nullptr);

    QString callsign() const;
    QString address() const;
    // "ranger" or "warden".
    QString role() const;
    void setValues(const QString &address, const QString &callsign, const QString &role);
    // Shows an error, or the default footer when `message` is empty.
    void showMessage(const QString &message);

  signals:
    // "online" or "practice".
    void joinRequested(const QString &mode);

  private:
    QLineEdit *addressEdit = nullptr;
    QLineEdit *callsignEdit = nullptr;
    QComboBox *roleBox = nullptr;
    QLabel *messageLabel = nullptr;
};
