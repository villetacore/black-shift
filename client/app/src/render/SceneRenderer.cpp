#include "render/SceneRenderer.h"
#include "game/Json.h"
#include "render/Models.h"
#include "render/WorldMesh.h"
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QOpenGLFramebufferObject>
#include <QOpenGLShaderProgram>
#include <QQuaternion>
#include <algorithm>
#include <cmath>
#include <cstddef>

using json::real;

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kFieldOfView = kVerticalFieldOfView, kNearPlane = 0.075f, kFarPlane = 100.f;
// Painted material sheet: 4×4 tiles, each reduced to period-appropriate detail.
constexpr int kSheetColumns = 4, kMaterialTextureSize = 128;
const char *kMaterialSheet = ":/textures/painted-materials.png";

QVector3D teamColor(int team) {
    return team == 0 ? QVector3D(0.29f, 0.9f, 0.85f) : QVector3D(1.f, 0.42f, 0.16f);
}

QString readResource(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
}

bool linkProgram(QOpenGLShaderProgram &program, const char *vertex, const char *fragment, QString *failure) {
    if (!program.addShaderFromSourceCode(QOpenGLShader::Vertex, readResource(vertex)) ||
        !program.addShaderFromSourceCode(QOpenGLShader::Fragment, readResource(fragment)) ||
        !program.link()) {
        *failure = program.log();
        return false;
    }
    return true;
}

// Degrees for QMatrix4x4::rotate from a yaw in radians (map yaw turns the other way around +Y).
float yawDegrees(float yaw) {
    return -yaw * 180 / kPi;
}

} // namespace

SceneRenderer::SceneRenderer() = default;

SceneRenderer::~SceneRenderer() {
    if (!initialized)
        return;
    for (auto &mesh : models)
        destroy(mesh);
    destroy(world);
    destroy(screenQuad);
    destroy(actorMesh);
    destroy(liquidMesh);
    glDeleteTextures(1, &waterTexture);
    glDeleteTextures(BS_MATERIAL_COUNT, textures.data());
}

bool SceneRenderer::initialize() {
    initializeOpenGLFunctions();
    if (!loadShaders())
        return false;
    for (int model = 0; model < BS_MODEL_COUNT; model++) {
        const auto vertices = modelVertices(BsModel(model));
        if (vertices.empty()) {
            failure = "Rust 3D mesh export failed";
            return false;
        }
        upload(models[size_t(model)], vertices, GL_STATIC_DRAW);
    }
    actorVertices.resize(size_t(bs_actor_vertex_count()));
    if (!loadTextures())
        return false;
    std::vector<BsVertex> quad(6);
    const float corners[6][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, -1}, {1, 1}, {-1, 1}};
    for (size_t i = 0; i < quad.size(); i++) {
        quad[i].position[0] = corners[i][0];
        quad[i].position[1] = corners[i][1];
        quad[i].uv[0] = (corners[i][0] + 1) / 2;
        quad[i].uv[1] = (corners[i][1] + 1) / 2;
    }
    upload(screenQuad, quad, GL_STATIC_DRAW);
    initialized = true;
    return true;
}

bool SceneRenderer::loadShaders() {
    shader = std::make_unique<QOpenGLShaderProgram>();
    presentShader = std::make_unique<QOpenGLShaderProgram>();
    skyShader = std::make_unique<QOpenGLShaderProgram>();
    return linkProgram(*skyShader, ":/shaders/present.vert", ":/shaders/sky.frag", &failure) &&
           linkProgram(*shader, ":/shaders/world.vert", ":/shaders/world.frag", &failure) &&
           linkProgram(*presentShader, ":/shaders/present.vert", ":/shaders/present.frag", &failure);
}

// One texture per material, each with its own mip chain, so filtering never bleeds between tiles.
bool SceneRenderer::loadTextures() {
    const QImage painted(kMaterialSheet);
    if (painted.isNull()) {
        failure = "Missing painted material resource";
        return false;
    }
    const QImage water = QImage(":/textures/cooling-water.bmp").convertToFormat(QImage::Format_RGBA8888);
    if (water.isNull()) {
        failure = "Missing water material";
        return false;
    }
    glGenTextures(1, &waterTexture);
    glBindTexture(GL_TEXTURE_2D, waterTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, water.width(), water.height(), 0, GL_RGBA, GL_UNSIGNED_BYTE,
                 water.constBits());
    glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glGenTextures(BS_MATERIAL_COUNT, textures.data());
    const int tileW = painted.width() / kSheetColumns, tileH = painted.height() / kSheetColumns;
    for (int material = 0; material < BS_MATERIAL_COUNT; material++) {
        const QImage pixels =
            painted.copy((material % kSheetColumns) * tileW, (material / kSheetColumns) * tileH, tileW, tileH)
                .scaled(kMaterialTextureSize, kMaterialTextureSize, Qt::IgnoreAspectRatio,
                        Qt::SmoothTransformation)
                .convertToFormat(QImage::Format_RGBA8888);
        glBindTexture(GL_TEXTURE_2D, textures[size_t(material)]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, kMaterialTextureSize, kMaterialTextureSize, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, pixels.constBits());
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    }
    return true;
}

void SceneRenderer::destroy(Mesh &mesh) {
    if (mesh.vbo)
        glDeleteBuffers(1, &mesh.vbo);
    mesh = {};
}

void SceneRenderer::upload(Mesh &mesh, const std::vector<BsVertex> &vertices, unsigned usage) {
    mesh.count = int(vertices.size());
    mesh.counts.fill(0);
    // Sort whole triangles by material; material is constant across each face.
    std::vector<BsVertex> sorted(vertices.size());
    for (size_t i = 0; i + 2 < vertices.size(); i += 3)
        mesh.counts[size_t(std::clamp(int(vertices[i].material), 0, BS_MATERIAL_COUNT - 1))] += 3;
    int cursor = 0;
    for (int m = 0; m < BS_MATERIAL_COUNT; m++) {
        mesh.starts[size_t(m)] = cursor;
        cursor += mesh.counts[size_t(m)];
    }
    auto offsets = mesh.starts;
    for (size_t i = 0; i + 2 < vertices.size(); i += 3) {
        const auto m = size_t(std::clamp(int(vertices[i].material), 0, BS_MATERIAL_COUNT - 1));
        for (int j = 0; j < 3; j++)
            sorted[size_t(offsets[m]++)] = vertices[i + size_t(j)];
    }
    if (!mesh.vbo)
        glGenBuffers(1, &mesh.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo);
    glBufferData(GL_ARRAY_BUFFER, int(sorted.size() * sizeof(BsVertex)), sorted.data(), usage);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void SceneRenderer::draw(const Mesh &mesh, const QMatrix4x4 &model, const QVector3D &tint, float glow,
                         float brightness, bool baked) {
    if (!mesh.count)
        return;
    shader->setUniformValue("model", model);
    shader->setUniformValue("normalMatrix", model.normalMatrix());
    shader->setUniformValue("teamTint", tint);
    shader->setUniformValue("glow", glow);
    shader->setUniformValue("brightness", brightness);
    shader->setUniformValue("bakedLighting", baked);
    glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo);
    const char *names[] = {"position", "normal", "uv", "material"};
    const int sizes[] = {3, 3, 2, 1};
    const int offsets[] = {int(offsetof(BsVertex, position)), int(offsetof(BsVertex, normal)),
                           int(offsetof(BsVertex, uv)), int(offsetof(BsVertex, material))};
    for (int i = 0; i < 4; i++) {
        const int location = shader->attributeLocation(names[i]);
        shader->enableAttributeArray(location);
        shader->setAttributeBuffer(location, GL_FLOAT, offsets[i], sizes[i], sizeof(BsVertex));
    }
    for (size_t material = 0; material < textures.size(); material++)
        if (mesh.counts[material]) {
            glBindTexture(GL_TEXTURE_2D, drawingLiquid ? waterTexture : textures[material]);
            glDrawArrays(GL_TRIANGLES, mesh.starts[material], mesh.counts[material]);
        }
    for (const auto *name : names)
        shader->disableAttributeArray(shader->attributeLocation(name));
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void SceneRenderer::drawModel(BsModel model, float x, float y, float z, float yaw, const QVector3D &tint) {
    QMatrix4x4 transform;
    transform.translate(x, y, z);
    transform.rotate(yawDegrees(yaw), 0, 1, 0);
    draw(models[size_t(model)], transform, tint);
}

void SceneRenderer::render(const QJsonObject &map, const QJsonObject &snapshot, const QString &playerId,
                           const FrameView &view, const QSize &outputSize, unsigned targetFbo) {
    if (!initialized)
        return;
    time = view.seconds;
    const float dt = std::clamp(time - previousTime, 0.f, 0.1f);
    previousTime = time;
    if (map != currentMap) {
        currentMap = map;
        destroy(world);
        upload(world, buildWorldMesh(map), GL_STATIC_DRAW);
    }
    if (!framebuffer || framebuffer->size() != outputSize) {
        QOpenGLFramebufferObjectFormat format;
        format.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
        framebuffer = std::make_unique<QOpenGLFramebufferObject>(outputSize, format);
        if (!framebuffer->isValid()) {
            initialized = false;
            failure = "Could not allocate OpenGL depth framebuffer";
            return;
        }
    }
    framebuffer->bind();
    glViewport(0, 0, outputSize.width(), outputSize.height());
    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glDepthMask(GL_TRUE);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);
    const auto sky = map["sky_color"].toArray();
    glClearColor(float(sky[0].toDouble(.075)), float(sky[1].toDouble(.095)), float(sky[2].toDouble(.085)),
                 1.f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

    // Render space is (x, height, y).
    const float bob = view.moving ? std::sin(time * 11.f) * 0.024f : 0;
    camera = {view.x, view.z + view.eye + bob, view.y};
    const QVector3D forward(std::cos(view.yaw) * std::cos(view.pitch), std::sin(view.pitch),
                            std::sin(view.yaw) * std::cos(view.pitch));
    QMatrix4x4 viewMatrix;
    viewMatrix.lookAt(camera, camera + forward, {0, 1, 0});
    QMatrix4x4 projection;
    projection.perspective(kFieldOfView, float(outputSize.width()) / outputSize.height(), kNearPlane,
                           kFarPlane);
    drawSky(view, outputSize);
    shader->bind();
    shader->setUniformValue("time", time);
    shader->setUniformValue("liquid", false);
    shader->setUniformValue("viewProjection", projection * viewMatrix);
    shader->setUniformValue("camera", camera);
    shader->setUniformValue("materialTexture", 0);
    glActiveTexture(GL_TEXTURE0);
    draw(world, QMatrix4x4(), teamColor(0), 0, 1, true);

    drawObjective(snapshot);
    drawSupplies(snapshot);
    drawPlayers(snapshot, playerId, dt);
    drawStructures(snapshot);
    drawTracers(snapshot);
    QJsonObject self;
    for (const auto entry : snapshot["players"].toArray())
        if (entry.toObject()["id"].toString() == playerId)
            self = entry.toObject();
    drawLiquids(map);
    if (lastPlayerId != playerId) {
        lastPlayerId = playerId;
        lastFireAt = self["fire_at"].toInt();
        recoil = 0;
    }
    const bool grounded = self["grounded"].toBool(true);
    landingKick *= std::exp(-dt * 14.f);
    if (grounded && !previousGrounded)
        landingKick = .04f;
    previousGrounded = grounded;
    sprintLower += ((self["sprinting"].toBool() ? .075f : 0.f) - sprintLower) * std::min(1.f, dt * 10.f);
    recoil *= std::exp(-dt * 13.f);
    const int fireAt = self["fire_at"].toInt();
    if (fireAt > lastFireAt)
        recoil = 1.f;
    lastFireAt = fireAt;
    if (real(self, "hp") <= 0)
        recoil = 0;
    drawViewModel(self, view, forward, bob);
    shader->release();
    present(outputSize, targetFbo);
}

// A ring of glowing segments with a small beacon: geometry, not billboards.
void SceneRenderer::drawObjective(const QJsonObject &snapshot) {
    const int relay = snapshot["relay"].toInt(-1);
    const auto objective = snapshot["objective"].toObject();
    const float relayX = float(objective.value("x").toDouble(11.5)),
                relayY = float(objective.value("y").toDouble(12.5)), relayZ = real(objective, "z");
    const QVector3D color = relay < 0 ? QVector3D(.6f, .68f, .40f) : teamColor(relay);
    for (int i = 0; i < 24; i++) {
        const float a = float(i) * 2 * kPi / 24;
        QMatrix4x4 segment;
        segment.translate(relayX + std::cos(a) * 1.9f, relayZ + 0.021f, relayY + std::sin(a) * 1.9f);
        segment.rotate(yawDegrees(a), 0, 1, 0);
        segment.scale(0.07f, 0.032f, 0.33f);
        draw(models[BS_MODEL_CUBE], segment, color, .85f);
    }
    QMatrix4x4 beacon;
    beacon.translate(relayX, relayZ + 0.025f, relayY);
    beacon.scale(.18f, .04f, .18f);
    draw(models[BS_MODEL_CUBE], beacon, color, .9f);
}

// Ready health pickups: a box with a glowing cross on top.
void SceneRenderer::drawSupplies(const QJsonObject &snapshot) {
    for (const auto item : snapshot["supplies"].toArray()) {
        const auto supply = item.toObject();
        if (!supply["ready"].toBool())
            continue;
        const float x = real(supply, "x"), y = real(supply, "y");
        QMatrix4x4 kit;
        kit.translate(x, real(supply, "z") + .28f, y);
        kit.scale(.42f, .32f, .42f);
        draw(models[BS_MODEL_CUBE], kit, {.4f, .7f, .4f}, .25f);
        QMatrix4x4 across;
        across.translate(x, real(supply, "z") + .46f, y);
        across.scale(.25f, .02f, .07f);
        draw(models[BS_MODEL_CUBE], across, {.7f, 1.f, .5f}, .85f);
        QMatrix4x4 along;
        along.translate(x, real(supply, "z") + .461f, y);
        along.scale(.07f, .02f, .25f);
        draw(models[BS_MODEL_CUBE], along, {.7f, 1.f, .5f}, .85f);
    }
}

// Class equipment, swimming and short client-side death poses share the skinned soldier.
void SceneRenderer::drawPlayers(const QJsonObject &snapshot, const QString &playerId, float dt) {
    const auto players = snapshot["players"].toArray();
    const auto beams = snapshot["beams"].toArray();
    animator.retain(players);
    for (const auto entry : players) {
        const auto p = entry.toObject();
        if (p["id"].toString() == playerId)
            continue;
        const bool warden = p["class"].toString() == "warden";
        const auto &animation = animator.update(p, beams, dt);
        if (animation.death > 1.4f)
            continue;
        QMatrix4x4 body;
        body.translate(animation.rendered);
        body.rotate(yawDegrees(real(p, "angle")), 0, 1, 0);
        if (animation.death > 0) {
            body.translate(0, .18f, 0);
            body.rotate(std::min(1.f, animation.death * 3.f) * 88.f, 0, 0, 1);
        }
        if (warden)
            body.scale(1.06f, 1.f, 1.06f);
        // Crouching operators are drawn compressed to their lower hit box.
        if (p["crouching"].toBool())
            body.scale(1.f, .69f, 1.f);
        const bool swimming = real(p, "immersion") > .35f;
        if (swimming)
            body.rotate(-12.f, 0, 0, 1);
        bs_actor_pose(time, swimming ? time * .8f : animation.phase, swimming ? .65f : animation.movement,
                      swimming ? 0.f : animation.air, animation.recoil, actorVertices.data(),
                      int(actorVertices.size()));
        upload(actorMesh, actorVertices, GL_STREAM_DRAW);
        const QVector3D tint = teamColor(p["team"].toInt());
        draw(actorMesh, body, tint, 0, warden ? .95f : 1.08f);
        draw(models[warden ? BS_MODEL_WARDEN_GEAR : BS_MODEL_RANGER_GEAR], body, tint);
        QMatrix4x4 held = body;
        held.translate(.36f - animation.recoil * .04f, 1.12f, 0);
        held.rotate(real(p, "pitch") * 180 / kPi + animation.recoil * 4, 0, 0, 1);
        held.scale(.58f);
        draw(models[warden ? BS_MODEL_SHOTGUN : BS_MODEL_SMG], held, tint);
    }
}

// Drones, cores and towers. Tower heads track the nearest enemy player in range.
void SceneRenderer::drawStructures(const QJsonObject &snapshot) {
    for (const auto entry : snapshot["entities"].toArray()) {
        const auto e = entry.toObject();
        if (real(e, "hp") <= 0)
            continue;
        const float ex = real(e, "x"), ey = real(e, "y");
        const int team = e["team"].toInt();
        const auto tint = teamColor(team);
        const QString kind = e["kind"].toString();
        if (kind == "drone")
            drawModel(BS_MODEL_DRONE, ex, real(e, "z"), ey, team == 0 ? 0 : kPi, tint);
        else if (kind == "core")
            drawModel(BS_MODEL_REACTOR, ex, real(e, "z"), ey, 0, tint);
        else if (kind == "tower") {
            drawModel(BS_MODEL_TURRET_BASE, ex, real(e, "z"), ey, 0, tint);
            float aim = team == 0 ? 0 : kPi;
            float nearest = 8;
            for (const auto player : snapshot["players"].toArray()) {
                const auto p = player.toObject();
                const float dx = real(p, "x") - ex, dy = real(p, "y") - ey, d = std::hypot(dx, dy);
                if (p["team"].toInt() != team && real(p, "hp") > 0 && d < nearest) {
                    nearest = d;
                    aim = std::atan2(dy, dx);
                }
            }
            drawModel(BS_MODEL_TURRET_HEAD, ex, real(e, "z") + 1.40f, ey, aim, tint);
        }
    }
}

// Server-confirmed tracers, depth-tested against the map.
void SceneRenderer::drawTracers(const QJsonObject &snapshot) {
    for (const auto value : snapshot["beams"].toArray()) {
        const auto b = value.toObject();
        const QVector3D start(real(b, "x"), float(b.value("z").toDouble(1.25)), real(b, "y"));
        const QVector3D end(real(b, "ex"), float(b.value("ez").toDouble(1.25)), real(b, "ey"));
        const QVector3D delta = end - start;
        const float length = delta.length();
        if (length < .01f)
            continue;
        QMatrix4x4 beam;
        beam.translate((start + end) / 2);
        beam.rotate(QQuaternion::rotationTo({1, 0, 0}, delta.normalized()));
        beam.scale(length, .012f, .012f);
        draw(models[BS_MODEL_CUBE], beam, teamColor(b["team"].toInt()), 1.f);
    }
}

// First-person class weapon with confirmed recoil, sprint lowering and landing motion.
void SceneRenderer::drawViewModel(const QJsonObject &self, const FrameView &view, const QVector3D &forward,
                                  float bob) {
    if (real(self, "hp") <= 0)
        return;
    glClear(GL_DEPTH_BUFFER_BIT);
    const QVector3D right(-std::sin(view.yaw), 0, std::cos(view.yaw));
    const QVector3D origin = camera + forward * (.40f - recoil * .065f) + right * .20f +
                             QVector3D(0, -.18f + bob - landingKick - sprintLower, 0);
    QMatrix4x4 weapon;
    weapon.translate(origin);
    weapon.rotate(yawDegrees(view.yaw), 0, 1, 0);
    weapon.rotate(view.pitch * 180 / kPi, 0, 0, 1);
    weapon.rotate(recoil * 7.f + (view.moving ? std::sin(time * 5.5f) * 1.3f : 0.f), 0, 0, 1);
    weapon.scale(.78f);
    draw(models[self["class"].toString() == "warden" ? BS_MODEL_SHOTGUN : BS_MODEL_SMG], weapon,
         teamColor(self["team"].toInt()), 0, 1.12f);
    if (recoil > .6f) {
        QMatrix4x4 flash = weapon;
        flash.translate(self["class"].toString() == "warden" ? .84f : .60f, .02f, 0);
        flash.rotate(time * 840, 1, 0, 0);
        flash.scale(.15f, .10f, .10f);
        draw(models[BS_MODEL_CUBE], flash, {1.f, .74f, .20f}, 1.f);
    }
}

// Copies the off-screen frame to the target framebuffer.
void SceneRenderer::present(const QSize &outputSize, unsigned targetFbo) {
    glBindFramebuffer(GL_FRAMEBUFFER, targetFbo);
    glViewport(0, 0, outputSize.width(), outputSize.height());
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_BLEND);
    presentShader->bind();
    presentShader->setUniformValue("scene", 0);
    presentShader->setUniformValue("time", time);
    presentShader->setUniformValue("underwater", underwater);
    presentShader->setUniformValue("waterColor", waterColor);
    glBindTexture(GL_TEXTURE_2D, framebuffer->texture());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glBindBuffer(GL_ARRAY_BUFFER, screenQuad.vbo);
    for (const char *name : {"position", "uv"})
        presentShader->enableAttributeArray(presentShader->attributeLocation(name));
    presentShader->setAttributeBuffer("position", GL_FLOAT, offsetof(BsVertex, position), 3,
                                      sizeof(BsVertex));
    presentShader->setAttributeBuffer("uv", GL_FLOAT, offsetof(BsVertex, uv), 2, sizeof(BsVertex));
    glDrawArrays(GL_TRIANGLES, 0, 6);
    for (const char *name : {"position", "uv"})
        presentShader->disableAttributeArray(presentShader->attributeLocation(name));
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    presentShader->release();
}

// Camera-centred sky: no parallax, depth writes or dependence on world bounds.
void SceneRenderer::drawSky(const FrameView &view, const QSize &size) {
    glDisable(GL_DEPTH_TEST);
    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);
    skyShader->bind();
    QVector3D forward(std::cos(view.yaw) * std::cos(view.pitch), std::sin(view.pitch),
                      std::sin(view.yaw) * std::cos(view.pitch));
    QVector3D right(-std::sin(view.yaw), 0, std::cos(view.yaw));
    skyShader->setUniformValue("forward", forward);
    skyShader->setUniformValue("right", right);
    skyShader->setUniformValue("up", QVector3D::crossProduct(right, forward));
    skyShader->setUniformValue("aspect", float(size.width()) / size.height());
    skyShader->setUniformValue("time", time);
    glBindBuffer(GL_ARRAY_BUFFER, screenQuad.vbo);
    skyShader->enableAttributeArray("position");
    skyShader->enableAttributeArray("uv");
    skyShader->setAttributeBuffer("position", GL_FLOAT, offsetof(BsVertex, position), 3, sizeof(BsVertex));
    skyShader->setAttributeBuffer("uv", GL_FLOAT, offsetof(BsVertex, uv), 2, sizeof(BsVertex));
    glDrawArrays(GL_TRIANGLES, 0, 6);
    skyShader->disableAttributeArray("position");
    skyShader->disableAttributeArray("uv");
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    skyShader->release();
    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
}

void SceneRenderer::drawLiquids(const QJsonObject &map) {
    underwater = 0;
    waterColor = {.13f, .30f, .29f};
    auto liquids = map["liquids"].toArray();
    std::vector<QJsonObject> sorted;
    for (const auto value : liquids)
        sorted.push_back(value.toObject());
    auto centre = [](const QJsonObject &v) {
        const auto r = v["rect"].toArray();
        return QVector3D(float((r[0].toDouble() + r[2].toDouble()) * .5), real(v, "surface"),
                         float((r[1].toDouble() + r[3].toDouble()) * .5));
    };
    std::sort(sorted.begin(), sorted.end(), [&](const QJsonObject &a, const QJsonObject &b) {
        return (centre(a) - camera).lengthSquared() > (centre(b) - camera).lengthSquared();
    });
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);
    drawingLiquid = true;
    shader->setUniformValue("liquid", true);
    for (const auto &v : sorted) {
        const auto r = v["rect"].toArray(), c = v["color"].toArray(), flow = v["current"].toArray();
        QVector3D color(float(c[0].toDouble(.13)), float(c[1].toDouble(.30)), float(c[2].toDouble(.29)));
        if (camera.x() >= r[0].toDouble() && camera.x() <= r[2].toDouble() && camera.z() >= r[1].toDouble() &&
            camera.z() <= r[3].toDouble() && camera.y() < real(v, "surface") &&
            camera.y() > real(v, "bottom")) {
            underwater = 1;
            waterColor = color;
        }
        shader->setUniformValue("flow", QVector2D(float(flow[0].toDouble()), float(flow[1].toDouble())));
        // A single top face avoids double blending the top and underside of a thin cube.
        std::vector<BsVertex> surface(6);
        const int corners[6][2] = {{0, 0}, {0, 1}, {1, 1}, {0, 0}, {1, 1}, {1, 0}};
        for (int i = 0; i < 6; i++) {
            surface[i].position[0] = float(r[corners[i][0] * 2].toDouble());
            surface[i].position[1] = real(v, "surface");
            surface[i].position[2] = float(r[1 + corners[i][1] * 2].toDouble());
            surface[i].normal[1] = 1;
            surface[i].material = 6;
        }
        upload(liquidMesh, surface, GL_STREAM_DRAW);
        draw(liquidMesh, QMatrix4x4(), color);
    }
    drawingLiquid = false;
    shader->setUniformValue("liquid", false);
    glDepthMask(GL_TRUE);
    glEnable(GL_CULL_FACE);
    glDisable(GL_BLEND);
}
