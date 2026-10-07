#pragma once
#include "blackshift_core.h"
#include "render/ActorAnimator.h"
#include <QJsonObject>
#include <QMatrix4x4>
#include <QOpenGLFunctions>
#include <QSize>
#include <QString>
#include <array>
#include <memory>
#include <vector>

class QOpenGLShaderProgram;
class QOpenGLFramebufferObject;

// First-person camera and view-model state for one frame. Positions use map coordinates.
struct FrameView {
    float x = 0, y = 0, z = 0;
    float yaw = 0, pitch = 0;
    // Eye height above the feet: lower while crouching.
    float eye = 1.48f;
    // Seconds since start; drives animation.
    float seconds = 0;
    bool firing = false;
    bool moving = false;
};

// Vertical field of view in degrees; the HUD converts accuracy cones to pixels with it.
inline constexpr float kVerticalFieldOfView = 62.f;

// OpenGL 2.1 renderer for the 3D scene: baked world geometry, objectives, pickups,
// skinned players, structures, tracers and the first-person weapon.
// Needs a current OpenGL context for every call, including destruction.
class SceneRenderer final : protected QOpenGLFunctions {
  public:
    SceneRenderer();
    ~SceneRenderer();

    bool initialize();
    bool ready() const {
        return initialized;
    }
    QString error() const {
        return failure;
    }
    // Renders one frame into `targetFbo`. The world mesh is rebuilt when `map` changes.
    void render(const QJsonObject &map, const QJsonObject &snapshot, const QString &playerId,
                const FrameView &view, const QSize &outputSize, unsigned targetFbo);

  private:
    // A vertex buffer sorted by material, drawn with one call per material texture.
    struct Mesh {
        unsigned vbo = 0;
        int count = 0;
        std::array<int, BS_MATERIAL_COUNT> starts{}, counts{};
    };

    bool initialized = false;
    QString failure;
    std::unique_ptr<QOpenGLShaderProgram> shader, presentShader, skyShader;
    // The scene renders off-screen first, then is copied to the target framebuffer.
    std::unique_ptr<QOpenGLFramebufferObject> framebuffer;
    std::array<Mesh, BS_MODEL_COUNT> models;
    Mesh world, screenQuad, actorMesh, liquidMesh;
    unsigned waterTexture = 0;
    bool drawingLiquid = false;
    std::array<unsigned, BS_MATERIAL_COUNT> textures{};
    std::vector<BsVertex> actorVertices;
    ActorAnimator animator;
    QJsonObject currentMap;
    float time = 0, previousTime = 0;
    QVector3D camera, waterColor;
    float underwater = 0, recoil = 0;
    int lastFireAt = 0;
    bool previousGrounded = true;
    float landingKick = 0, sprintLower = 0;
    QString lastPlayerId;
    void drawSky(const FrameView &view, const QSize &size);
    void drawLiquids(const QJsonObject &map);

    bool loadShaders();
    bool loadTextures();
    void upload(Mesh &mesh, const std::vector<BsVertex> &vertices, unsigned usage);
    void destroy(Mesh &mesh);
    void draw(const Mesh &mesh, const QMatrix4x4 &model, const QVector3D &tint, float glow = 0,
              float brightness = 1, bool baked = false);
    void drawModel(BsModel model, float x, float y, float z, float yaw, const QVector3D &tint);

    void drawObjective(const QJsonObject &snapshot);
    void drawSupplies(const QJsonObject &snapshot);
    void drawPlayers(const QJsonObject &snapshot, const QString &playerId, float dt);
    void drawStructures(const QJsonObject &snapshot);
    void drawTracers(const QJsonObject &snapshot);
    void drawViewModel(const QJsonObject &self, const FrameView &view, const QVector3D &forward, float bob);
    void present(const QSize &outputSize, unsigned targetFbo);
};
