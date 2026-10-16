#pragma once
#include <QHash>
#include <QIODevice>
#include <QJsonObject>
#include <QMutex>
#include <array>
#include <memory>
#include <vector>
class QAudioSink;
// Bounded stereo mixer; only new authoritative snapshot events produce sounds.
class AudioEngine final : public QIODevice {
  public:
    explicit AudioEngine(QObject *parent = nullptr, bool enableDevice = true);
    ~AudioEngine() override;
    void update(const QJsonObject &snapshot, const QString &selfId, float yaw);
    void clearEvents();
    void setVolume(float volume);
    bool isSequential() const override {
        return true;
    }
    qint64 bytesAvailable() const override {
        return 4096 + QIODevice::bytesAvailable();
    }

  protected:
    qint64 readData(char *data, qint64 size) override;
    qint64 writeData(const char *, qint64) override {
        return -1;
    }

  private:
    struct Voice {
        const std::vector<float> *samples = nullptr;
        double cursor = 0;
        float left = 0, right = 0;
    };
    std::unique_ptr<QAudioSink> sink;
    QHash<QString, std::vector<float>> clips;
    std::array<Voice, 32> voices{};
    QMutex mutex;
    float volume = .7f;
    double sampleStep = 1;
    bool floatOutput = false;
    QJsonObject previous;
    QHash<QString, float> stepDistance;
    void play(const QString &name, float gain = 1, float pan = 0);
};
