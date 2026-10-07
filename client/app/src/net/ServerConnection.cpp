#include "net/ServerConnection.h"
#include "net/Protocol.h"
#include <QJsonDocument>

namespace {
constexpr int kConnectTimeoutMs = 8000;
// The server drops connections that stay silent for 15 seconds.
constexpr int kHeartbeatMs = 4000;
} // namespace

std::optional<Endpoint> parseEndpoint(const QString &text, QString *error) {
    Endpoint endpoint{text.trimmed(), protocol::kDefaultPort};
    const int split = endpoint.host.lastIndexOf(':');
    if (split >= 0) {
        bool ok = false;
        const int port = endpoint.host.mid(split + 1).toInt(&ok);
        if (!ok || port < 1 || port > 65535) {
            *error = "Invalid port.";
            return std::nullopt;
        }
        endpoint.port = quint16(port);
        endpoint.host = endpoint.host.left(split);
    }
    if (endpoint.host.isEmpty()) {
        *error = "Enter a server address.";
        return std::nullopt;
    }
    return endpoint;
}

ServerConnection::ServerConnection(QObject *parent) : QObject(parent) {
    connectTimeout.setSingleShot(true);
    connect(&connectTimeout, &QTimer::timeout, this, [this] {
        close();
        emit failed("Connection timed out.");
    });
    connect(&socket, &QTcpSocket::connected, this, [this] {
        connectTimeout.stop();
        emit connected();
    });
    connect(&socket, &QTcpSocket::readyRead, this, &ServerConnection::receive);
    connect(&socket, &QTcpSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        if (!closing)
            emit failed(socket.errorString());
    });
    connect(&socket, &QTcpSocket::disconnected, this, [this] {
        if (!closing)
            emit closedByServer();
    });
    connect(&heartbeat, &QTimer::timeout, this, [this] { send(protocol::ping()); });
    heartbeat.start(kHeartbeatMs);
}

// Destroying a connected socket aborts it; that must not reach handlers of a half-destroyed owner.
ServerConnection::~ServerConnection() {
    closing = true;
    socket.abort();
}

void ServerConnection::open(const Endpoint &endpoint) {
    close();
    socket.connectToHost(endpoint.host, endpoint.port);
    connectTimeout.start(kConnectTimeoutMs);
}

void ServerConnection::close() {
    closing = true;
    socket.abort();
    closing = false;
    connectTimeout.stop();
    incoming.clear();
    ++generation;
}

void ServerConnection::send(const QJsonObject &message) {
    if (socket.state() != QAbstractSocket::ConnectedState)
        return;
    socket.write(QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n');
}

void ServerConnection::receive() {
    incoming += socket.readAll();
    if (incoming.size() > protocol::kMaxIncomingBytes) {
        close();
        emit failed("Server message too large.");
        return;
    }
    // A message handler may close the connection; drop the rest of the buffer if it does.
    const quint64 session = generation;
    while (session == generation) {
        const int newline = incoming.indexOf('\n');
        if (newline < 0)
            break;
        const QByteArray line = incoming.left(newline);
        incoming.remove(0, newline + 1);
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(line, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            close();
            emit failed("Invalid server message.");
            return;
        }
        emit message(document.object());
    }
}
