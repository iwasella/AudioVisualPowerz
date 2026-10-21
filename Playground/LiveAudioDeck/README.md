# Live Audio Deck

A small macOS DJ-style audio project built with C++, GLFW, OpenGL, and AVFoundation. Load a track, select a crop range by dragging across the waveform, then play that section forward or backward. Pitch and playback speed can be changed while the track is playing.

## Build and launch

From the repository root:

```sh
cmake -S Playground/LiveAudioDeck -B build-live-deck
cmake --build build-live-deck
open build-live-deck/liveaudiodeck.app
```

Requires macOS, CMake, and GLFW (`brew install cmake glfw`). AVFoundation handles the supported audio decoding.

## Controls

- **O**: open an audio file; dragging a file onto the window also loads it.
- **Space**: play or pause the selected range.
- **Drag** across the waveform to choose a crop range.
- **C**: reset the crop to the whole track.
- **R**: switch between forward and reverse, restarting the selected range.
- **Left / Right**: lower or raise pitch by one semitone.
- **Down / Up**: lower or raise playback speed by 0.05×.
- **Escape**: quit.

Pitch is adjusted with AVAudioUnitTimePitch while speed is adjusted through its playback-rate control. Reverse playback is made by reversing the selected PCM samples before sending them to the audio player. OpenGL displays the waveform and highlights the crop selection.
