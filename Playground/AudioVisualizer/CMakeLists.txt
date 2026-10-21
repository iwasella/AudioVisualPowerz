cmake_minimum_required(VERSION 3.20)
project(AudioVisualPowerz LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_library(GLFW_LIBRARY glfw PATHS /opt/homebrew/lib /usr/local/lib REQUIRED)

add_executable(audiovisualpowerz
    src/main.mm
    ../../src/glad.cpp
)
set_target_properties(audiovisualpowerz PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.audiovisualpowerz.demo"
    MACOSX_BUNDLE_BUNDLE_NAME "AudioVisualPowerz"
)
target_include_directories(audiovisualpowerz PRIVATE ../../include /opt/homebrew/include)
target_link_libraries(audiovisualpowerz PRIVATE ${GLFW_LIBRARY}
    "-framework OpenGL" "-framework Cocoa" "-framework AVFoundation"
    "-framework CoreAudio" "-framework AudioToolbox" "-framework UniformTypeIdentifiers")
target_compile_options(audiovisualpowerz PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
