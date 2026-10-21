# Purpose 
Documenting things I learned for funsies

# First Project
I made the screen purple and wide
<img width="1510" height="610" alt="Play1" src="https://github.com/user-attachments/assets/bee10cec-e44f-40f0-ac9e-07e237b0b2bf" />

# Notes: Audio Visualizer Tools

## What GLFW does

GLFW creates the desktop window and handles input such as keyboard and mouse events. In this project, it opens the window where the visualizer runs. It is a small windowing library, rather than a complete app framework like Flutter or Streamlit.

## What OpenGL does

OpenGL is a graphics API that lets the program send drawing work to the GPU. We use it to display the moving audio visuals in the GLFW window.

The visualizer uses an OpenGL **shader**: a small program that runs on the GPU. Our fragment shader runs for the pixels on the screen. It samples a texture containing audio waveform data and uses those samples to shape the colored waves.

## How the pieces fit together

- **C++** coordinates the application and graphics logic.
- **Objective-C++** (`.mm`) lets that C++ code call macOS frameworks.
- **GLFW** creates the window and handles input.
- **AVFoundation** decodes and plays audio files.
- **OpenGL and its shader** draw the animated visuals using the GPU.
- **CMake** builds the code and packages it as a macOS app.

The app is packaged as a `.app` bundle so macOS can recognize and open it like a regular desktop application. GLFW supplies the window inside that app; it does not package or launch the app by itself.

