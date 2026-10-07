#pragma once
#include <QByteArray>
#include <QJsonObject>
#include <QObject>
#include <QTcpSocket>
#include <QTimer>
#include <optional>

struct Endpoint {
    QString host;
    quint16 port = 0;
};

// Parses "host" or "host:port". On failure returns nullopt and sets `error`.
std::optional<Endpoint> parseEndpoint(const QString &text, QString *error);

// TCP connection to the game server: JSON Lines framing, connect timeout and keep-alive pings.
class ServerConnection final : public QObject {
    Q_OBJECT

  public:
    explicit ServerConnection(QObject *parent = nullptr);
    ~ServerConnection() override;

    void open(const Endpoint &endpoint);
    // Closes without emitting failed()/closedByServer().
    void close();
    void send(const QJsonObject &message);

  signals:
    void connected();
    void message(const QJsonObject &message);
    // Socket errors, timeouts and malformed server data.
    void failed(const QString &reason);
    // The server closed an established connection.
    void closedByServer();

  private:
    QTcpSocket socket;
    QTimer connectTimeout, heartbeat;
    QByteArray incoming;
    bool closing = false;
    quint64 generation = 0;

    void receive();
};
