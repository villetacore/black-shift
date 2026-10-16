#include "audio/AudioEngine.h"
#include <QAudioDevice>
#include <QAudioSink>
#include <QDebug>
#include <QFile>
#include <QJsonArray>
#include <QMediaDevices>
#include <QMutexLocker>
#include <QtEndian>
#include <algorithm>
#include <cmath>
#include <cstring>

AudioEngine::AudioEngine(QObject *parent, bool enableDevice) : QIODevice(parent) {
    for (const auto *name : {"smg", "shotgun", "step", "reload", "hit", "kill", "hurt", "dash", "pulse",
                             "relay", "warning", "victory"}) {
        QFile file(QString(":/audio/%1.wav").arg(name));
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const auto wav = file.readAll();
        if (wav.size() < 44 || wav.mid(0, 4) != "RIFF" || wav.mid(36, 4) != "data")
            continue;
        std::vector<float> samples;
        for (qsizetype i = 44; i + 1 < wav.size(); i += 2)
            samples.push_back(qFromLittleEndian<qint16>(wav.constData() + i) / 32768.f);
        clips.insert(name, std::move(samples));
    }
    open(QIODevice::ReadOnly | QIODevice::Unbuffered);
    if (!enableDevice)
        return;
    const auto device = QMediaDevices::defaultAudioOutput();
    QAudioFormat format;
    format.setSampleRate(44100);
    format.setChannelCount(2);
    format.setSampleFormat(QAudioFormat::Int16);
    if (device.isNull()) {
        qWarning() << "Audio: no output device";
        return;
    }
    if (!device.isFormatSupported(format)) {
        format.setSampleRate(device.preferredFormat().sampleRate());
        if (!device.isFormatSupported(format))
            format.setSampleFormat(QAudioFormat::Float);
    }
    if (!device.isFormatSupported(format)) {
        qWarning() << "Audio: no compatible stereo output" << device.description();
        return;
    }
    sampleStep = 44100.0 / format.sampleRate();
    floatOutput = format.sampleFormat() == QAudioFormat::Float;
    sink = std::make_unique<QAudioSink>(device, format);
    sink->setBufferSize(8192);
    sink->start(this);
}
AudioEngine::~AudioEngine() {
    if (sink)
        sink->stop();
}
void AudioEngine::setVolume(float value) {
    QMutexLocker lock(&mutex);
    volume = std::clamp(value, 0.f, 1.f);
}
void AudioEngine::clearEvents() {
    QMutexLocker lock(&mutex);
    voices = {};
    previous = {};
    stepDistance.clear();
}
void AudioEngine::play(const QString &name, float gain, float pan) {
    const auto it = clips.constFind(name);
    if (it == clips.cend() || it.value().empty() || gain < .01f)
        return;
    QMutexLocker lock(&mutex);
    auto voice = std::find_if(voices.begin(), voices.end(), [](const Voice &v) { return !v.samples; });
    if (voice == voices.end())
        return;
    pan = std::clamp(pan, -1.f, 1.f);
    *voice = {&it.value(), 0, gain * std::sqrt((1 - pan) * .5f), gain * std::sqrt((1 + pan) * .5f)};
}
qint64 AudioEngine::readData(char *data, qint64 size) {
    QMutexLocker lock(&mutex);
    const int frameBytes = floatOutput ? 8 : 4;
    const qint64 bytes = size - size % frameBytes;
    for (qint64 i = 0; i < bytes; i += frameBytes) {
        float left = 0, right = 0;
        for (auto &voice : voices) {
            if (!voice.samples)
                continue;
            const auto index = size_t(voice.cursor);
            const float fraction = float(voice.cursor - index);
            const float a = (*voice.samples)[index];
            const float b = (*voice.samples)[std::min(index + 1, voice.samples->size() - 1)];
            const float sample = a + (b - a) * fraction;
            voice.cursor += sampleStep;
            left += sample * voice.left;
            right += sample * voice.right;
            if (voice.cursor >= voice.samples->size())
                voice.samples = nullptr;
        }
        if (floatOutput) {
            const float l = std::tanh(left * volume), r = std::tanh(right * volume);
            std::memcpy(data + i, &l, 4);
            std::memcpy(data + i + 4, &r, 4);
        } else {
            const qint16 l = qint16(std::tanh(left * volume) * 32767);
            const qint16 r = qint16(std::tanh(right * volume) * 32767);
            std::memcpy(data + i, &l, 2);
            std::memcpy(data + i + 2, &r, 2);
        }
    }
    return bytes;
}
void AudioEngine::update(const QJsonObject &snapshot, const QString &selfId, float yaw) {
    if (previous.isEmpty()) {
        previous = snapshot;
        return;
    }
    if (snapshot["tick"].toInt() <= previous["tick"].toInt())
        return;
    QHash<QString, QJsonObject> old;
    for (const auto v : previous["players"].toArray())
        old.insert(v.toObject()["id"].toString(), v.toObject());
    QJsonObject self;
    for (const auto v : snapshot["players"].toArray())
        if (v.toObject()["id"].toString() == selfId)
            self = v.toObject();
    if (self.isEmpty()) {
        previous = snapshot;
        return;
    }
    for (const auto v : snapshot["players"].toArray()) {
        const auto p = v.toObject();
        const auto id = p["id"].toString();
        if (!old.contains(id))
            continue;
        const auto before = old.value(id);
        const bool local = id == selfId;
        const float dx = float(p["x"].toDouble() - self["x"].toDouble());
        const float dy = float(p["y"].toDouble() - self["y"].toDouble());
        const float dz = float(p["z"].toDouble() - self["z"].toDouble());
        const float distance = std::sqrt(dx * dx + dy * dy + dz * dz);
        const float gain = local ? .85f : std::max(0.f, 1 - distance / 24) / (1 + distance * .13f);
        const float pan =
            local || distance < .1f ? 0.f : (-std::sin(yaw) * dx + std::cos(yaw) * dy) / distance;
        if (p["fire_at"].toInt() > before["fire_at"].toInt())
            play(p["class"].toString() == "warden" ? "shotgun" : "smg", gain, pan);
        if (p["hp"].toInt() <= 0 || before["hp"].toInt() <= 0) {
            stepDistance.remove(id);
            continue;
        }
        if (p["reload"].toDouble() > 0 && before["reload"].toDouble() <= 0)
            play("reload", gain * .6f, pan);
        if (p["cooldown"].toDouble() > before["cooldown"].toDouble() + 1)
            play(p["class"].toString() == "warden" ? "pulse" : "dash", gain, pan);
        const float moved = std::hypot(float(p["x"].toDouble() - before["x"].toDouble()),
                                       float(p["y"].toDouble() - before["y"].toDouble()));
        if (p["grounded"].toBool() && moved < 1 && p["immersion"].toDouble() < .5) {
            stepDistance[id] += moved;
            if (stepDistance[id] > (p["sprinting"].toBool() ? 1.8f : 1.3f)) {
                stepDistance[id] = 0;
                play("step", gain * (p["crouching"].toBool() ? .12f : .4f), pan);
            }
        }
    }
    const auto before = old.value(selfId);
    if (!before.isEmpty()) {
        if (self["hits"].toInt() > before["hits"].toInt())
            play(self["hit_kill"].toBool() ? "kill" : "hit", .65f);
        if (self["hurt_at"].toInt() > before["hurt_at"].toInt())
            play("hurt", .55f);
    }
    const auto objective = snapshot["objective"].toObject();
    const auto oldObjective = previous["objective"].toObject();
    if (objective["name"] != oldObjective["name"] ||
        (snapshot.contains("relay") && snapshot["relay"].toInt() >= 0 &&
         snapshot.value("relay") != previous.value("relay")))
        play("relay", .6f);
    if (objective["remaining"].toInt() <= 15 && oldObjective["remaining"].toInt() > 15)
        play("warning", .6f);
    if (snapshot["over"].toBool() && !previous["over"].toBool())
        play("victory", .7f);
    previous = snapshot;
}
