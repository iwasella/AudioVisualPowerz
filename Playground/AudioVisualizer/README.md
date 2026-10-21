# Audio Visualizer

The original OpenGL audio visualization demo, organized as a standalone mini project. It loads and plays audio using AVFoundation and visualizes the decoded waveform with an OpenGL fragment shader.

Build from the repository root:

```sh
cmake -S Playground/AudioVisualizer -B build-audio-visualizer
cmake --build build-audio-visualizer
open build-audio-visualizer/audiovisualpowerz.app
```

Requires macOS, CMake, and GLFW (`brew install cmake glfw`). Use **O** to open a file, **Space** to play or pause, or drag a file onto the window.
