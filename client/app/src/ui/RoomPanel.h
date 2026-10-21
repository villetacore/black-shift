#pragma once
#include <QJsonObject>
#include <QWidget>
class QLabel;
class QPushButton;
class QComboBox;
class RoomPanel final : public QWidget {
    Q_OBJECT
  public:
    explicit RoomPanel(QWidget *parent = nullptr);
    void updateRoom(const QJsonObject &room, const QString &selfId, const QString &result = QString());
    void showError(const QString &text);
  signals:
    void action(const QJsonObject &message);
    void leaveRequested();

  private:
    QLabel *codeLabel, *cyan, *amber, *message;
    QPushButton *readyButton, *startButton;
    QComboBox *teamBox, *classBox;
    bool ready = false;
};
