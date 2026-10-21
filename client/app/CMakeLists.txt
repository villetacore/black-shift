set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.4 REQUIRED COMPONENTS Widgets Network OpenGL OpenGLWidgets Multimedia)

# Everything except main(), shared by the game and the integration test.
qt_add_library(blackshift_client STATIC
  src/app/GameWidget.cpp src/app/GameWidget.h
  src/audio/AudioEngine.cpp src/audio/AudioEngine.h
  src/game/Json.h
  src/game/MatchState.cpp src/game/MatchState.h
  src/input/InputController.cpp src/input/InputController.h
  src/net/Protocol.h
  src/net/ServerConnection.cpp src/net/ServerConnection.h
  src/render/ActorAnimator.cpp src/render/ActorAnimator.h
  src/render/Models.h
  src/render/SceneRenderer.cpp src/render/SceneRenderer.h
  src/render/WorldMesh.cpp src/render/WorldMesh.h
  src/ui/DeploymentPanel.cpp src/ui/DeploymentPanel.h
  src/ui/RoomPanel.cpp src/ui/RoomPanel.h
  src/ui/HudPainter.cpp src/ui/HudPainter.h
  src/ui/MenuPainter.cpp src/ui/MenuPainter.h
  src/ui/Theme.cpp src/ui/Theme.h)
target_include_directories(blackshift_client PUBLIC src)
target_compile_definitions(blackshift_client PUBLIC BLACKSHIFT_VERSION="${PROJECT_VERSION}")
target_link_libraries(blackshift_client PUBLIC
  Qt6::Widgets Qt6::Network Qt6::OpenGL Qt6::OpenGLWidgets Qt6::Multimedia blackshift::core)

set(MATERIAL_SHEET "${PROJECT_SOURCE_DIR}/assets/textures/foundry-materials-v2.png")
set_source_files_properties("${MATERIAL_SHEET}" PROPERTIES QT_RESOURCE_ALIAS textures/painted-materials.png)
set(WORKSHOP_SHEET "${PROJECT_SOURCE_DIR}/assets/textures/industrial-materials-v3.png")
set_source_files_properties("${WORKSHOP_SHEET}" PROPERTIES QT_RESOURCE_ALIAS textures/workshop-materials.png)
set(WATER_TILE "${PROJECT_SOURCE_DIR}/assets/textures/cooling-water.bmp")
set_source_files_properties("${WATER_TILE}" PROPERTIES QT_RESOURCE_ALIAS textures/cooling-water.bmp)
set(CLIENT_RESOURCES
  "${MATERIAL_SHEET}" "${WATER_TILE}" "${WORKSHOP_SHEET}"
  shaders/world.vert shaders/world.frag
  shaders/present.vert shaders/present.frag shaders/sky.frag)

foreach(SOUND smg shotgun step reload hit kill hurt dash pulse relay warning victory)
  set(SOUND_FILE "${PROJECT_SOURCE_DIR}/assets/audio/${SOUND}.wav")
  set_source_files_properties("${SOUND_FILE}" PROPERTIES QT_RESOURCE_ALIAS "audio/${SOUND}.wav")
  list(APPEND CLIENT_RESOURCES "${SOUND_FILE}")
endforeach()

# Resources are added to each executable so their static initialisers are always linked.
function(blackshift_add_resources target)
  qt_add_resources(${target} ${target}_resources PREFIX "/" FILES ${CLIENT_RESOURCES})
endfunction()

qt_add_executable(blackshift MACOSX_BUNDLE src/main.cpp)
target_link_libraries(blackshift PRIVATE blackshift_client)
blackshift_add_resources(blackshift)
if(APPLE)
  set_target_properties(blackshift PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "Black Shift"
    MACOSX_BUNDLE_GUI_IDENTIFIER "io.github.blackshift"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}")
endif()
install(TARGETS blackshift RUNTIME DESTINATION bin BUNDLE DESTINATION .)

if(BLACKSHIFT_CLIENT_TESTS)
  find_package(Qt6 REQUIRED COMPONENTS Test)
  qt_add_executable(blackshift-client-test tests/client_test.cpp)
  target_link_libraries(blackshift-client-test PRIVATE blackshift_client Qt6::Test)
  blackshift_add_resources(blackshift-client-test)
  add_test(NAME native_client COMMAND blackshift-client-test)
endif()
